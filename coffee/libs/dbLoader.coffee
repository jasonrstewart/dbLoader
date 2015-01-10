###
  dbLoader works with the dbLoaderManager. The client will have hash baked in, that is passed to the
    manager when requesting the locations data book. This request will never expire to the client
    requests the data book only once until the underlying data is changed on the server. 
    
  dbLoader will ask the view to reload if the server determines the hash has expired, meaning the 
    underlying data was changed after the view was served. 
    
  dbLoader will make callbacks to the controller that requested the data book. dbLoader is typically 
    requested by the views primary controller. For example, the memberships view dbLoader callback is 
    typically found in the MembershipsController found in memberships.coffee.

###

window.InitializeDBLoader = (App) ->
  window.ERROR_MISSING_PARAMS = 0 
  window.ERROR_LOCATION_MISSING = 1 
  window.ERROR_HASH_EXPIRED = 2
  
  App.DBLoaderController = Em.ArrayController.extend {
    bookDicts: {
      'employees': true
      'locations': true
      'services': true
      'products': true
      'membershipTypes': true
      'membershipRegions': true
      'coupons': true
      'groupons': true
      'grouponRegions': true
      'frontDesks': true
      'locationMgrs': true
      'estheticians': true
      'therapists': true
      'groupMgrs': true
    }
    userIdDicts: ['employees', 'rosters', 'schedules', 'therapists', 'estheticians', 'frontDesks', 'locationMgrs']
    barcodeDicts: ['coupons', 'groupons', 'products']
    locationDicts: ['employees', 'rosters', 'schedules', 'therapists', 'estheticians', 'frontDesks', 'locationMgrs', 'locationRooms']
    weekTimeDicts: ['rosters']
    serveAllDicts: ['services', 'products']
    modelsToLoad: null
    isReadyCallbacks: []
    weekTime: null
    
    init: () ->
      @_super()
      @set 'modelsToLoad', []
      @set 'weekTime', getWeekTime()
      
    isReady: () ->
      for m in @modelsToLoad when m.loaded == false
        return false 
      return true if not db.md5Hash?
      return @bookDidLoad
      
    registerIsReadyCallback: (callback) ->
      @isReadyCallbacks.addObject callback 
      
    checkCallbacks: () ->
      if @isReady()
        cb() for cb in @isReadyCallbacks    
      
    setModels: (modelNames) ->
      modelsToLoad = []
      for m in modelNames
        if not @bookDicts[m]? or not db.md5Hash?
          modelsToLoad.push {'name': m, 'loaded': false}
      @set 'modelsToLoad', modelsToLoad
      
    loadModels: () ->
      @checkCallbacks() if not @modelsToLoad? or @modelsToLoad.length == 0
      return @loadBook() if db.md5Hash?
      return @loadNonBookModels() if @modelsToLoad.length > 0
      
    loadBook: () ->
      $.getJSON( "/api/1/dbLoader/#{db.locationId ? 'corporate'}/#{db.md5Hash}" )
        .done (data) =>
          if data.result
            @setBookDicts data.book
          else
            showErrors data.errors
            if data.code == ERROR_HASH_EXPIRED
              setTimeout (-> 
                message = "Some of the system data is out ouf date for this page. The page will be reloaded in a few seconds."
                dialog = launchModalDialog {'message': message}
                setTimeout (-> window.location.reload true),3000
              ), 3000
            
        .fail ->
          showErrors "Having trouble fetching the location system data"

    setBookDicts: (book) ->
      for name, data of book
        @setDB {name:name}, data
      
      @bookDidLoad = true
      @checkCallbacks()
      
      @loadNonBookModels()
      
    loadNonBookModels: () ->
      for m in @modelsToLoad
        if m.name == "location"
          @loadLocation m
        else if m.name == "customer"
          @loadCustomer m, false
        else
          @loadModel m
          
      
             
    loadModel: (model) ->
      url = "/api/1/#{model.name}"
      url += "/all" if model.name in @serveAllDicts
      url += "?"
      url += "locationId=#{window.db.locationId}&" if model.name in @locationDicts
      url += "weekTime=#{@weekTime}&" if model.name in @weekTimeDicts
      
      $.getJSON( url )
        .done (data) =>
          if data.result
            @setDB model, data["#{model.name}"]
          else
            showErrors data.errors
        .fail ->
          showErrors "Having trouble fetching the #{model.name} data"

      
    # Special handling for customer (not customers)
    # Place this into it's own dictionary, which represents the customer with focus      
    loadCustomer: (model, light) ->
      if window.db.customerId?
        url = "/api/1/customers/#{window.db.customerId}"
      else if window.db.userId?
        url = "/api/1/customers/userId/#{window.db.userId}"
      else
        url = "/api/1/customers/userid/#{window.db.user.operator._id}"
      url += "?light=1" if light
      $.getJSON(url)
        .done (data) =>
          if data.result
            loaded = false
            
            if data.customers?
              if data.customers.length == 1
                window.db["customer"] = data.customers[0]
                loaded = true
            else
              window.db["customer"] = data.customer
              loaded = true
              
            if loaded
              Ember.set model, 'loaded', true
              return @checkCallbacks()
            else
              showErrors "Having trouble fetching the customer data"
          else
            showErrors data.errors
        .fail ->
          showErrors "Having trouble fetching the customer data"
          
    # Special handling for location (not locations)
    # Place this into it's own dictionary, which represents the location with focus 
    # the data should already exist in the locations dict     
    loadLocation: (model) ->
      if db.md5Hash?
        location = db.locations[db.locationId]
        if not location?
          return showErrors "locationId: #{db.locationId} not found in locations list"
        db.location = location
        @set 'locationName', db?.location?.name ? ''
        Ember.set model, 'loaded', true
        @checkCallbacks()
      
      # Ok to serve views without an md5Hash, in which case the view must be responsible for
      # building its own dictionaries and will be handled below.
      else
        $.getJSON( "/api/1/locations?locationId=#{window.db.locationId}" )
          .done (data) =>
            if data.result
              if data["locations"].length == 1
                window.db["location"] = data["locations"][0]
                @set 'locationName', db?.location?.name ? ''
                Ember.set model, 'loaded', true
                return @checkCallbacks()
              else
                showErrors "Having trouble fetching the location data"
            else
              showErrors data.errors
               
          .fail ->
            showErrors "Having trouble fetching the #{model.name} data"  
          
    setDB: (model, data)  ->
      _dict = {}
      if model.name in @userIdDicts
        keyRef = 'userId'
      else if model.name in @barcodeDicts
        keyRef = 'barcode'
      else
        keyRef = '_id'
      
      
      for d in data
        key = d[keyRef]
        _dict[key] = d
      
      window.db[model.name] = _dict
      
      Ember.set model, 'loaded', true
      @checkCallbacks()
  }
  
