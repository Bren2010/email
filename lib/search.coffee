{BaseModel} = require 'baseModel'
{check} = require 'validator'

async = require 'async'

# Prepares a database table for this model to use.
#
# @param class  db  The database connection to use.
exports.db = (db) -> 
    module.d = db.r
    module.r = db.r.table 'index'
    module.c = db.conn

# Describes the data and operations of an index.
class Index extends BaseModel
    constructor: (@id, entry) ->
        @user = entry?.user ? null
        @domain = entry?.domain ? null
        @key = entry?.key ? null
        @doc = entry?.doc ? null
    
    validate: ->
        check(@user, 'user').notEmpty()
        check(@domain, 'domain').notEmpty()
        check(@key, 'key').notEmpty()
        check(@doc, 'doc').notEmpty()
    
    # @see BaseModel::{humanize(),...,del()}
    humanize: -> super []
    dehumanize: -> super []
    load: (fn) -> super 'index', fn, module
    save: (fn) -> super fn, module
    del: (fn) -> super fn, module


# Creates a new index object.
#
# @param string/null  id     The index's id.  (Null for a new entry.)
# @param object/null  entry  The index's data.  (Null for existing.)
#
# @return Index The index described.
exports.create = (id, entry) -> new Index id, entry

# Gets an array of indexes by their user and domain.
#
# @param string    user         The user's id.
# @param string    domain       The domain.
# @param callback  fn([]Index)  Called when the indexes are loaded.
#
# @return User The user described.
exports.getByDomain = (user, domain, fn) ->
    module.r.filter(user: user, domain: domain).run module.c, (err, cur) ->
        out = []
        test = -> cur.hasNext()
        processEntry = (done) ->
            cur.next (err, entry) ->
                id = entry.id
                delete entry.id
                
                entry = exports.create id, entry
                entry.humanize()
                out.push entry
                done()
        
        async.whilst test, processEntry, -> fn out
