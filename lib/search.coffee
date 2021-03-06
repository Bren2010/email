{BaseModel} = require 'baseModel'
{check} = require 'validator'

async = require 'async'
inbox = require './inbox'

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

# Queries the indexes.
#
#
#
exports.query = (user, queries, p, fn) ->
    [n, entries] = [10, {}]
    finish = ->
        cleanEntries = []
        cleanEntries.push entry for id, entry of entries
        
        query = module.r.getAll(ids...).filter({user: user}).count()
        query.run module.c, (err, t) ->
            fn cleanEntries, Math.ceil t/n
    
    # Better database <=> Better queries
    # RethinkDB is pretty hard and expensive to query like this.
    # BigTable (or another multi-dimensional K/V store) would be cool to use.
    ids = []
    for query in queries
        for dn, keys of query
            for key in keys
                ids.push key
    
    ids.push {index: 'key'}
    
    x = (p - 1) * n
    query = module.r.getAll(ids...).filter({user: user}).skip(x).limit(n)
    query.run module.c, (err, cur) ->
        test = -> cur.hasNext()
        processEntry = (done) ->
            cur.next (err, entry) ->
                if not entry? then return done()
                if entries[entry.doc]? then return done()
                entry = inbox.model.create entry.doc, null
                entry.load (ok) ->
                    entry.humanize()
                    entries[entry.id] = entry
                    
                    done()
        
        async.whilst test, processEntry, finish


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

# Efficiently deletes all indexes under a list of domains.
#
# @param string    user                The user's id.
# @param array     email               Email id to select on.
# @param callback  fn(object, object)  See BaseModel::del()
exports.massDeleteByEmail = (user, email, fn) ->
    query = module.r.filter({user: user, doc: email})
    query.delete().run module.c, (err, out) ->
        fn err, out
        return false
