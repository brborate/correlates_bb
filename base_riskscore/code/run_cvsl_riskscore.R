#-----------------------------------------------
# obligatory to append to the top of each script
renv::activate(project = here::here(".."))
source(here::here("..", "_common.R"))
#-----------------------------------------------

# load required libraries and functions
library(tidyverse)
library(here)
library(methods)
library(SuperLearner)
library(e1071)
library(glmnet)
library(kyotil)
library(argparse)
library(vimp)
library(nloptr)
library(RhpcBLASctl)
library(conflicted)
conflicted::conflict_prefer("filter", "dplyr")
conflict_prefer("summarise", "dplyr")
library(mice)
library(COVIDcorr)

# Risk score analysis: Superlearner code requires computing environment with more than 10 cores!
num_cores <- parallel::detectCores()
if(num_cores < 10) stop("Number of cores on this computing environment are less than 10! Superlearner code needs atleast 11 cores to run smoothly.")

# Define code version to run
run_demo <- TRUE  # the demo version is simpler and runs faster!
run_prod <- FALSE # the prod version runs SL with the complete set of diverse learners and takes more time (around 5-7 hrs on a cluster machine!)

#source(paste0(here(), "/correlates_report/SL_risk_score/cluster_code/sl_screens.R")) # set up the screen/algorithm combinations
#source(paste0(here(), "/correlates_report/SL_risk_score/cluster_code/utils.R")) # get CV-AUC for all algs
source(here("code", "sl_screens.R")) # set up the screen/algorithm combinations
source(here("code", "utils.R")) # get CV-AUC for all algs

############ SETUP INPUT ####################### 
# Read in data file
inputFile <- dat.mock

# Identify the risk demographic variable names that will be used to compute the risk score
risk_vars <- c("MinorityInd", "EthnicityHispanic", "EthnicityNotreported", "EthnicityUnknown", 
               "Black", "Asian", "NatAmer", "PacIsl", "WhiteNonHispanic", "Multiracial", 
               "Other", "Notreported", "Unknown", "HighRiskInd", "Sex", "Age", "BMI")

# Identify the endpoint variable
endpoint <- "EventIndPrimaryD57"
################################################    

# Consider only placebo data for risk score analysis
dat.ph1 <- inputFile %>%
  filter(Perprotocol == 1 & Trt == 0) %>%
  # Keep only variables to be included in risk score analyses
  select(Ptid, Trt, all_of(endpoint), all_of(risk_vars)) %>%  
  # Drop any observation with NA values in Ptid, Trt, or endpoint!
  drop_na(Ptid, Trt, all_of(endpoint))
  
# Derive maxVar: the maximum number of variables that will be allowed by SL screens in the models.  
np <- sum(dat.ph1 %>% select(matches(endpoint)))
maxVar <- max(20, floor(np/20))

# Remove any risk_vars that have fewer than 10 1s 
dat.ph1 <- drop_riskVars_with_fewer_1s(dat.ph1, risk_vars)

# Remove any risk_vars with more than 5% missing values. Impute the missing values for other risk variables using mice package! 
dat.ph1 <- drop_riskVars_with_high_total_missing_values(dat.ph1, risk_vars)

# Update risk_vars
risk_vars <- dat.ph1 %>% select(-Ptid, -Trt, -all_of(endpoint)) %>% colnames()

X_covars2adjust <-  dat.ph1 %>%
  select(all_of(risk_vars))
 
# Save ptids to merge with predictions later
risk_placebo_ptids <- dat.ph1 %>% select(Ptid, all_of(endpoint)) 

# Impute missing values in any variable included in risk_vars using the mice package!
print("Make sure data is clean before conducting imputations!")
X_covars2adjust <- impute_missing_values(X_covars2adjust, risk_vars)

# Scale X_covars2adjust to have mean 0, sd 1 for all vars
for (a in colnames(X_covars2adjust)) {
  X_covars2adjust[[a]] <- scale(X_covars2adjust[[a]],
                                center = mean(X_covars2adjust[[a]], na.rm = T),  
                                scale = sd(X_covars2adjust[[a]], na.rm = T))    
}

X_riskVars <- X_covars2adjust
Y = dat.ph1 %>% pull(endpoint)

# set up outer folds for cv variable importance; do stratified sampling
V_outer <- 5
# set up inner folds based off number of cases 
if(np <= 30){
  V_inner <- length(Y) - 1
} else {
  V_inner <- 5  
}

## ensure reproducibility
set.seed(20210217)
seeds <- round(runif(10, 1000, 10000)) # average over 10 random starts

##solve cores issue
library(RhpcBLASctl)
blas_get_num_procs()
blas_set_num_threads(1)
print(blas_get_num_procs())
stopifnot(blas_get_num_procs()==1)


fits <- parallel::mclapply(seeds, FUN = run_cv_sl_once, 
                           Y = Y, 
                           X_mat = X_riskVars, 
                           family = "binomial",
                           #obsWeights = weights,
                           sl_lib = SL_library,
                           method = "method.CC_nloglik",
                           cvControl = list(V = V_outer, stratifyCV = TRUE),
                           innerCvControl = list(list(V = V_inner)),
                           #all_weights = weights,
			                     #Z = Z_treatmentDAT, 
                           #C = C, 
                           #z_lib = "SL.glm",
                           scale = "identity", # new argument
                           vimp = FALSE,
                           mc.cores = num_cores
)

cvaucs <- list()
cvfits <- list()

for(i in 1:length(seeds)) {
  cvaucs[[i]] = fits[[i]]$cvaucs
  cvfits[[i]] = fits[[i]]$cvfits
}

saveRDS(cvaucs, here("results", "cvsl_riskscore_cvaucs.rds"))
save(cvfits, file = here("results", "cvsl_riskscore_cvfits.rda"))
save(risk_placebo_ptids, file = here("results", "risk_placebo_ptids.rda"))
save(run_demo, run_prod, Y, X_riskVars, weights, inputFile, risk_vars, endpoint, maxVar, file = here("results", "objects_for_running_SL.rda"))

