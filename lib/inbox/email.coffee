{BaseModel} = require 'baseModel'
{check} = require 'validator'

moment = require 'moment'
ghm = require 'ghm'
async = require 'async'

user = require('user').model
cache = require 'cache'

# Prepares a database table for this model to use.
#
# @param class db The database connection to use.
exports.db = (db) ->
    module.d = db.r
    module.r = db.r.table 'emails'
    module.c = db.conn

# Describes the data and operations of a emails.
class Email extends BaseModel
    constructor: (@id, email) ->
        @user = email?.user ? null
        @date = email?.date ? moment().unix()
        @from = email?.from ? null
        @subject = email?.subject ? null
        @body = email?.body ? null
        @signature = email?.signature ? null
        @pubKey = email?.pubKey ? null
        @read = email?.read ? false
        @processed = email?.processed ? false
        
        @_immutable = []
    
    validate: ->
        check(@date, 'date').isInt()
        check(@from, 'from').notEmpty().len(10, 1024)
        check(@subject, 'subject').notEmpty().len(64, 1024)
        check(@body, 'body').notEmpty().len(64, 10240)
        check(@signature, 'signature').notEmpty().len(32, 256)
        check(@pubKey, 'pubKey').notEmpty().len(10, 1024)
    
    # @see BaseModel::humanize()
    humanize: ->
        super ['date']
        
        @__defineGetter__ 'date', () -> moment.unix(@_date).format 'LL'
        @__defineSetter__ 'date', (date) -> @_date = moment(date).unix()
    
    # @see BaseModel::{getUser(),...,del()}
    getUser: (done) -> super user, done
    dehumanize: -> super ['date']
    load: (fn) -> super 'email', fn, module
    prepare: -> super()
    save: (fn) -> super fn, module
    del: (fn) -> super fn, module


# Creates a new email object.
#
# @param String/null id The email's id. (Null for a new email.)
# @param Object/null email The email's data. (Null for existing.)
#
# @return Email The email described.
exports.create = (id, email) -> new Email id, email

# Get a page of emails
#
# @param String user User ID.
# @param Number p The page number to retrieve.
# @param callback fn([]Email, Number) Called when the data is loaded.
exports.getPage = (user, p, fn) ->
    [d, entries, t, n] = [module.d.desc('date'), [], 0, 10]
    
    finish = ->
        filter = user: user, processed: true
        module.r.filter(filter).count().run module.c, (err, t) ->
            fn entries, Math.ceil t/n
    
    x = (p - 1) * n
    query = module.r.filter({user: user, processed: true}).orderBy(d).skip(x)
    query.limit(n).run module.c, (err, cur) ->
        test = -> cur.hasNext()
        processEntry = (done) ->
            cur.next (err, entry) ->
                id = entry.id
                delete entry.id
                
                entry = exports.create id, entry
                entry.humanize()
                
                entries.push entry
                done()
        
        async.whilst test, processEntry, finish

# Get the new emails for a user.
#
# @param string    user         User Id.
# @param callback  fn([]Email, Number)  10 unread and unprocessed emails.
exports.getNew = (user, fn) ->
    [entries, n] = [[], 10]
    filter =
        user: user
        read: false
        processed: false
    
    finish = ->  module.r.filter(filter).count().run module.c, (err, t) ->
        fn entries, Math.ceil t/n
    
    query = module.r.filter(filter).orderBy(module.d.asc('date')).limit(n)
    query.run module.c, (err, cur) ->
        test = -> cur.hasNext()
        processEntry = (done) ->
            cur.next (err, entry) ->
                id = entry.id
                delete entry.id
                
                entry = exports.create id, entry
                entry.humanize()
                
                entries.push entry
                done()
        
        async.whilst test, processEntry, finish


# Get all the emails in an array.
#
# @param string user User ID.
# @param Array ids List of ids to load.
# @param callback fn([]Email) Called when data is loaded.
exports.getAll = (user, ids, fn) ->
    [entries, n] = [[], 10]
    finish = ->
        filter = user: user, processed: true
        module.r.filter(filter).count().run module.c, (err, t) ->
            console.log t
            fn entries, Math.ceil t/n
    
    ids.push {index: 'id'}
    module.r.getAll(ids...).filter(user: user).run module.c, (err, cur) ->
        test = -> cur.hasNext()
        processEntry = (done) ->
            cur.next (err, entry) ->
                id = entry.id
                delete entry.id
                
                entry = exports.create id, entry
                entry.humanize()
                
                entries.push entry
                done()
        
        async.whilst test, processEntry, finish

# Perform a mass update of emails.


# Efficiently updates several emails.
#
# @param array     emails              The indexes to insert.
# @param callback  fn(object, object)  See BaseModel::save()
exports.massUpdate = (emails, fn) ->
    entries = []
    
    for email in emails
        [err, entry] = email.prepare()
        if err? then continue
        
        entry.id = email.id
        entries.push entry
    
    module.r.insert(entries, {upsert: true}).run module.c, (err, out) ->
        fn err, out
        return false
