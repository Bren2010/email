express = require 'express'
http = require 'http'
path = require 'path'
hbs = require 'hbs'
i18n = require 'i18n'
io = require 'socket.io'
config = require 'config'
crypto = require 'crypto'

db = require 'db'

# Sections
pages = {}
pages.home       = require 'home'
pages.user       = require 'user'
pages.inbox      = require 'inbox'

app = express()

app.configure () ->
    app.set 'view engine', 'html'
    
    app.engine 'html', require('hbs').__express
    
    app.use express.favicon()
    app.use express.logger 'dev'
    app.use express.urlencoded()
    app.use express.json()
    app.use express.methodOverride()
    app.use express.cookieParser config.sessionSecret
    app.use express.cookieSession()
    app.use express.csrf()
    app.use i18n.init
    app.use app.router
    app.use require('less-middleware')({ src: __dirname + '/public' })
    app.use express.static path.join __dirname, 'public'
    
    app.use pages[name] for name of pages
    
    hbs.registerHelper 'paginate', require 'handlebars-paginate'
    hbs.registerHelper 'inArray', (array, val, options) ->
        if array? and array.indexOf(val) isnt -1 then options.fn this
    
    hbs.registerHelper '__', (args...) ->
        this.locale ?= args[args.length - 1].locale
        # this.locale ?= options.hash.locale
        i18n.__.apply this, arguments
    
    hbs.registerHelper '__n', -> i18n.__n.apply this, arguments

app.configure 'development', () -> app.use express.errorHandler()

i18n.configure {
    locales: ['en']
    defaultLocale: 'en'
    cookie: 'locale'
    directory: './locales'
    updateFiles: false
}

{getUser} = require 'global'
app.all '*', getUser

db.events.once 'start', ->
    server = app.listen config.port, ->
        console.log 'Server listening on port ' + config.port
    
    websocket = io.listen server
    websocket.sockets.on 'connection', pages.inbox.handler
    
    true

db.start()
