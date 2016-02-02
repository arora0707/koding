kd                          = require 'kd'
AdminAppView                = require 'admin/views/customviews/adminappview'
StackCatalogMainTabPaneView = require './stackcatalogmaintabpaneview'


module.exports = class StackCatalogModalView extends AdminAppView


  constructor: (options = {}, data) ->

    options.paneViewClass = StackCatalogMainTabPaneView

    super options, data

    @overlay.once 'click', @bound 'handleOverlayClick'


  handleOverlayClick: ->

    activePane = @tabs.getActivePane()

    return @destroy()  if activePane.name is 'Your Stacks'

    { mainView }    = activePane
    { editorView }  = mainView?.defineStackView?.stackTemplateView

    unless editorView?.getAce().isContentChanged()
      @destroy()