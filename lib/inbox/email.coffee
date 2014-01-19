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
    
    finish = -> module.r.filter(user: user).count().run module.c, (err, t) ->
        fn entries, Math.ceil t/n
    
    x = (p - 1) * n
    query = module.r.filter(user: user).orderBy(d).skip(x)
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

# Get all the emails in an array.
#
# @param string user User ID.
# @param Array ids List of ids to load.
# @param callback fn([]Email) Called when data is loaded.
exports.getAll = (user, ids, fn) ->
    entries = []
    finish = -> fn entries
    
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
