_             = require("lodash")
EE            = require("events")
Promise       = require("bluebird")
menu          = require("../gui/menu")
Windows       = require("../gui/windows")
savedState    = require("../saved_state")

module.exports = {
  _defaultOptions: (state, options) ->
    _this = @

    _.defaults({}, options, {
      x: state.browserX
      y: state.browserY
      width: state.browserWidth or 1280
      height: state.browserHeight or 720
      devTools: state.isBrowserDevToolsOpen
      minWidth: 100
      minHeight: 100
      contextMenu: true
      trackState: {
        width: "browserWidth"
        height: "browserHeight"
        x: "browserX"
        y: "browserY"
        devTools: "isBrowserDevToolsOpen"
      }
      onFocus: ->
        menu.set({withDevTools: true})
      onNewWindow: (e, url) ->
        _win = @

        _this._launchChild(e, url, _win, state, options)
        .then (child) ->
          ## close child on parent close
          _win.on "close", ->
            if not child.isDestroyed()
              child.close()
    })

  _render: (url, state, options = {}) ->
    options = @_defaultOptions(state, options)

    win = Windows.create(options)

    @_launch(win, url, options)

  _launchChild: (e, url, parent, state, options) ->
    e.preventDefault()

    [parentX, parentY] = parent.getPosition()

    options = @_defaultOptions(state, options)

    _.extend(options, {
      x: parentX + 100
      y: parentY + 100
      trackState: false
      onPaint: null ## dont capture paint events
    })

    win = Windows.create(options)

    ## needed by electron since we prevented default and are creating
    ## our own BrowserWindow (https://electron.atom.io/docs/api/web-contents/#event-new-window)
    e.newGuest = win

    @_launch(win, url, options)

  _launch: (win, url, options) ->
    menu.set({withDevTools: true})

    Promise
    .try =>
      if ps = options.proxyServer
        @_setProxy(win.webContents, ps)
    .then ->
      win.loadURL(url)
    .return(win)

  _setProxy: (webContents, proxyServer) ->
    new Promise (resolve) ->
      webContents.session.setProxy({
        proxyRules: proxyServer
      }, resolve)

  open: (browserName, url, options = {}, automation) ->
    savedState.get()
    .then (state) =>
      @_render(url, state, options)
      .then (win) =>
        a = Windows.automation(win)

        invoke = (method, data) =>
          a[method](data)

        automation.use({
          onRequest: (message, data) ->
            switch message
              when "get:cookies"
                invoke("getCookies", data)
              when "get:cookie"
                invoke("getCookie", data)
              when "set:cookie"
                invoke("setCookie", data)
              when "clear:cookies"
                invoke("clearCookies", data)
              when "clear:cookie"
                invoke("clearCookie", data)
              when "is:automation:client:connected"
                invoke("isAutomationConnected", data)
              when "take:screenshot"
                invoke("takeScreenshot")
              else
                throw new Error("No automation handler registered for: '#{message}'")
        })

        call = (method) ->
          return ->
            if not win.isDestroyed()
              win[method]()

        events = new EE

        win.once "closed", ->
          call("removeAllListeners")
          events.emit("exit")

        return _.extend events, {
          browserWindow:      win
          kill:               call("close")
          removeAllListeners: call("removeAllListeners")
        }
}
