PROGRAM blend_precip_singlemodel_dressed_gammacdf

    ! ---- this version estimates forecast and analyzed CDFs with either empirical or
    !      Gamma distributions estimated from previous 60 forecast days.


USE netcdf

LOGICAL, PARAMETER :: empirical = .false. ! if = 1 use empirical CDFs for quantile otherwise fitted Gamma
LOGICAL, PARAMETER :: gammadress = .false. ! full fitted Gamma dressing or simple Gaussian
    ! centered on each ensemble member
LOGICAL, PARAMETER :: csgd = .true. ! whether or not to perform a variant of Scheuerer's CSGD
INTEGER, PARAMETER :: nxa = 464  ! number of grid pts in x-dir for 1/8-deg analysis grid
INTEGER, PARAMETER :: nya = 224  ! number of grid pts in y-dir for 1/8-deg analysis grid 
INTEGER, PARAMETER :: nens_ecmwf = 50 ! number of ECMWF perturbed ensemble members
INTEGER, PARAMETER :: nens_cmc   = 20 ! number of CMC perturbed ensemble members
INTEGER, PARAMETER :: nens_ncep  = 20 ! number of NCEP perturbed ensemble members
INTEGER, PARAMETER :: npct = 90 ! number of thresholds for CDFs
INTEGER, PARAMETER :: nthreshes = 7 ! number of precipitation threshold amounts where PQPF calculated.
INTEGER, PARAMETER :: npvals = 68 ! number of precipitation amounts where gamma statistics tallied
INTEGER, PARAMETER :: nclim_vals = 7 ! when ens mean precip zero, we estimate Gamma dist
    ! parameters of nonzero precipitation stratified by values of the climatological value of POP.
    ! this is the index into that array of thresholds of climatological precipitation.
INTEGER, PARAMETER :: nclim_p1_vals = 8 
INTEGER, PARAMETER :: nlo_int_hi_vals = 3 ! dimension for lowest, intermediate, highest 
    ! member of closest histogram
INTEGER, PARAMETER :: npcatvals = 3 ! closest_histogram stats are stratified by ens-mean amount.
INTEGER, PARAMETER :: n25 = 25
    ! closest_histogram array.
INTEGER, PARAMETER :: ncsgd_params = 6

REAL, PARAMETER, DIMENSION(nthreshes) :: pthreshes = &
    (/0.254, 1.0, 2.5, 5.0, 10.0, 25.0, 50.0/) ! precipitation threshold amounts where we compute PQPF

INTEGER :: nstride ! for 3 x 3 stencil of grid points, how many grid pts between samples.

REAL, DIMENSION(npct) :: thresh ! the precip amount thresholds for CDFs
REAL, DIMENSION(npvals) :: precip_values ! precip amts where gamma distribution information collected
REAL, DIMENSION(npvals, npcatvals, nlo_int_hi_vals) :: gamma_shapes ! shape parameters for 
    ! Gamma distributions
REAL, DIMENSION(npvals, npcatvals, nlo_int_hi_vals) :: gamma_scales ! scale parameters for 
    ! Gamma distributions
REAL, DIMENSION(npvals, npcatvals, nlo_int_hi_vals) :: fraction_zeros ! fraction of 
    ! samples with zero precip.
REAL, DIMENSION(nclim_p1_vals) :: gamma_shape_fclimpop ! when ens mean = 0., 
    ! shape parameter of nonzero dressed values.
REAL, DIMENSION(nclim_p1_vals) :: gamma_scale_fclimpop ! when ens mean = 0., 
    ! scale parameter of nonzero dressed values.
REAL, DIMENSION(nclim_p1_vals) :: fraction_zeros_fclimpop ! when ens mean = 0., 
    ! fraction of samples with zero dressed values
REAL, DIMENSION(nclim_vals) :: climo_pop_thresholds ! climatological probability thresholds 
    ! between elements of gamma_shape_fclimpop, etc.
REAL*8, DIMENSION(ncsgd_params) :: csgd_parameters

CHARACTER*2 chh, cmm
CHARACTER*3, DIMENSION(12) :: cmonths ! Jan, Feb, etc.
CHARACTER*256 data_directory ! location where data is stored.
CHARACTER*256 pclimo_infile ! name of file with climo probs
CHARACTER*256 infile_early ! ecmwf forecast data for today
CHARACTER*256 infile_late ! ecmwf forecast data for today
CHARACTER*256 infile_closest_histogram ! netCDF file name with closest_histogram array
CHARACTER*256 infile_gamma_parameters ! netCDF file containing Gamma dressing distribution params.
CHARACTER*256 infile_CSGD_climatology ! netCDF file containing CSGD analyzed climatology parameters
CHARACTER*256 infile_CSGD_regress_params ! CSGD regression parameters
CHARACTER*256 outfile ! name of flat fortran file with output prob forecasts
CHARACTER*256 outfile_HXLR ! name of flat fortran file with output prob HXLR forecasts
CHARACTER*10 cyyyymmddhh ! year,month,day,hour of initial time of forecast
CHARACTER*3 cleade ! ending hour of precip forecast accumulation, 3 digits, e.g., '024'
CHARACTER*3 cleadb ! beginning hour of precip forecast accumulation, 3 digits, e.g., '012'
CHARACTER*5 cmodel ! 'ECMWF', 'NCEP', 'CMC' currently

INTEGER*2, DIMENSION(nxa,nya) :: conusmask  ! inherited from CCPA data set
REAL, DIMENSION(npcatvals) :: precip_histogram_thresholds
REAL b0_mean, b1_mean, b0_spread, b1_spread ! heteroscedastic extended logistic regression coefficients

! ---- 1/8 deg. Lat/Lon arrays (i.e. CCPA grid)

REAL, ALLOCATABLE, DIMENSION(:,:,:) :: ensemble_ccpa ! ecmwf ens precip forecast on 1/8-deg ccpa grid

! ---- x25 array with 5 x 5 stencil of data

REAL, ALLOCATABLE, DIMENSION(:,:,:,:) :: ensemble_ccpa_x25 ! ecmwf ens precip forecast on 
    ! 1/8-deg ccpa grid with 5x5 stencil

! --- other arrays 

REAL, ALLOCATABLE, DIMENSION(:,:) :: closest_histogram ! contains histogram of closest member to analyzed
REAL, ALLOCATABLE, DIMENSION(:,:,:) :: climo_prob ! climatological event probability
REAL, ALLOCATABLE, DIMENSION(:,:) :: CSGD_climo_mean
REAL, ALLOCATABLE, DIMENSION(:,:) :: CSGD_climo_mu
REAL, ALLOCATABLE, DIMENSION(:,:) :: CSGD_climo_sigma
REAL, ALLOCATABLE, DIMENSION(:,:) :: CSGD_climo_shift
REAL, ALLOCATABLE, DIMENSION(:,:) :: rlonsa ! precip analysis grid lat/lons
REAL, ALLOCATABLE, DIMENSION(:,:) :: rlatsa ! precip analysis grid lat/lons
REAL, ALLOCATABLE, DIMENSION(:,:) :: ensemble_mean ! precip analysis grid lat/lons
REAL, ALLOCATABLE, DIMENSION(:,:,:) :: prob_forecast  ! final probability forecast
REAL, ALLOCATABLE, DIMENSION(:,:,:) :: prob_forecast_raw  ! output raw ensemble probability forecast
REAL, ALLOCATABLE, DIMENSION(:,:,:) :: prob_forecast_qmapped ! output quantile-mapped ensemble prob forecast
REAL, ALLOCATABLE, DIMENSION(:,:,:) :: prob_forecast_CSGD ! output quantile-mapped ensemble prob forecast
REAL, ALLOCATABLE, DIMENSION(:,:,:) :: gamma_shape_qmap_forecast
REAL, ALLOCATABLE, DIMENSION(:,:,:) :: gamma_scale_qmap_forecast
REAL, ALLOCATABLE, DIMENSION(:,:,:) :: fraction_zero_qmap_forecast
REAL, ALLOCATABLE, DIMENSION(:,:) :: gamma_shape_qmap_analysis
REAL, ALLOCATABLE, DIMENSION(:,:) :: gamma_scale_qmap_analysis
REAL, ALLOCATABLE, DIMENSION(:,:) :: fraction_zero_qmap_analysis
REAL, ALLOCATABLE, DIMENSION(:,:,:) :: precip_anal_cdf
REAL, ALLOCATABLE, DIMENSION(:,:,:,:) :: ensemble_cdf
REAL, ALLOCATABLE, DIMENSION(:,:) :: rho
!REAL, ALLOCATABLE, DIMENSION(:,:) :: shift


REAL, ALLOCATABLE, DIMENSION(:,:) :: ensmean ! for HXLR, quantile-mapped 25x larger ens mean
REAL, ALLOCATABLE, DIMENSION(:,:) :: stddev ! for HXLR, quantile-mapped 25x larger ens spread
REAL, ALLOCATABLE, DIMENSION(:,:) :: POP ! probability of precipitaton (> 0.254 mm)

integer :: ierr      ! return variable for BAOPEN
integer :: ios       ! return variable for Fortran I/O, Allocation statements
integer :: ifcstint  ! forecast interval. Set depending on cpcpvar.

integer :: iyyyymmddhh,jyyyymmddhh
integer :: iyear,imo,iday,ihour,idoy ! Parsed date variables from iyyyymmddhh
integer :: jyear,jmo,jday,jhour,jdoy ! Parsed date variables for valid date

integer :: nens    ! number of ensemble members

LOGICAL exchangeable

! ---- Initialize

DATA cmonths /'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'/
!DATA pthreshes /0.254, 1.0, 2.5, 5.0, 10.0, 25.0, 50.0/
DATA data_directory /'/Users/thamill/precip/ecmwf_data/'/
!DATA data_directory /'/Projects/Reforecast2/netcdf/NationalBlend/'/

! --- Via command line, read in the input year/mo/day/hr and the forecast resolution 
!     we're working with.  Process date to determine the day of the month as an integer

CALL getarg(1,cyyyymmddhh)  ! input year month day hour of initial condition, 'yyyymmddhh' format
CALL getarg(2,cleade)       ! forecast lead time for beginning of precip accum period, hours, e.g.'060'
CALL getarg(3,cmodel)       ! for my test data ECMWF NCEP or CMC

PRINT *,'****************************************************************************'
PRINT *,'RUNNING blend_precip_singlemodel_dressed_gammacdf.x ',cyyyymmddhh,' ',&
    cleade,' ',cmodel
PRINT *,'****************************************************************************'

IF (TRIM(cmodel) .eq. 'ECMWF') THEN 
    nens = nens_ecmwf
    nens_qmap = 1  ! exchangeable, CDFs same for all members
    exchangeable = .TRUE.
ELSE IF (TRIM(cmodel) .eq. 'NCEP') THEN 
    nens = nens_ncep
    nens_qmap = 1 
    exchangeable = .TRUE.
ELSE IF (TRIM(cmodel) .eq. 'CMC') THEN 
    nens = nens_cmc
    nens_qmap = nens_cmc 
    exchangeable = .FALSE.
ENDIF    
nmembersx25 = nens*n25
PRINT *,'nens, nmembersx25 = ', nens, nmembersx25

cmm = cyyyymmddhh(5:6)
READ (cmm,'(i2)') imonth

write(6,*)' Command line arguments:'
write(6,110)  cyyyymmddhh, cleade, cmodel
110 format(1x,'cyyyymmddhh: ',A/1x,'cleade: ',A/1x,'cmodel: ',A/1x)

! ---- Convert character based variables from command line to integers

READ (cyyyymmddhh,'(i10)') iyyyymmddhh
READ (cleade,'(i3)') ileade
PRINT *,'iyyyymmddhh, ileade = ',iyyyymmddhh, ileade
nstride = nint(1.+4.*ileade/168.)

! ---- Set ifcstint and ipcpvar according to cpcpvar

ifcstint = 12
ileadb = ileade - ifcstint
PRINT *,'ileadb = ',ileadb
WRITE (cleadb,'(i3)') ileadb

! ---- Parse the initializtion date; determine the valid hour.  This is dependent on the
!      precip variable (cpcpvar), the model initialization (iyyyymmddhh), and forecast 
!      ending hour (ileade).

iendhour=0
call doy(iyyyymmddhh,iyear,imo,iday,ihour,idoy)
call updat(iyyyymmddhh,ileade,jyyyymmddhh)
call doy(jyyyymmddhh,jyear,jmo,jday,jhour,jdoy)
iendhour=jhour

write(6,*)'Model Initialization: ',iyyyymmddhh
write(6,*)'Forecast Projection Ending: ',ileade
write(6,*)'Forecast Valid Date/Hour: ',jyyyymmddhh,iendhour

! ---- Allocate dynamic arrays

write(6,*)'Allocating dynamic arrays...'
ALLOCATE (ensemble_ccpa(nxa,nya,nens))
ALLOCATE (ensemble_mean(nxa,nya))
ALLOCATE (rlonsa(nxa,nya),rlatsa(nxa,nya))
ALLOCATE (prob_forecast(nxa,nya,nthreshes))
ALLOCATE (prob_forecast_raw(nxa,nya,nthreshes))
ALLOCATE (prob_forecast_qmapped(nxa,nya,nthreshes))

ALLOCATE (climo_prob(nxa,nya,nthreshes))
ALLOCATE (ensemble_ccpa_x25(n25,nxa,nya,nens))
ALLOCATE (gamma_shape_qmap_forecast(nxa,nya,nens_qmap))
ALLOCATE (gamma_scale_qmap_forecast(nxa,nya,nens_qmap))
ALLOCATE (fraction_zero_qmap_forecast(nxa,nya,nens_qmap))
ALLOCATE (gamma_shape_qmap_analysis(nxa,nya))
ALLOCATE (gamma_scale_qmap_analysis(nxa,nya))
ALLOCATE (fraction_zero_qmap_analysis(nxa,nya))
ALLOCATE (ensmean(nxa,nya))
ALLOCATE (stddev(nxa,nya))
ALLOCATE (POP(nxa,nya))
IF (csgd) ALLOCATE (prob_forecast_CSGD(nxa,nya,nthreshes))
IF (csgd) ALLOCATE (CSGD_climo_mean(nxa,nya))
IF (csgd) ALLOCATE (CSGD_climo_mu(nxa,nya))
IF (csgd) ALLOCATE (CSGD_climo_sigma(nxa,nya))
IF (csgd) ALLOCATE (CSGD_climo_shift(nxa,nya))
!IF (csgd) ALLOCATE (shift(nxa,nya))
IF (csgd) ALLOCATE (rho(nxa,nya))


prob_forecast(:,:,:) = -99.99
prob_forecast_raw(:,:,:) = -99.99
prob_forecast_qmapped(:,:,:) = -99.99

! ---- read in the precipitation climatology appropriate to this threshold

IF (iendhour .eq. 0)  THEN
    pclimo_infile = TRIM(data_directory) // 'apcp_climatologies_12_to_00UTC_'// &
    cmonths(imonth)//'_2002_to_2016.nc'
ELSE
    pclimo_infile = TRIM(data_directory) // 'apcp_climatologies_00_to_12UTC_'// &
    cmonths(imonth)//'_2002_to_2016.nc'
ENDIF

write(6,*) 'Calling read_precip_climatology_multithresh'
CALL read_precip_climatology_multi_thresh(nxa, nya, nthreshes, pthreshes, &
    pclimo_infile, climo_prob, rlonsa, rlatsa, conusmask)

! ---- Read precipitation forecasts for all ensemble members from netCDF files.
!      These files contains the 1/8 deg. grid data.

ensemble_ccpa = -99.99
IF (TRIM(cmodel) .eq. 'CMC' .or. TRIM(cmodel) .eq. 'NCEP' .or. &
TRIM(cmodel) .eq. 'ECMWF')  THEN
    infile_late = TRIM(data_directory) // TRIM(cmodel) // '_' // cyyyymmddhh // &
        '_leadtime' // TRIM(ADJUSTL(cleade)) // 'h.nc'
    infile_early = TRIM(data_directory) // TRIM(cmodel) // '_' // cyyyymmddhh // &
        '_leadtime' // TRIM(ADJUSTL(cleadb)) // 'h.nc'
    CALL read_forecasts_local (nxa, nya, nens, infile_early, infile_late, &
        ensemble_ccpa)
ELSE
    PRINT *,'invalid model choice: ', TRIM(cmodel)
    PRINT *,'stopping.'
    STOP
ENDIF

! ---- If CSGD forecasts desired (empirical .eq.)

IF (csgd) THEN
    IF (iendhour .eq. 0) THEN 
        infile_CSGD_climatology = &
            '/Users/mscheuerer/Desktop/Tom-NBM/CSGD_climatology_CCPA_0p125deg_00Z.nc'
    ELSE
        infile_CSGD_climatology = &
            '/Users/mscheuerer/Desktop/Tom-NBM/CSGD_climatology_CCPA_0p125deg_00Z.nc'
    ENDIF
    CALL read_CSGD_climatology_parameters(infile_CSGD_climatology, nxa, nya, &
        jyear, jmo, jday, CSGD_climo_mean, CSGD_climo_mu, CSGD_climo_sigma, &
        CSGD_climo_shift)

    infile_CSGD_regress_params = '/Users/mscheuerer/Desktop/Tom-NBM/' // &
        TRIM(cmodel) // '/' // TRIM(cmodel) // '_parameters_leade' // &
        TRIM(ADJUSTL(cleade)) //'h_' // '2016050100.nc' !cyyyymmddhh // '.nc' 

    CALL read_CSGD_regression_parameters(nxa, nya, infile_CSGD_regress_params, &
        ncsgd_params, csgd_parameters, rho)
ENDIF 

! ---- only bother processing if there is valid positive data
    
pmax = MAXVAL(ensemble_ccpa)
IF (pmax .gt. 0.) THEN

    ! ---- For purposes of having a baseline for comparison, generate an 
    !      ensemble probability simply from the relative frequency.

    PRINT *, 'Calling raw_ensemble_probs_singlemodel'
    PRINT *, 'pthreshes = ', pthreshes
    CALL raw_ensemble_probs_singlemodel(nxa, nya, nens, nthreshes, pthreshes, &
        ensemble_ccpa, prob_forecast_raw, ensemble_mean)  
    PRINT *,'max(ensemble_ccpa) = ', maxval(ensemble_ccpa)
    PRINT *,'max(ensemble_mean) = ', maxval(ensemble_mean)  
    
    ! ---- This version of the program offers the user the option of using 
    !      empirically generated CDFs in the quantile-mapping process, or gamma-
    !      distributed CDFs
    
    IF (empirical) THEN
        
        ! --- read in forecast and analyzed CDFs at pre-defined precipitation amounts.
        
        ALLOCATE(precip_anal_cdf(nxa,nya,npct))
        ALLOCATE(ensemble_cdf(nxa,nya,nens_qmap,npct))
        
        PRINT *,'calling read_cdf_netcdf_anal_forecast'
        CALL read_cdf_netcdf_anal_forecast(nxa, nya, npct, nens_qmap, iyyyymmddhh, &
            cleade, cmodel, data_directory, precip_anal_cdf, ensemble_cdf, thresh)
            
        CALL control_ensemble_quantile_mapping_x25(nxa, nya, npct, nstride, &
            nens, nens_qmap, n25, thresh, conusmask, precip_anal_cdf, &
            ensemble_cdf, ensemble_ccpa, ensemble_ccpa_x25, &
            ensmean, stddev, POP)
            
        DEALLOCATE(precip_anal_cdf, ensemble_cdf)
        
    ELSE
    
        ! ---- read in the gamma parameters for each forecast and for the analyzed precip.
        !      we note that the CMC ensemble has biases which may differ for each
        !      member, so the array dimensioning is different for this system.

        PRINT *,'calling determine_gamma_parameters_for_quantile_mapping'
        CALL determine_gamma_parameters_for_quantile_mapping(nxa, nya, &
            iyyyymmddhh, imonth, nens_qmap, data_directory, cmodel, cleade, &
            cmonths, conusmask, gamma_shape_qmap_forecast, gamma_scale_qmap_forecast, &
            fraction_zero_qmap_forecast, gamma_shape_qmap_analysis, &
            gamma_scale_qmap_analysis, fraction_zero_qmap_analysis)

        ! ---- compute and apply the quantile mapping bias correction, 
        !      including the use of surrounding grid points

        PRINT *,'calling control_quantile_mapping_x25_singlemodel'
        CALL control_quantile_mapping_singlemodel_gamma(nxa, nya, &
            nstride, nens, nens_qmap, n25, exchangeable, conusmask, &
            ensemble_ccpa, gamma_shape_qmap_forecast, &
            gamma_scale_qmap_forecast, fraction_zero_qmap_forecast, &
            gamma_shape_qmap_analysis, gamma_scale_qmap_analysis, &
            fraction_zero_qmap_analysis, ensemble_ccpa_x25, &
            ensmean, stddev, POP)
            
    ENDIF
    PRINT *, 'maxval(ensemble_ccpa_x25) = ', maxval(ensemble_ccpa_x25)
    
    ! ---- Get probabilities from quantile-mapped ensemble before dressing.

    PRINT *, 'Calling ensemble_probs_x25_singlemodel'
    CALL ensemble_probs_x25_singlemodel (nxa, nya, nens, nthreshes, n25, &
        pthreshes, ensemble_ccpa_x25, prob_forecast_qmapped)  
    
    ! ---- read in the closest histogram information, the gamma distribution
    !      parameters.   These provide statistically informed dressing
    !      information for the ensemble to deal with remaining spread
    !      deficiency errors.

    ALLOCATE(closest_histogram(nmembersx25,npcatvals))
    IF (empirical) THEN
        infile_closest_histogram = TRIM(data_directory) // TRIM(cmodel) // &
            '/closest_histogram_' // TRIM(cmodel) // '_date=' // &
            cyyyymmddhh // '_lead=' // TRIM(cleade) // '.nc'   
    ELSE
        infile_closest_histogram = TRIM(data_directory) // TRIM(cmodel) // &
            '/closest_histogram_' // TRIM(cmodel) // '_date=' // &
            cyyyymmddhh // '_lead=' // TRIM(cleade) // '_gammaqmap.nc'    
    ENDIF 
    PRINT *, 'calling read_closest_histogram_singlemodel'
    CALL read_closest_histogram_singlemodel (nmembersx25, npcatvals, &
        infile_closest_histogram, closest_histogram, &
        precip_histogram_thresholds)
    

    ! ---- Generate a final probability from the exceedance probability
    !      from a weighted sum of kernels appropriate for each sorted, 
    !      quantile-mapped member

    IF (gammadress) THEN

        IF (empirical) THEN
            infile_gamma_parameters = TRIM(data_directory) // TRIM(cmodel) // &
                '/gamma_fraction_zero_dressing_' // TRIM(cmodel) // '_date=' // &
                cyyyymmddhh // '_lead=' // TRIM(cleade) //'.nc'
        ELSE
            infile_gamma_parameters = TRIM(data_directory) // TRIM(cmodel) // &
                '/gamma_fraction_zero_dressing_' // TRIM(cmodel) // '_date=' // &
                cyyyymmddhh // '_lead=' // TRIM(cleade) //'_gammaqmap.nc'
        ENDIF    
        PRINT *, 'calling read_dressing_parameters_singlemodel'
        CALL read_dressing_parameters_singlemodel(npvals, npcatvals, &
            nlo_int_hi_vals, nclim_p1_vals, nclim_vals, &
            infile_gamma_parameters, precip_values, gamma_shapes, &
            gamma_scales, fraction_zeros, gamma_shape_fclimpop, &
            gamma_scale_fclimpop, fraction_zeros_fclimpop, &
            climo_pop_thresholds)  

        PRINT *,'calling ensemble_probs_dressweight_x25'
        CALL ensemble_probs_dressweight_x25 (n25, nxa, nya, nens, &
            nmembersx25, npcatvals, npvals, nlo_int_hi_vals, &
            nclim_p1_vals, nclim_vals, nthreshes, pthreshes, precip_values, &
            ensemble_ccpa_x25, closest_histogram, precip_histogram_thresholds, &
            gamma_shapes, gamma_scales, fraction_zeros, gamma_shape_fclimpop, &
            gamma_scale_fclimpop, fraction_zeros_fclimpop, climo_pop_thresholds, &
            conusmask, climo_prob, prob_forecast_qmapped, prob_forecast)
    ELSE
        CALL ensemble_probs_dressweight_x25_normal (n25, nxa, nya, nens, &
            nmembersx25, npcatvals, nthreshes, pthreshes, &
            ensemble_ccpa_x25, closest_histogram, precip_histogram_thresholds, &
            conusmask, climo_prob, prob_forecast_qmapped, prob_forecast)
    ENDIF    
    DEALLOCATE(closest_histogram)

    write(6,fmt='(A)')' Dressed Model Precipitation Amount Stats (1/8 deg. grid):'
    write(6,fmt='(4(A10,1X))')'MIN','MAX','MEAN'
    write(6,fmt='(A10,1X,3(F10.5,1X))') minval(ensemble_ccpa),&
        maxval(ensemble_ccpa),sum(ensemble_ccpa)/(nxa*nya*nens)
        
        
    IF (csgd) THEN
        CALL ensemble_probs_csgd (nxa, nya, nthreshes, ncsgd_params, &
            pthreshes, conusmask, ensmean, stddev, POP, CSGD_climo_mean, &
            CSGD_climo_mu, CSGD_climo_sigma, CSGD_climo_shift, &
            csgd_parameters, rho, prob_forecast_CSGD)
    ENDIF
         
ELSE
    ensemble_mean(:,:) = -99.99
ENDIF

PRINT *,'max prob_forecast = ', maxval(prob_forecast)
    
    
! ---- write the output to file(s)

IF (.not. empirical) THEN
    IF (gammadress) THEN
        outfile = TRIM(data_directory) // TRIM(cmodel) // '/' // &
            TRIM(cmodel) // '_' // TRIM(cleade) // 'h_IC' // &
            cyyyymmddhh // '_gammaqmap_gammadress.nc'  
    ELSE
        outfile = TRIM(data_directory) // TRIM(cmodel) // '/' // &
            TRIM(cmodel) // '_' // TRIM(cleade) // 'h_IC' // &
            cyyyymmddhh // '_gammaqmap_gaussdress.nc'
    ENDIF  
ELSE IF (empirical) THEN
    IF (gammadress) THEN
        outfile = TRIM(data_directory) // TRIM(cmodel) // '/' // &
            TRIM(cmodel) // '_' // TRIM(cleade) // 'h_IC' // &
            cyyyymmddhh // '_empirical_gammadress.nc'
    ELSE
        outfile = TRIM(data_directory) // TRIM(cmodel) // '/' // &
            TRIM(cmodel) // '_' // TRIM(cleade) // 'h_IC' // &
            cyyyymmddhh // '_empirical_gaussdress.nc' 
    ENDIF           
ENDIF
CALL write_output_to_netcdf(outfile, nxa, nya, nens, nthreshes, &
    pthreshes, rlonsa, rlatsa, climo_prob, conusmask, prob_forecast_raw, &
    prob_forecast_qmapped, prob_forecast, ensemble_mean)        

IF (csgd) THEN   
    IF (.not. empirical) THEN          
        outfile = TRIM(data_directory) // TRIM(cmodel) // '/' // &
            TRIM(cmodel) // '_' // TRIM(cleade) // 'h_IC' // &
            cyyyymmddhh // '_gammaqmap_csgd.nc'
    ELSE
        outfile = TRIM(data_directory) // TRIM(cmodel) // '/' // &
            TRIM(cmodel) // '_' // TRIM(cleade) // 'h_IC' // &
            cyyyymmddhh // '_empirical_csgd.nc'
    ENDIF        
    CALL write_output_to_netcdf(outfile, nxa, nya, nens, nthreshes, &
        pthreshes, rlonsa, rlatsa, climo_prob, conusmask, prob_forecast_raw, &
        prob_forecast_qmapped, prob_forecast_csgd, ensemble_mean)        
ENDIF       

DEALLOCATE(rlonsa, rlatsa, prob_forecast, prob_forecast_raw, &
    prob_forecast_qmapped, climo_prob, ensemble_ccpa, &
    ensemble_ccpa_x25, ensemble_mean, gamma_shape_qmap_forecast, &
    gamma_scale_qmap_forecast, fraction_zero_qmap_forecast, &
    gamma_shape_qmap_analysis, gamma_scale_qmap_analysis, &
    fraction_zero_qmap_analysis, ensmean, stddev, POP, stat=ios)

IF (csgd) DEALLOCATE (prob_forecast_CSGD)
IF (csgd) DEALLOCATE (CSGD_climo_mean)
IF (csgd) DEALLOCATE (CSGD_climo_mu)
IF (csgd) DEALLOCATE (CSGD_climo_sigma)
IF (csgd) DEALLOCATE (CSGD_climo_shift)
IF (csgd) DEALLOCATE (rho)

write(6,*)'Deallocation Status = ',ios
write(6,*)'Done!'

END PROGRAM blend_precip_singlemodel_dressed_gammacdf
