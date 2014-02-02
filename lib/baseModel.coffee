async = require 'async'
cache = require 'cache'

# Base Model
class exports.BaseModel
    
    # Gets the user object.
    #
    # @param object    user             Model to use.
    # @param callback  done(err, User)  Called with the user object.
    getUser: (user, done) ->
        u = user.create @user, null
        u.load (ok) ->
            if ok
                done null, u.username 
            else 
                done null, 'Anonymous'
    
    # Makes the content this model represents human-readable.
    #
    # Currently, this function only stows data to a safe place so 
    # getters and setters can use the main key.
    #
    # @param array  keys  The keys that need to be stowed.
    humanize: (keys) ->
        swap = (key) => this['_' + key] = this[key]
        swap key for key in keys
    
    # Inverse of humanize().
    #
    # This is completely functional, unlike BaseModel::humanize().
    #
    # @param array  keys  The keys that need to be unstowed.
    dehumanize: (keys) ->
        swap = (key) =>
            if not this['_' + key]? then return
            
            delete this[key]
            this[key] = this['_' + key]
            delete this['_' + key]
        
        swap key for key in keys
    
    # Loads the described entry in state.
    #
    # @param String    type      The type of content being loaded.
    # @param callback  fn(bool)  Called when the content is loaded with 
    #                            a boolean success state.
    # @param object    context   The context to use.  (Should contain 
    #                            DB methods).
    load: (type, fn, context) ->
        first = (done) -> done null, type, @id
        fetch = (done) ->
            [type, id] = [type, @id]
            context.r.get(@id).run context.c, (err, entry) ->
                done null, type, id, entry
        
        fns = [first.bind(this), cache.get, fetch.bind(this), cache.set]
        async.waterfall fns, (err, entry) =>
            if entry?
                put = (k) => if k[0] isnt '_' then this[k] = entry[k]
                put key for key in Object.keys this
                @_new = false
                
                fn true
            else
                @_new = true
                fn false
    
    # Prepares the model for a save.
    #
    # @return  string  An error string.
    # @return  object  The raw data to push to the database.
    prepare: ->
        # Data should be raw.
        @dehumanize()
        
        # Error check content.
        try @validate()
        catch e then return [e.message, null]
        
        # Generate entry.
        entry = {}
        put = (k) => if k[0] isnt '_' and k isnt 'id' then entry[k] = this[k]
        put key for key in Object.keys this
        
        [null, entry]
    
    # Saves the model's state to the database.
    #
    # @param callback  fn(object, object)  Called when content is saved 
    #                                      (with the database's output).
    # @param object    context             The context to use.  (Should 
    #                                      contain DB methods).
    save: (fn, context) ->
        [err, entry] = @prepare()
        if err?
            errors = {}
            errors[err] = true
            return fn null, errors
        
        # Add to database.
        query = context.r
        if (@_new? and not @_new) or (not @_new? and @id?)
            if @_immutable? then delete entry[k] for k in @_immutable
            query = query.get(@id).update entry
        else
            if @id? then entry.id = @id
            query = query.insert entry, upsert: true
        
        query.run context.c, (err, out) =>
            if out.generated_keys?.length is 1 then @id = out.generated_keys[0]
            fn err, out
        
        entry
    
    # Deletes this content from the database.
    #
    # @param callback  fn(object)  Called when the content is saved with
    #                              the database's output.
    # @param object    context     The context to use.  (Should contain 
    #                              DB methods).
    del: (fn, context) ->
        context.r.get(@id).delete().run context.c, (err, out) ->
            fn err, out
            return false
