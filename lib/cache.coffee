db = require 'db'

module.exports.get = (type, id, fn) ->
    if db.cache?
        db.cache.get type + '_' + id, (err, reply) ->
            if reply? then fn 'hit', JSON.parse reply else fn()
    else fn()

module.exports.set = (type, id, entry, fn) ->
    if db.cache?
        db.cache.set type + '_' + id, JSON.stringify(entry), ->
            db.cache.expire type + '_' + id, 30, ->
                fn null, entry
    else fn null, entry

