async = require 'async'
config = require 'config'
{EventEmitter} = require 'events'
r = require 'rethinkdb'
redis = require 'redis'

exports.events = new EventEmitter()
exports.start = ->
    rdb = (done) ->
        r.connect config.database, (err, conn) ->
            if err? then console.log err
            
            exports.r = r
            exports.conn = conn
            
            done()
    
    cache = (done) ->
        conf = config.cache
        
        if not conf.caching then return done()
        exports.cache = redis.createClient conf.port, conf.host, conf.opts
        exports.cache.on 'ready', -> done()
    
    async.parallel [rdb, cache], -> exports.events.emit 'start'

exports.close = () ->
    exports.conn.close()
    if exports.cache? then exports.cache.end()

