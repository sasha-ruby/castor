#===========================================================================================#
# Copyright 2023 Province of British Columbia
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.
#===========================================================================================#

defineModule(sim, list(
  name = "uploadCastor",
  description = NA, #"insert module description here",
  keywords = NA, # c("insert key words here"),
  authors =  c(person("Kyle", "Lochhead", email = "kyle.lochhead@gov.bc.ca", role = c("aut", "cre")),
               person("Tyler", "Muhly", email = "tyler.muhly@gov.bc.ca", role = c("aut", "cre"))),
  childModules = character(0),
  version = list(SpaDES.core = "0.2.5", uploadCastor = "0.0.1"),
  spatialExtent = raster::extent(rep(NA_real_, 4)),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list("citation.bib"),
  documentation = list("README.txt", "uploadCastor.Rmd"),
  reqdPkgs = list("sf", "rpostgis","DBI", "RSQLite", "data.table"),
  parameters = rbind(
    defineParameter(".plotInitialTime", "numeric", NA, NA, NA, "This describes the simulation time at which the first plot event should occur"),
    defineParameter(".plotInterval", "numeric", NA, NA, NA, "This describes the simulation time interval between plot events"),
    defineParameter(".saveInitialTime", "numeric", NA, NA, NA, "This describes the simulation time at which the first save event should occur"),
    defineParameter(".saveInterval", "numeric", NA, NA, NA, "This describes the simulation time interval between save events"),
    defineParameter("aoiName", "character", "test", NA, NA, "The name of the ares of interest i.e., chilcotin"),
    defineParameter("dbInfo", "list", list("dbhost","dbname", "dbpassword", "dbuser"), NA, NA, "A list of database information in the order: host, user, password, database"),
    defineParameter(".useCache", "logical", FALSE, NA, NA, "Should this entire module be run with caching activated? This is generally intended for data-type modules, where stochasticity and time are not relevant")
  ),
  inputObjects = bind_rows(
    expectsInput(objectName = "scenario", objectClass ="data.table", desc = 'The name of the scenario and its description', sourceURL = NA),
    expectsInput(objectName = "castordb", objectClass ="SQLiteConnection", desc = "A rsqlite database that stores, organizes and manipulates castor realted information", sourceURL = NA),
    expectsInput(objectName = "boundaryInfo", objectClass ="character", desc = NA, sourceURL = NA),
    expectsInput(objectName = "extent", objectClass ="list", desc = NA, sourceURL = NA),
    
    expectsInput(objectName ="foreststate", objectClass ="data.table", desc = 'The current state of the forest from dataCastor', sourceURL = NA),
    expectsInput(objectName ="updateInterval", objectClass ="numeric", desc = 'The length of the time period. Ex, 1 year, 5 year', sourceURL = NA)
    
  ),
  outputObjects = bind_rows(
    createsOutput(objectName = NA, objectClass = NA, desc = NA)
  )
))

doEvent.uploadCastor = function(sim, eventTime, eventType) {
  switch(
    eventType,
    init = {
      sim <- Init(sim) #if the schema exists - delete all the rows that are labeled with the scenario and if it doesn't make it
      sim <- scheduleEvent(sim, end(sim), "uploadCastor", "save", 99999)
    },
    save = {
      sim <- save.currentState(sim)
      sim <- save.reports(sim)
    },
    
    warning(paste("Undefined event type: '", current(sim)[1, "eventType", with = FALSE],
                  "' in module '", current(sim)[1, "moduleName", with = FALSE], "'", sep = ""))
  )
  return(invisible(sim))
}

Init <- function(sim) {
  
  #check to see if a scenario table exists. If it does -- delete from the table where scenario is equal to the scenario
  connx<-DBI::dbConnect(dbDriver("PostgreSQL"), 
                        host=P(sim, "dbInfo", "uploadCastor")[[1]], 
                        dbname = P(sim, "dbInfo", "uploadCastor")[[4]], 
                        port='5432', 
                        user=P(sim, "dbInfo", "uploadCastor")[[2]],
                        password= P(sim, "dbInfo", "uploadCastor")[[3]])

  
  #Does the schema exist?
  if(nrow(dbGetQuery(connx, paste0("SELECT schema_name FROM information_schema.schemata WHERE schema_name = '", P(sim, "aoiName", "uploadCastor") ,"';"))) > 0){
    message("...remove old information")
    #remove all the rows that have the scenario name in them
    if(!is.null(sim$foreststate)){
      message("...Add new forest state")
      dbExecute(connx, paste0("DELETE FROM ",P(sim, "aoiName", "uploadCastor"), ".state where aoi = '", P(sim, "aoiName", "uploadCastor"), "' and compartment in('",paste(sim$boundaryInfo[[3]], sep = " ", collapse = "','"),"');"))
    }
    
    dbExecute(connx, paste0("DELETE FROM ",P(sim, "aoiName", "uploadCastor"), ".scenarios where scenario = '", sim$scenario$name, "';"))
    dbExecute(connx, paste0("INSERT INTO ",P(sim, "aoiName", "uploadCastor"), ".scenarios (scenario, description, rank) values ('", sim$scenario$name,"', '", sim$scenario$description, "', 0);"))
    
    sim$zoneManagement
    if(!is.null(sim$zoneManagement)){
      message("...Add new forest zones")
    dbExecute(connx, paste0("DELETE FROM ",P(sim, "aoiName", "uploadCastor"), ".zonemanagement where scenario = '", sim$scenario$name, "';"))
    }
    
    lapply(dbGetQuery(connx, paste0("SELECT table_name FROM information_schema.tables WHERE table_schema  = '", P(sim, "aoiName", "uploadCastor") ,"' and table_name in ('disturbance', 'growingstock', 'rsf',  'fisher', 'fisherabm', 'harvest', 'yielduncertainty',  'grizzly_survival') ;"))$table_name, function (x){
      dbExecute(connx, paste0("DELETE FROM ",P(sim, "aoiName", "uploadCastor"), ".",x," where scenario = '", sim$scenario$name, "' and compartment in('",paste(sim$boundaryInfo[[3]], sep = " ", collapse = "','"),"');"))
    }) 
    
    lapply(dbGetQuery(connx, paste0("SELECT table_name FROM information_schema.tables WHERE table_schema  = '", P(sim, "aoiName", "uploadCastor") ,"' and table_name in ('survival',  'volumebyarea',  'caribou_abundance') ;"))$table_name, function (y){
     dbExecute(connx, paste0("DELETE FROM ",P(sim, "aoiName", "uploadCastor"), ".",y," where scenario = '", sim$scenario$name, "' ;"))
    })
    
   dbDisconnect(connx)
  }else{
    #Create the schema and all the tables
   
    dbExecute(connx, paste0("CREATE SCHEMA ",P(sim, "aoiName", "uploadCastor"),";"))
    dbExecute(connx, paste0("GRANT ALL ON SCHEMA ",P(sim, "aoiName", "uploadCastor")," TO appuser;"))
    dbExecute(connx, paste0("GRANT ALL ON SCHEMA ",P(sim, "aoiName", "uploadCastor")," TO castor_project;"))
    #Create the tables
    tableList = list(state = data.table(aoi=character(), compartment=character(), total= integer(), thlb= numeric(), early= integer(), mature= integer(), old= integer(), road = integer()),

                    scenarios = data.table(scenario =character(), description= character(), rank = integer()), 
                    harvest = data.table(scenario = character(), timeperiod = integer(), compartment = character(), target= numeric(), area= numeric(), volume = numeric(), age = numeric(), hsize = numeric(), avail_thlb= numeric(), transition_area = numeric(), transition_volume= numeric()), # , harvest_type = character()
                    growingstock = data.table(scenario = character(), compartment = character(), timeperiod = integer(), gs = numeric(), m_gs = numeric(), m_dec_gs = numeric()), 

                    rsf = data.table(scenario = character(), compartment = character(), timeperiod = integer(), critical_hab = character() , sum_rsf_hat = numeric() , sum_rsf_hat_75 = numeric(), per_rsf_hat_75 = numeric(), rsf_model= character()), 

                    survival = data.table(scenario = character(), compartment = character(), timeperiod = integer(), herd_bounds = character() , prop_age = numeric(), prop_mature = numeric(), prop_old = numeric(), survival_rate= numeric(), area = integer()),
                    grizzly_survival = data.table(scenario = character(), compartment = character(), timeperiod = integer(), gbpu_name = character(), total_roaded = numeric(), road_density = numeric(), survival_rate= numeric(), total_area = integer()),
                    caribou_abundance = data.table(scenario = character(), subpop_name = character(), timeperiod = integer(), area = integer(), core = numeric(), matrix = numeric(), 
                                                   abundance_r50 = numeric(), abundance_c80r50= numeric(), abundance_c80= numeric(), abundance_avg= numeric()
                                                   ),
                    disturbance = data.table(scenario = character(), compartment = character(), timeperiod= integer(),
                                             critical_hab = character(), total_area = numeric(), cut20 = numeric(), cut40 = numeric(), cut80 = numeric(), 
                                             road50 = numeric(), road250 = numeric(), road500 = numeric(),road750 = numeric(),
                                             c20r50 = numeric(), c20r250=numeric(), c20r500=numeric(),  c20r750=numeric(),
                                             c40r50 = numeric(), c40r250=numeric(), c40r500=numeric(),  c40r750=numeric(),
                                             c80r50 = numeric(), c80r250=numeric(), c80r500=numeric(),  c80r750=numeric(),
                                             c10_40r50=numeric(),  c10_40r500=numeric(), cut10_40=numeric()),
                    
                    yielduncertainty = data.table(scenario = character(), compartment = character(), timeperiod = integer(), projvol = numeric(), calibvol = numeric (), prob = numeric(), pred5 = numeric(), pred95 = numeric() ),
                    fisher=data.table(timeperiod = as.integer(), scenario = as.character(), compartment =  as.character(), openess = as.numeric(), zone = as.integer(), reference_zone = as.character(), rel_prob_occup = as.numeric(), denning= as.numeric(), rust= as.numeric(), cavity= as.numeric(), cwd= as.numeric(), mov= as.numeric(), d2 = as.numeric()),
                    fisherabm = data.table (timeperiod = as.integer(), scenario = as.character(), compartment = character(), n_f_adult = as.numeric (), n_f_juv = as.numeric (), n_f_disperse = as.numeric (), mean_age_f = as.numeric (), sd_age_f = as.numeric ()),
                    zonemanagement=data.table(scenario = as.character(), zoneid = as.integer(), reference_zone = as.character(), zone_column = as.character(), variable = as.character(), threshold = as.numeric(), type = as.character(), percentage = numeric(), multi_condition = as.character(), t_area = numeric(), denom = as.character(), start = as.integer(), stop = as.integer(), percent = numeric(), timeperiod = as.integer()))

    tablesUpload<-c("state", "scenarios", "harvest","growingstock", "rsf", "survival", "disturbance", "yielduncertainty", "fisher", "fisherabm", "zonemanagement", "grizzly_survival", "caribou_abundance")
    for(i in 1:length(tablesUpload)){
      dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), tablesUpload[[i]]), tableList[[tablesUpload[i]]], row.names = FALSE)
      dbExecute(connx, paste0("GRANT SELECT ON ", P(sim, "aoiName", "uploadCastor"),".", tablesUpload[[i]]," to appuser;"))
      dbExecute(connx, paste0("GRANT ALL ON ", P(sim, "aoiName", "uploadCastor"),".", tablesUpload[[i]]," to castor_project;"))
    }
    
    dbExecute(connx, paste0("INSERT INTO ",P(sim, "aoiName", "uploadCastor"), ".scenarios (scenario, description, rank) values ('", sim$scenario$name,"', '", sim$scenario$description, "', 0);"))
    dbDisconnect(connx)
  }
  return(invisible(sim))
}

save.currentState<- function(sim){
  if(!is.null(sim$foreststate)){
    connx<-DBI::dbConnect(dbDriver("PostgreSQL"), 
                          host=P(sim, "dbInfo", "uploadCastor")[[1]], 
                          dbname = P(sim, "dbInfo", "uploadCastor")[[4]], 
                          port='5432', 
                          user=P(sim, "dbInfo", "uploadCastor")[[2]],
                          password= P(sim, "dbInfo", "uploadCastor")[[3]])

  
    sim$foreststate[,aoi:= P(sim, "aoiName", "uploadCastor")]
    dbExecute(connx, paste0("DELETE FROM ",P(sim, "aoiName", "uploadCastor"), ".state where aoi = '", P(sim, "aoiName", "uploadCastor"), "' and compartment in('",paste(sim$boundaryInfo[[3]], sep = " ", collapse = "','"),"');"))
    dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'state'), 
                 sim$foreststate, append = T, row.names = FALSE)
  

    dbDisconnect(connx)
  }
  return(invisible(sim))
}

save.reports <-function (sim){

  connx<-DBI::dbConnect(dbDriver("PostgreSQL"), 
                        host=P(sim, "dbInfo", "uploadCastor")[[1]], 
                        dbname = P(sim, "dbInfo", "uploadCastor")[[4]], 
                        port='5432', 
                        user=P(sim, "dbInfo", "uploadCastor")[[2]],
                        password= P(sim, "dbInfo", "uploadCastor")[[3]])
  #harvestingReport
  if(!is.null(sim$harvestReport)){
    message("writing harvest report")
    dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'harvest'),
                 sim$harvestReport, append = T,
                 row.names = FALSE)
  }
  #GrowingStockReport
  if(!is.null(sim$growingStockReport)){
    message("writing growingstock report")
    test<<-sim$growingStockReport
    dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'growingstock'), 
                 sim$growingStockReport, append = T,
                 row.names = FALSE)
  }
  #rsf
  if(!is.null(sim$rsf)){
    message("writing rsf report")
    dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'rsf'), 
                 sim$rsf, append = T,row.names = FALSE)
  }
  # caribou survival
  if(!is.null(sim$tableSurvivalReport)){
    message("writing caribou survival report")
    dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'survival'), 
                 sim$tableSurvivalReport, append = T,row.names = FALSE)
  }
  #disturbance
  if(!is.null(sim$disturbanceReport)){
    message("writing disturbance report")
    DBI::dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'disturbance'), 
                      sim$disturbanceReport, append = T,row.names = FALSE)
  }
  #yielduncertainty
  if(!is.null(sim$yielduncertain)){
    message("writing uncertainty report")
    DBI::dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'yielduncertainty'), 
                      sim$yielduncertain, append = T,row.names = FALSE)
  }
  #volumebyarea
  if(!is.null(sim$volumebyareaReport)){
    message("writing volume by area report")
    DBI::dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'volumebyarea'), 
                      sim$volumebyareaReport, append = T, row.names = FALSE)
  }
  #fisher
  if(!is.null(sim$fisherReport)){
    message("writing fisher report")
    DBI::dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'fisher'), 
                      sim$fisherReport, append = T, row.names = FALSE)
  }
  #fisher ABM
  if(!is.null(sim$fisherABMReport)){
    message("writing fisher ABM report")
    DBI::dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'fisherabm'), 
                      sim$fisherABMReport, append = T, row.names = FALSE)
  }
  #zonal constraints
  if(!is.null(sim$zoneManagement)){
    message("writing land cover constraint report")
    DBI::dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'zonemanagement'), 
                      sim$zoneManagement, append = T, row.names = FALSE)
  }
  # grizzly bear survival
  if(!is.null(sim$tableGrizzSurvivalReport)){
    message("writing grizzly bear survival report")
    dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'grizzly_survival'), 
                 sim$tableGrizzSurvivalReport, append = T,row.names = FALSE)
  }
  # caribou abundance
  if(!is.null(sim$tableAbundanceReport)){
    message("writing abundance report")
    dbWriteTable(connx, c(P(sim, "aoiName", "uploadCastor"), 'caribou_abundance'), 
                 sim$tableAbundanceReport, append = T,row.names = FALSE)
  }
  dbDisconnect(connx)
  
  return(invisible(sim)) 
}

save.rasters <-function (sim){
  #rasters
  if(is.null(sim$foreststate)){
    connx<-DBI::dbConnect(dbDriver("PostgreSQL"), 
                          host=P(sim, "dbInfo", "uploadCastor")[[1]], 
                          dbname = P(sim, "dbInfo", "uploadCastor")[[4]], 
                          port='5432', 
                          user=P(sim, "dbInfo", "uploadCastor")[[2]],
                          password= P(sim, "dbInfo", "uploadCastor")[[3]])
    ##blocks
    message('....cutblock raster')
    commitRaster(layer = paste0(sim$scenario$name, "_",sim$boundaryInfo[[3]][[1]], "_harvestBlocks.tif"), 
                 schema = P(sim, "aoiName", "uploadCastor"), 
                 name = paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_cutblocks"), 
                 dbInfo = P(sim, "dbInfo", "uploadCastor") )
    dbExecute(connx, paste0("GRANT SELECT ON ", P(sim, "aoiName", "uploadCastor"),".", paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_cutblocks")," to appuser;"))
    dbExecute(connx, paste0("GRANT ALL ON ", P(sim, "aoiName", "uploadCastor"),".", paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_cutblocks")," to castor_project;"))
    
    ##roads
    if(!is.null(sim$roads)){

    message('....roads raster')
    commitRaster(layer = paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_", P(sim, "roadCastor", "roadMethod"),"_year_", time(sim)*sim$updateInterval, ".tif"), 
                 schema = P(sim, "aoiName", "uploadCastor"), name = paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_roads"),
                 dbInfo = P(sim, "dbInfo", "uploadCastor"))
    dbExecute(connx, paste0("GRANT SELECT ON ", P(sim, "aoiName", "uploadCastor"),".", paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_roads")," to appuser;"))
    dbExecute(connx, paste0("GRANT ALL ON ", P(sim, "aoiName", "uploadCastor"),".", paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_roads")," to castor_project;"))
    
    }
    ##zoneConstraint
    message('....constraint raster')
    commitRaster(layer = paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]], "_constraints.tif"), 
                 schema = P(sim, "aoiName", "uploadCastor"), 
                 name = paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_constraint"),
                 dbInfo = P(sim, "dbInfo", "uploadCastor"))
    dbExecute(connx, paste0("GRANT SELECT ON ", P(sim, "aoiName", "uploadCastor"),".", paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_constraint")," to appuser;"))
    dbExecute(connx, paste0("GRANT ALL ON ", P(sim, "aoiName", "uploadCastor"),".", paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_constraint")," to castor_project;"))
    ## fisher territories
    message('....fisher territory raster')
    commitRaster(layer = paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]], "_fisherterritories.tif"), 
                 schema = P(sim, "aoiName", "uploadCastor"), 
                 name = paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_fisherterritories"),
                 dbInfo = P(sim, "dbInfo", "uploadCastor"))
    dbExecute(connx, paste0("GRANT SELECT ON ", P(sim, "aoiName", "uploadCastor"),".", paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_fisherterritories")," to appuser;"))
    dbExecute(connx, paste0("GRANT ALL ON ", P(sim, "aoiName", "uploadCastor"),".", paste0(sim$scenario$name, "_", sim$boundaryInfo[[3]][[1]],"_fisherterritories")," to castor_project;"))
    
    ##rsfEND
  }
  return(invisible(sim)) 
}

#---Other functions
commitRaster<-function(layer, schema, name, dbInfo){
  #print(paste0('raster2pgsql -s 3005 -d -I -C -M -N 2147483648  ', layer, ' -t 100x100 ', schema, '.', name, ' |  psql postgres://', dbInfo[[2]], ':', dbInfo[[3]], '@', dbInfo[[1]], ':5432/',dbname = dbInfo[[4]]))
  system("cmd.exe", 
         input = paste0('raster2pgsql -s 3005 -d -I -C -M -N 2147483648  ', layer, ' -t 100x100 ', schema, '.', name, ' |  psql postgres://', dbInfo[[2]], ':', dbInfo[[3]], '@', dbInfo[[1]], ':5432/',dbname = dbInfo[[4]]), 
         show.output.on.console = FALSE, 
         invisible = TRUE)
}
