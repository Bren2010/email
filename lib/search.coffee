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
    prepare: -> super()
    save: (fn) -> super fn, module
    del: (fn) -> super fn, module


# Creates a new index object.
#
# @param string/null  id     The index's id.  (Null for a new entry.)
# @param object/null  entry  The index's data.  (Null for existing.)
#
# @return Index The index described.
exports.create = (id, entry) -> new Index id, entry

# Efficiently inserts several index entries.
#
# @param array     indexes             The indexes to insert.
# @param callback  fn(object, object)  See BaseModel::save()
exports.massInsert = (indexes, fn) ->
    entries = []
    
    for index in indexes
        [err, entry] = index.prepare()
        if err? then continue
        
        entries.push entry
    
    module.r.insert(entries).run module.c, (err, out) ->
        fn err, out
        return false

# Efficiently deletes all indexes under a list of domains.
#
# @param string    user                The user's id.
# @param array     dns                 Domains to delete.
# @param callback  fn(object, object)  See BaseModel::del()
exports.massDeleteByDn = (user, dns, fn) ->
    if dns.length is 0 then return fn null, null
    dns.push {index: 'domain'}
    
    query = module.r.getAll dns...
    query.filter({user: user}).delete().run module.c, (err, out) ->
        fn err, out
        return false
