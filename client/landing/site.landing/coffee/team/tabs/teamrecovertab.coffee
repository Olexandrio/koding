kd                = require 'kd.js'
$                 = require 'jquery'
utils             = require './../../core/utils'
JView             = require './../../core/jview'
MainHeaderView    = require './../../core/mainheaderview'
RecoverInlineForm = require './../../login/recoverform'

track = (action) ->

  category = 'Team'
  label    = 'RecoverForm'
  utils.analytics.track action, { category, label }


module.exports = class TeamRecoverTab extends kd.TabPaneView

  JView.mixin @prototype

  constructor: (options = {}, data)->

    super options, data

    { mainController } = kd.singletons
    { group }          = kd.config

    @header = new MainHeaderView
      cssClass : 'team'
      navItems : [
        { title : 'Blog',     href : 'http://blog.koding.com',          name : 'blog' }
        { title : 'Features', href : 'https://www.koding.com/Features', name : 'features', attributes: target: '_blank' }
      ]

    @logo = utils.getGroupLogo()

    @form = new RecoverInlineForm
      cssClass : 'login-form clearfix'
      callback : @bound 'doRecover'

    @form.button.unsetClass 'solid medium green'
    @form.button.setClass 'TeamsModal-button TeamsModal-button--green'


  setFocus: -> @form.usernameOrEmail.input.setFocus()


  doRecover: (formData) ->

    track 'submitted recover form'

    { email, mode } = formData
    group = utils.getGroupNameFromLocation()

    $.ajax
      url         : '/Recover'
      data        : { email, _csrf : Cookies.get('_csrf'), group, mode }
      type        : 'POST'
      error       : (xhr) =>
        {responseText} = xhr
        new kd.NotificationView title : responseText
        @form.button.hideLoader()
      success     : =>
        @form.button.hideLoader()
        @form.reset()

        new kd.NotificationView
          cssClass : 'recoverConfirmation'
          title    : 'Check your email'
          content  : 'We\'ve sent you a password recovery code.'
          duration : 4500

        route = if mode is 'join' then '/Join' else '/'
        kd.singletons.router.handleRoute route


  pistachio: ->

    """
    {{> @header }}
    <div class="TeamsModal TeamsModal--login">
      {{> @logo}}
      {{> @form}}
    </div>
    <footer>
      <a href="https://www.koding.com/Legal" target="_blank">Acceptable user policy</a><a href="https://www.koding.com/Legal/Copyright" target="_blank">Copyright/DMCA guidelines</a><a href="https://www.koding.com/Legal/Terms" target="_blank">Terms of service</a><a href="https://www.koding.com/Legal/Privacy" target="_blank">Privacy policy</a>
    </footer>
    """
