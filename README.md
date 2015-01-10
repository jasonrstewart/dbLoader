# dbLoader
Server/client process for serving frequently used dictionaries using the clients cached response whenever possible.


Server

  dbLoaderManager works with the client side libs/dbLoader.cofffee
  
  dbLoaderManager will build, at app startup/nightly cron/change to data, various
    dictionaries to be used by client views. For example, with the employee dict a
    view can easily display a readable employee name with just the employeeId and no
    further ajax data calls are required.
    
  dbLoaderManager is responsible for keeping the dict up to date, but each manager providing
    dbLoader with data is responsible for pinging the dbLoader with a notification that
    their data has changed.
    
  dbLoaderManager, after building the dictionary, will create an md5Hash from the dictionary.
    Any change to the dictionary will trigger a new hash. The hash is passed to each client
    view and used as a parameter to request the matching dictionary. This request is set to 
    never expire, so the client will request data once, and use the cached response until a 
    new hash (indicating data has changed) is passed to the view. 
    
  Should the client be passed a hash that has expires prior to requesting the dictionary, the 
    libs/dbLoader.coffee will request the view be reloaded which will receive the new hash and
    insure the view is operating with an up to date dictionary. 


Client

  dbLoader works with the dbLoaderManager. The client will have hash baked in, that is passed to the
    manager when requesting the locations data book. This request will never expire to the client
    requests the data book only once until the underlying data is changed on the server. 
    
  dbLoader will ask the view to reload if the server determines the hash has expired, meaning the 
    underlying data was changed after the view was served. 
    
  dbLoader will make callbacks to the controller that requested the data book. dbLoader is typically 
    requested by the views primary controller. For example, the memberships view dbLoader callback is 
    typically found in the MembershipsController found in memberships.coffee.
