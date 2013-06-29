jraphical = require 'jraphical'
module.exports = class JDomain extends jraphical.Module

  DomainManager = require 'domainer'
  {secure, ObjectId}  = require 'bongo'


  domainManager = new DomainManager
  JAccount  = require './account'
  JVM       = require './vm'

  @share()

  @set
    softDelete      : yes

    sharedMethods   :
      static        : ['one', 'count', 'createDomain', 'bindVM', 'findByAccount', 'fetchByDomain', 'fetchByUserId',
                       'isDomainAvailable','addNewDNSRecord', 'removeDNSRecord', 'registerDomain', 'fetchBlockList',
                       'updateWhiteList', 'updateBlockList']

    indexes         :
      domain        : 'unique'
      hostnameAlias : 'sparse'

    schema          :
      domain        :
        type        : String
        required    : yes
        set         : (value)-> value.toLowerCase()

      hostnameAlias : [String]

      proxy         :
        mode        : String # TODO: enumerate all possible modes
        username    : String
        serviceName : String
        key         : String
        fullUrl     : String

      loadBalancer  :
        persistence :
          type      : String
          enum      : ['invalid persistence mode',[
            'disabled'
            # 'cookie'
            # 'sourceAdress'
          ]]
          default   : 'disabled'
        mode        :
          type      : String
          enum      : ['invalid load balancer mode',[
            'roundrobin'
            # 'sticky'
            # 'weighted'
            # 'weighted-roundrobin'
          ]]
          default   : 'roundrobin'
        index       :
          type      : Number
          default   : 0

      orderId       :
        recurly     : String
        resellerClub: String

      regYears      : Number

      createdAt     :
        type        : Date
        default     : -> new Date
      modifiedAt    :
        type        : Date
        default     : -> new Date

  @createDomain: secure (client, options={}, callback)->
    model = new JDomain options
    model.save (err) ->
      callback? err, model

  @findByAccount: secure (client, selector, callback)->
    @all selector, (err, domains) ->
      if err then console.log err
      domainList = ({name:domain.domain, id:domain.getId(), vms:domain.vms} for domain in domains)
      callback? err, domains

  @isDomainAvailable = (domainName, tld, callback)->
    domainManager.domainService.isDomainAvailable domainName, tld, (err, isAvailable)->
      callback err, isAvailable

  @registerDomain = secure (client, data, callback)->
    #default user info / all domains are under koding account.
    params =
      domainName         : data.domainName
      years              : data.years
      customerId         : "9663202"
      regContactId       : "28083911"
      adminContactId     : "28083911"
      techContactId      : "28083911"
      billingContactId   : "28083911"
      invoiceOption      : "NoInvoice"
      protectPrivacy     : no

    domainManager.domainService.registerDomain params, (err, data)=>
      if err then return callback err, data

      if data.actionstatus is "Success"
        @createDomain client,
          domain   : data.description
          regYears : params.years
          orderId  :
            resellerClub : data.entityid
          , (err, model) =>
            callback err, model
      else
          callback "Domain registration failed"


  @addNewDNSRecord = secure ({connection:{delegate}}, data, callback)->
    newRecord =
      mode          : "vm"
      username      : delegate.profile.nickname
      domainName    : data.domainName
      linkedVM      : data.selectedVM

    domainManager.dnsManager.registerNewRecordToProxy newRecord, (response)=>
      domain =
        domain       : newRecord.domainName
        orderId      : "0" # when forwarding we got no orderid
        linkURL      : newRecord.domainName
        linkedVM     : newRecord.linkedVM

      @create delegate, domain, (err, record) =>
        callback null, record


  @removeDNSRecord = secure ({connection:{delegate}}, data, callback)->
    record =
      username      : client.context.user
      domainName : data.domainName
      mode          : "vm"

    # not working should talk with farslan
    domainManager.dnsManager.removeDNSRecordFromProxy record, callback

  @bindVM = secure ({connection:{delegate}}, params, callback)->
    KD.remote.api.JVM.someData {name:params.vmName}, {hostname:1}, (err, vm)->
      console.log vm

    ###
    record =
      mode          : "vm"
      username      : delegate.profile.nickname
      domainName    : params.domainName
      linkedVM      : params.vmName

    if params.state
      domainManager.dnsManager.registerNewRecordToProxy record, (response)=>
        @update {"domain":params.domainName}, {'$push': {"hostnameAlias":params.vmName}}
        callback "Your domain is now connected to #{params.vmName} VM." if response?.host?

    else
      domainManager.dnsManager.removeDNSRecordFromProxy record, (response)=>
        @update {"domain":params.domainName}, {'$pull': {"hostnameAlias":params.vmName}}
        callback "Your domain is now disconnected from the #{params.vmName} VM." if response?.res?
    ###

  @updateWhiteList = (params, callback)->
    if params.op == 'addToSet'
      @update {domain:params.domainName}, {'$addToSet':{'whiteList':params.value}}, (err, obj)-> callback err
    else
      @update {domain:params.domainName}, {'$pull':{'whiteList':params.value}}, (err, obj)-> callback err


  @updateBlockList = (params, callback)->
    if params.op == 'addToSet'
      @update {domain:params.domainName}, {'$addToSet':{'blockList':params.value}}, (err, obj)-> callback err
    else
      @update {domain:params.domainName}, {'$pull':{'blockList':params.value}}, (err, obj)-> callback err
