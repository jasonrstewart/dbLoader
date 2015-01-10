###
  dbLoaderManager works with the client side libs/dbLoader.cofffee
  
  dbLoaderManager will build, at app startup/nightly cron/change to data, various
    dictionaries to be used by client views. For example, with the employee dict a
    view can easily display a readable employee name with just the employeeId and no
    further ajax data calls are required.
    
  dbLoader is responsible for keeping the dict up to date, but each manager providing
    dbLoader with data is responsible for pinging the dbLoader with a notification that
    their data has changed.
    
  dbLoader, after building the dictionary, will create an md5Hash from the dictionary.
    Any change to the dictionary will trigger a new hash. The hash is passed to each client
    view and used as a parameter to request the matching dictionary. This request is set to 
    never expire, so the client will request data once, and use the cached response until a 
    new hash (indicating data has changed) is passed to the view. 
    
  Should the client be passed a hash that has expires prior to requesting the dictionary, the 
    libs/dbLoader.coffee will request the view be reloaded which will receive the new hash and
    insure the view is operating with an up to date dictionary. 
###


ObjectId                      = require('mongodb').ObjectID
crypto                        = require('crypto')
log                           = new (require '../modules/bbalogger')
timeAndDate                   = require '../modules/timeAndDateFunctions' 
mongoManager                  = require '../managers/mongoManager'
cronManager                   = require '../managers/cronManager'

# Managers providing data that is the same for every location
locationManager               = require '../managers/locationManager'
productManager                = require '../managers/productManager'
serviceManager                = require '../managers/serviceManager'
membershipTypeManager         = require '../managers/membershipTypeManager'
membershipRegionManager       = require '../managers/membershipRegionManager'
couponManager                 = require '../managers/couponManager'
grouponManager                = require '../managers/grouponManager'
grouponRegionManager          = require '../managers/grouponRegionManager'

# Managers providing data that is different for each location
employeeManager               = require '../managers/employeeManager'
groupMgrManager               = require '../managers/roles/groupMgrManager'
frontDeskManager              = require '../managers/roles/frontDeskManager'
locationMgrManager            = require '../managers/roles/locationMgrManager'
estheticianManager            = require '../managers/roles/estheticianManager'
therapistManager              = require '../managers/roles/therapistManager'


class DBLoaderManager
  constructor: ()->
    @neutralCache = {}
    @cacheByLocation = {}
    @md5HashToLocationId = {}
    @locationIdToMd5Hash = {}
    @corporateMd5Hash = null
    
    # Neutral models will be the same for all locations
    @neutralModels = [
      {name: 'employees', manager: employeeManager}
      {name: 'locations', manager: locationManager}
      {name: 'products', manager: productManager}
      {name: 'services', manager: serviceManager}
      {name: 'membershipTypes', manager: membershipTypeManager}
      {name: 'membershipRegions', manager: membershipRegionManager}
      {name: 'coupons', manager: couponManager}
      {name: 'groupons', manager: grouponManager}
      {name: 'grouponRegions', manager: grouponRegionManager}
    ]
    
    # Location models will be different for each location
    @locationModels = [
      {name: 'groupMgrs', manager: groupMgrManager}
      {name: 'frontDesks', manager: frontDeskManager}
      {name: 'locationMgrs', manager: locationMgrManager}
      {name: 'estheticians', manager: estheticianManager}
      {name: 'therapists', manager: therapistManager}
    ]
    
    @setCallbacks()
    
  setCallbacks: () ->
    callback = (locationId) =>
      return if not @okToRebuildCache
      return @buildNeutralCache() if not locationId?
      @rebuildCacheByLocationId locationId, (err, result) ->
    
    employeeManager.registerNotificationOfNewEmployeesCallback () -> callback()
    locationManager.registerNotificationOfNewLocationsCallback () -> callback()
    productManager.registerNotificationOfNewProductsCallback () -> callback()
    serviceManager.registerNotificationOfNewServicesCallback () -> callback()
    membershipTypeManager.registerNotificationOfNewMembershipTypesCallback () -> callback()
    membershipRegionManager.registerNotificationOfNewMembershipRegionsCallback () -> callback()
    membershipRegionManager.registerNotificationOfNewMembershipRegionsCallback () -> callback()
    couponManager.registerNotificationOfCollectionDidChange () -> callback()
    grouponManager.registerNotificationOfCollectionDidChange () -> callback()
    grouponRegionManager.registerNotificationOfCollectionDidChange () -> callback()
    
    for mgr in @locationModels
      mgr.registerNotificationOfLocationBookDidChange callback
    
  databaseIsReady: () ->
    @buildNeutralCache()
    @setupCron()
     
  setupCron: () ->
    handler = (job) => @cronTask job
    cronManager.registerJobHandler 'rebuildDBBooks', handler, () =>
      time = (new Date()).getTime()
      @scheduleJob null, null, time
    
  scheduleJob: (lastRunTime, nextRunMidnight, runNow) ->
    if runNow?
      runTime = runNow
    else
      nextRunMidnight = timeAndDate.getTomorrowMidnight lastRunTime
      #after midnight but before opening time in all US timezones
      runTime = nextRunMidnight + 8.04*3600*1000 
    params = { name: 'Rebuild DBLoader Books', runTime: runTime }
    cronManager.scheduleJob 'rebuildDBBooks', runTime, params, (err, id) -> return
      
  cronTask: (job) ->
    @buildNeutralCache (err, result) =>
      cronManager.jobCompleted job
      @scheduleJob job.params.runTime, null
      
  buildNeutralCache: (callback) ->
    @neutralCache = {}
    modelIdx = -1
    
    done = () =>
      @buildAllLocationBooks callback
    
    updateCorporateMD5Hash = () =>
      dataAsString = JSON.stringify @neutralCache
      md5Hash = crypto.createHash('md5').update( dataAsString ).digest('hex')
      @corporateMd5Hash = md5Hash
      done()
      
    nextManager = () =>
      modelIdx++
      return updateCorporateMD5Hash() if modelIdx > (@neutralModels.length-1)
      mdl = @neutralModels[modelIdx]
      mdl.manager.getDataForDBBook (err, data) =>
        return done err if err?
        @neutralCache[mdl.name] = data
        nextManager()
    
    nextManager()
       
  buildAllLocationBooks: (callback) ->
    locations = null
    locationIdx = -1
    
    done = (err) =>
      if err?
        log.criticalError err
        return callback err, false if callback?
      @okToRebuildCache = true
      callback null, true if callback?
      
    nextLocation = () =>
      locationIdx++
      return done() if locationIdx > locations.length-1
      
      location = locations[locationIdx]
      return done "No location found in buildAllLocationBooks" if not location?._id?
        
      @rebuildCacheByLocationId location._id, (err, success) ->
        return done err if err?
        return done "CRITICAL ERROR: Failed to build location book for #{location._id}" if not success
        nextLocation()
      
    locationManager.getCachedLocations (err, locationsById) ->
      return done "CRITICAL ERROR: unable to getCachedLocations" if err?
      return done "No cached locations returned in buildAllLocationBooks" if not locationsById?
      locations = (v for k,v of locationsById)
      nextLocation()
         
  rebuildCacheByLocationId: (locationId, callback) ->
    md5Hash = @locationIdToMd5Hash[locationId]
    delete @md5HashToLocationId[md5Hash]
    delete @locationIdToMd5Hash[locationId]
    
    @cacheByLocation[locationId] = {}
    locationCache = {}
    data = {}
    modelIdx = -1
    
    getMD5Hash = () =>
      dataAsString = JSON.stringify data
      md5Hash = crypto.createHash('md5').update( dataAsString ).digest('hex')
      @md5HashToLocationId[md5Hash] = locationId
      @locationIdToMd5Hash[locationId] = md5Hash
      @cacheByLocation[locationId][md5Hash] = locationCache
      return callback null, true 
      
    addNeutralData = () =>
      data[k] = v for k,v of locationCache 
      data[k] = v for k,v of @neutralCache
      getMD5Hash()
      
    nextManager = () =>
      modelIdx++
      return addNeutralData() if modelIdx > (@locationModels.length-1)
      m = @locationModels[modelIdx]
      m.manager.getDataForDBBookByLocationId locationId, (err, d) ->
        locationCache[m.name] = d
        nextManager()
    
    nextManager()
      
  serveWithoutHash: (req, res) ->
    @getCurrentMD5HashForLocationId req.params.locationId, (err, hash) =>
      return res.json {'result': false, 'errors': err} if err?
      req.params.md5Hash = hash
      @serve req, res
    
  serve: (req, res) ->
    ERROR_MISSING_PARAMS = 0 
    ERROR_LOCATION_MISSING = 1 
    ERROR_HASH_EXPIRED = 2
    
    locationId = req.params.locationId
    md5Hash = req.params.md5Hash
    
    callback = (err, code) =>
      return res.json {'result': false, 'errors': err, 'code': code} if err?
      data = {}
      if locationId != 'corporate'
        data[k] = v for k,v of @cacheByLocation[locationId][md5Hash]
      data[k] = v for k,v of @neutralCache
      res.setHeader("Expires", 9000000000000)
      res.json {'result': true, 'book': data}
    
    return callback 'A location Id is required', ERROR_MISSING_PARAMS if not locationId?
    return callback 'An md5Hash is required', ERROR_MISSING_PARAMS if not md5Hash?
    
    if locationId == 'corporate'
      if md5Hash == @corporateMd5Hash
        return callback null if @neutralCache?
      else
        return callback "The md5Hash key is out of date for corprate. No data book has been returned. 
            Try reloading the page in a few seconds.", ERROR_HASH_EXPIRED
    
    if not @cacheByLocation[locationId]?
      return callback "The locationId: #{locationId} was not found and no data book has been returned.", ERROR_LOCATION_MISSING
    if not @cacheByLocation[locationId][md5Hash]?
      return callback "The locationId: #{locationId} was found, but the md5Hash key is out of date. No data book has been returned. 
            Try reloading the page in a few seconds.", ERROR_HASH_EXPIRED
    
    return callback null if @cacheByLocation[locationId]?[md5Hash]?
    
  getCurrentMD5HashForLocationId: (locationId, callback) ->
    return callback null, @locationIdToMd5Hash[locationId] if @locationIdToMd5Hash[locationId]?
    @rebuildCacheByLocationId locationId, (err, result) =>
      return callback err if err?
      return callback null, @locationIdToMd5Hash[locationId]
    
  getCurrentMD5HashForCorporate: (callback) ->
    callback null, @corporateMd5Hash
    
    

module.exports = new DBLoaderManager
      
    
    
