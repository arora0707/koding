class NCopyUrlView extends JView

  constructor: ->
    super

    @path = FSHelper.plainPath @getData().path
    @publicPath = @path.replace \
      ///.*\/(.*\.#{KD.config.userSitesDomain})\/(.*)///, '//$1/$2'

    @inputUrlLabel  = new KDLabelView
      cssClass      : 'public-url-label'
      title         : 'Public URL'
      click         :=>
        @focusAndSelectAll()

    @inputUrl       = new KDInputView
      label         : @inputUrlLabel
      cssClass      : 'public-url-input'

    @inputUrl.setValue @publicPath

  focusAndSelectAll:->
    @inputUrl.setFocus()
    @inputUrl.selectAll()

  viewAppended:->
    @setClass "copy-url-wrapper"
    super

  pistachio:->
    hasNoPublicPath = @publicPath is @path

    if hasNoPublicPath
      """
      <div class="public-url-warning">This #{@getData().type} can not be reached over a public URL</div>
      """
    else
      """
      {{> @inputUrlLabel}}
      {{> @inputUrl}}
      """