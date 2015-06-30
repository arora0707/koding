package tunnelproxymanager

import (
	"errors"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/route53"
	"github.com/koding/logging"
)

const (
	hostedZoneComment       = "Hosted zone for tunnel proxies"
	validStateForHostedZone = "INSYNC" // taken from aws response
)

var (
	errHostedZoneNotFound           = errors.New("hosted zone not found")
	errDeadlineReachedForChangeInfo = errors.New("deadline for change info")
)

// RecordManager manages Route53 records
type RecordManager struct {
	// aws services
	route53 *route53.Route53

	// application wide parameters
	hostedZone *route53.HostedZone
	region     string

	hostedZoneConf HostedZone

	// general usage
	log logging.Logger
}

// NewRecordManager creates a RecordManager
func NewRecordManager(config *aws.Config, log logging.Logger, region string, hostedZoneConf HostedZone) *RecordManager {
	return &RecordManager{
		route53:        route53.New(config),
		log:            log.New("recordmanager"),
		region:         region,
		hostedZoneConf: hostedZoneConf,
	}
}

// Init initializes record manager's prerequisites
func (r *RecordManager) Init() error {
	r.log.Debug("Configuring...")

	if err := r.ensureHostedZone(); err != nil {
		return err
	}

	r.log.Info("init is done")
	return nil
}

func (r *RecordManager) ensureHostedZone() error {
	hostedZoneLogger := r.log.New("HostedZone").New("name", r.hostedZoneConf.Name)
	hostedZoneLogger.Debug("Trying to get existing Hosted Zone")

	err := r.getHostedZone(hostedZoneLogger)
	if err == nil {
		hostedZoneLogger.Debug("Hosted Zone exists..")
		return nil
	}

	if err != errHostedZoneNotFound {
		return err
	}

	hostedZoneLogger.Debug("Not found, creating...")
	return r.createHostedZone(hostedZoneLogger)
}

// getHostedZone fetches all hosted zones from account and iterates over them
// until it finds the respective one
func (r *RecordManager) getHostedZone(hostedZoneLogger logging.Logger) error {
	const maxIterationCount = 100
	iteration := 0

	// for pagination
	var nextMarker *string

	// try to get our hosted zone
	for {
		// just be paranoid about remove api calls, dont harden too much
		if iteration == maxIterationCount {
			return errors.New("iteration terminated")
		}

		log := hostedZoneLogger.New("iteration", iteration)

		iteration++

		log.Debug("Fetching hosted zone")
		listHostedZonesResp, err := r.route53.ListHostedZones(
			&route53.ListHostedZonesInput{
				Marker: nextMarker,
			}, // we dont have anything to filter
		)
		if err != nil {
			return err
		}

		if listHostedZonesResp == nil || listHostedZonesResp.HostedZones == nil {
			return errors.New("malformed response - reponse or hosted zone is nil")
		}

		for _, hostedZone := range listHostedZonesResp.HostedZones {
			if hostedZone == nil || hostedZone.CallerReference == nil {
				continue
			}

			if *hostedZone.CallerReference == r.hostedZoneConf.CallerReference {
				r.hostedZone = hostedZone
				return nil
			}
		}

		// if our result set is truncated we can try to fetch again, but if we
		// reach to end, nothing to do left
		if !*listHostedZonesResp.IsTruncated {
			return errHostedZoneNotFound
		}

		// assign next marker
		nextMarker = listHostedZonesResp.NextMarker
	}
}

// createHostedZone creates hosted zone and makes sure that it is in to be used
// state
func (r *RecordManager) createHostedZone(hostedZoneLogger logging.Logger) error {
	hostedZoneLogger.Debug("create hosted zone started")

	// CreateHostedZone is not idempotent, multiple calls to this function
	// result in duplicate records, fyi
	resp, err := r.route53.CreateHostedZone(&route53.CreateHostedZoneInput{
		CallerReference: aws.String(r.hostedZoneConf.CallerReference),
		Name:            aws.String(r.hostedZoneConf.Name),
		HostedZoneConfig: &route53.HostedZoneConfig{
			Comment: aws.String(hostedZoneComment),
		},
	})
	if err != nil {
		return err
	}

	if resp == nil || resp.ChangeInfo == nil {
		return errors.New("malformed response, resp is nil")
	}

	changeInfo := resp.ChangeInfo
	deadline := time.After(time.Minute * 5) // at most i've seen ~3min

	// make sure it propagated
	for {
		// if our change propagated, we can return
		if changeInfo.Status != nil && *changeInfo.Status == validStateForHostedZone {
			hostedZoneLogger.Debug("hosted zone status is valid")
			break
		}

		select {
		case <-deadline:
			return errDeadlineReachedForChangeInfo
		default:
			time.Sleep(time.Second * 3) // poor man's throttling
			hostedZoneLogger.New("changeInfoID", *changeInfo.ID).Debug("fetching latest status")
			getChangeResp, err := r.route53.GetChange(&route53.GetChangeInput{
				ID: changeInfo.ID,
			})
			if err != nil {
				return err
			}

			if getChangeResp == nil || getChangeResp.ChangeInfo == nil {
				return errors.New("malformed response, getChangeResp is nil")
			}

			changeInfo = getChangeResp.ChangeInfo
		}
	}

	r.hostedZone = resp.HostedZone
	hostedZoneLogger.Debug("create hosted finished successfully")
	return nil
}

// UpsertRecordSet updates record set for current ResourceRecordSet
func (r *RecordManager) UpsertRecordSet(instances []*string) error {
	if r.hostedZone == nil {
		return errors.New("hosted zone is not set")
	}

	resourceRecords := make([]*route53.ResourceRecord, 0)
	for _, instance := range instances {
		resourceRecords = append(resourceRecords, &route53.ResourceRecord{
			Value: instance,
		})
	}
	params := &route53.ChangeResourceRecordSetsInput{
		ChangeBatch: &route53.ChangeBatch{
			// contains one Change element for each resource record set that you
			// want to create or delete.
			Changes: []*route53.Change{
				&route53.Change{
					Action: aws.String("UPSERT"),
					ResourceRecordSet: &route53.ResourceRecordSet{
						// The domain name of the current resource record set.
						Name: aws.String(r.hostedZoneConf.Name),
						// The type of the current resource record set.
						Type: aws.String("A"),
						// Latency-based resource record sets only: Among
						// resource record sets that have the same combination
						// of DNS name and type, a value that specifies the AWS
						// region for the current resource record set.
						Region: aws.String(r.region),
						// that contains the resource records for the current
						// resource record set.
						ResourceRecords: resourceRecords,
						// Weighted, Latency, Geo, and Failover resource record sets only
						// use region name as identifer
						SetIdentifier: aws.String(r.region),
						// The cache time to live for the current resource record set.
						TTL: aws.Long(1),
					},
				},
			},
			Comment: aws.String(
				fmt.Sprintf(
					"Record set for zone: %s region: %s",
					r.hostedZoneConf.Name,
					r.region,
				),
			),
		},
		HostedZoneID: r.hostedZone.ID,
	}

	_, err := r.route53.ChangeResourceRecordSets(params)
	return err
}
