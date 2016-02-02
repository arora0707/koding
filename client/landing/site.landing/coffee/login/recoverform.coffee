kd = require 'kd.js'
LoginViewInlineForm = require './loginviewinlineform'
LoginInputView      = require './logininputview'

module.exports = class RecoverInlineForm extends LoginViewInlineForm

  constructor:->

    super
    @usernameOrEmail = new LoginInputView
      inputOptions    :
        name          : "email"
        placeholder   : "Email address"
        testPath      : "recover-password-input"
        validate      :
          container   : this
          rules       :
            required  : yes
          messages    :
            required  : "Please enter your email."

    @button = new kd.ButtonView
      title       : "RECOVER PASSWORD"
      style       : "solid medium green"
      type        : 'submit'
      loader      : yes


  reset: ->

      super
      @button.hideLoader()

  pistachio:->

    """
    <div>{{> @usernameOrEmail}}</div>
    <div>{{> @button}}</div>
    """