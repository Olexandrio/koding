class NewKite extends KDEventEmitter

  { Scrubber, Store } = Bongo.dnodeProtocol

  [NOTREADY, READY, CLOSED] = [0,1,3]

  kontrolEndpoint = "http://127.0.0.1:4000/request" #kontrol addr

  constructor: (options)->

    super options

    { @addr, @kitename, @token, @correlationName, @kiteKey } = options
    @localStore   = new Store
    @remoteStore  = new Store
    @tokenStore = {}
    @autoReconnect = true
    @readyState = NOTREADY
    @addr or= ""
    @token or= ""
    @initBackoff options  if @autoReconnect
    @connect()

  connect:->
    if @addr
    then @connectDirectly()
    else @getKiteAddr(true)

  bound: Bongo.bound

  connectDirectly:->
    log "trying to connect to #{@addr}"
    @ws = new WebSocket "ws://#{@addr}/sock"
    @ws.onopen    = @bound 'onOpen'
    @ws.onclose   = @bound 'onClose'
    @ws.onmessage = @bound 'onMessage'
    @ws.onerror   = @bound 'onError'

  getKiteAddr : (connect=no)->
    NewKite.getKites @kitename, (err, data) =>
      if err
        log "kontrol request error", err
        # Make a request again if we could not get the addres, use backoff for that
        KD.utils.defer => @setBackoffTimeout =>
          @getKiteAddr true
      else
        log {data}
        @token = data[0].token
        @addr = data[0].publicIP

        # this should be optional
        @connectDirectly() if connect

  @getKites: (kitename, callback)->
    requestData =
      username   : "#{KD.nick()}"
      remoteKite : kitename
      sessionID  : KD.remote.getSessionToken()

    xhr = new XMLHttpRequest
    xhr.open "POST", kontrolEndpoint, yes
    xhr.setRequestHeader('Content-type', 'application/x-www-form-urlencoded')
    xhr.send JSON.stringify requestData
    xhr.onload = =>
      if xhr.status is 200
        data = JSON.parse xhr.responseText
        callback null, data
      else
        callback xhr.responseText, null

  disconnect:(reconnect=true)->
    @autoReconnect = !!reconnect  if reconnect?
    @ws.close()

  onOpen:->
    log "I'm connected to #{@kitename} at #{@addr}. Yayyy!"
    @clearBackoffTimeout()
    @readyState = READY
    @emit 'KiteConnected', @kitename
    @emit 'ready'

  onClose: (evt) ->
    # log "#{@kitename}: disconnected, trying to reconnect"
    @readyState = CLOSED
    @emit 'KiteDisconnected', @kitename
    # enable below to autoReconnect when the socket has been closed
    # if @autoReconnect
    #   KD.utils.defer => @setBackoffTimeout @bound "connect"

  onMessage: (evt) ->
    try
      args = JSON.parse evt.data
    catch e
      log "json parse error: ", e, evt.data

    if args and not e
      err = args.arguments[0]
      {method} = args
      callback = switch method
        when 'ping'             then @bound 'handlePing'
        else (@localStore.get method) ? ->

    if err?.message?
      KD.utils.defer => @setBackoffTimeout @bound "getKiteAddr"
    else
      callback.apply this, @unscrub args


  onError: (evt) ->
    # log "#{@kitename}: error #{evt.data}"

  handlePing: ->
    @send JSON.stringify
      method      : 'pong'
      arguments   : []
      callbacks   : {}

  initBackoff:(options)->
    backoff = options.backoff ? {}
    totalReconnectAttempts = 0
    initalDelayMs = backoff.initialDelayMs ? 700
    multiplyFactor = backoff.multiplyFactor ? 1.4
    maxDelayMs = backoff.maxDelayMs ? 1000 * 15 # 15 seconds
    maxReconnectAttempts = backoff.maxReconnectAttempts ? 50

    @clearBackoffTimeout =->
      totalReconnectAttempts = 0

    @setBackoffTimeout = (fn)=>
      if totalReconnectAttempts < maxReconnectAttempts
        timeout = Math.min initalDelayMs * Math.pow(
          multiplyFactor, totalReconnectAttempts
        ), maxDelayMs
        setTimeout fn, timeout
        totalReconnectAttempts++
      else
        @emit "connectionFailed"

  ready: (callback)->
    return KD.utils.defer callback  if @readyState
    @once 'ready', callback

  unscrub: (args) ->
    scrubber = new Scrubber @localStore
    return scrubber.unscrub args, (callbackId) =>
      unless @remoteStore.has callbackId
        @remoteStore.add callbackId, (rest...) =>
          @handleRequest callbackId, rest
      @remoteStore.get callbackId

  handleRequest: (method, args) ->
    @scrub method, args, (scrubbed) =>
      messageString = JSON.stringify(scrubbed)
      @ready => @send scrubbed

  scrub: (method, args, callback) ->
    scrubber = new Scrubber @localStore
    scrubber.scrub args, =>
      scrubbed = scrubber.toDnodeProtocol()
      scrubbed.method or= method
      callback scrubbed

  tell:(options, callback) ->
    @ready =>
      # token is needed to initiate a valid session
      # TODO: invalidate token when something goes wrong, or if we got a new token from kontrol
      options.token = @token
      options.username  = "#{KD.nick()}"
      @handleRequest options.method, [options, callback]

  send: (data) ->
    try
      if @readyState is READY
        @ws.send JSON.stringify data
      else
        # log "slow down ... I'm still trying to reconnect!"
    catch e
      @disconnect()

