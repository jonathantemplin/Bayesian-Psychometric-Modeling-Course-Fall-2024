# Package installation ======================================================================
needed_packages = c("ggplot2", "cmdstanr", "HDInterval", "bayesplot", "loo")
for(i in 1:length(needed_packages)){
  haspackage = require(needed_packages[i], character.only = TRUE)
  if(haspackage == FALSE){
    install.packages(needed_packages[i])
  }
  library(needed_packages[i], character.only = TRUE)
}

# Data import ==================================================================
DietData = read.csv(file = "DietData.csv")

# Centering variables ==========================================================
DietData$Height60IN = DietData$HeightIN-60

group2 = rep(0, nrow(DietData))
group2[which(DietData$DietGroup == 2)] = 1

group3 = rep(0, nrow(DietData))
group3[which(DietData$DietGroup == 3)] = 1

heightXgroup2 = DietData$Height60IN*group2
heightXgroup3 = DietData$Height60IN*group3

# our matrix syntax from before, but now with PPMC built in

model06_Syntax = "

data {
  int<lower=0> N;         // number of observations
  int<lower=0> P;         // number of predictors (plus column for intercept)
  matrix[N, P] X;         // model.matrix() from R 
  vector[N] y;            // outcome
  
  vector[P] meanBeta;       // prior mean vector for coefficients
  matrix[P, P] covBeta; // prior covariance matrix for coefficients
  
  real sigmaRate;         // prior rate parameter for residual standard deviation
}


parameters {
  vector[P] beta;         // vector of coefficients for Beta
  real<lower=0> sigma;    // residual standard deviation
}


model {
  beta ~ multi_normal(meanBeta, covBeta); // prior for coefficients
  sigma ~ exponential(sigmaRate);         // prior for sigma
  y ~ normal(X*beta, sigma);              // linear model
}

generated quantities{

  // general quantities used below:
  vector[N] y_pred;
  y_pred = X*beta; // predicted value (conditional mean)

  // posterior predictive model checking
  
  array[N] real y_rep;
  y_rep = normal_rng(y_pred, sigma);
  
  real mean_y = mean(y);
  real sd_y = sd(y);
  real mean_y_rep = mean(to_vector(y_rep));
  real<lower=0> sd_y_rep = sd(to_vector(y_rep));
  int<lower=0, upper=1> mean_gte = (mean_y_rep >= mean_y);
  int<lower=0, upper=1> sd_gte = (sd_y_rep >= sd(y));
  
  // WAIC and LOO for model comparison
  
  array[N] real log_lik;
  for (person in 1:N){
    log_lik[person] = normal_lpdf(y[person] | y_pred[person], sigma);
  }
}

"

# compile stan code into executable
model06_Stan = cmdstan_model(stan_file = write_stan_file(model06_Syntax))


# start with model formula
model06_formula = formula(WeightLB ~ Height60IN + factor(DietGroup) + Height60IN:factor(DietGroup), data = DietData)

temp = lm(model06_formula, data=DietData)
plot(temp)
# grab model matrix
model06_predictorMatrix = model.matrix(model06_formula, data=DietData)

# find details of model matrix
N = nrow(model06_predictorMatrix)
P = ncol(model06_predictorMatrix)

# build matrices of hyper parameters (for priors)
meanBeta = rep(0, P)
covBeta = diag(x = 1000, nrow = P, ncol = P)
sigmaRate = .1

# build Stan data from model matrix
model06_data = list(
  N = N,
  P = P,
  X = model06_predictorMatrix,
  y = DietData$WeightLB,
  meanBeta = meanBeta,
  covBeta = covBeta,
  sigmaRate = sigmaRate
)


model06_Samples = model06_Stan$sample(
  data = model06_data,
  seed = 03102022,
  chains = 4,
  parallel_chains = 4,
  iter_warmup = 1000,
  iter_sampling = 2000
)


# here, we use format = "draws_matrix" to remove the draws from the array format they default to
posteriorSample = model06_Samples$draws(variables = c("beta", "sigma"), format = "draws_matrix")
View(posteriorSample)

sampleIteration = sample(x = 1:nrow(posteriorSample), size = 1, replace = TRUE)
sampleIteration

posteriorSample[sampleIteration, ]

betaVector = matrix(data = posteriorSample[sampleIteration, 1:6], ncol = 1)
betaVector

sigma = posteriorSample[sampleIteration, 7]

conditionalMeans = model06_predictorMatrix %*% betaVector

simData = rnorm(n = N, mean = conditionalMeans, sd = sigma)
hist(simData)

simMean = mean(simData)
simMean

simSD = sd(simData)
simSD

mean(DietData$WeightLB)
sd(DietData$WeightLB)

simMean = rep(NA, nrow(posteriorSample))
simSD = rep(NA, nrow(posteriorSample))
for (iteration in 1:nrow(posteriorSample)){
  betaVector = matrix(data = posteriorSample[iteration, 1:6], ncol = 1)
  sigma = posteriorSample[iteration, 7]
  
  conditionalMeans = model06_predictorMatrix %*% betaVector
  
  simData = rnorm(n = N, mean = conditionalMeans, sd = sigma)
  simMean[iteration] = mean(simData)
  simSD[iteration] = sd(simData)
}

hist(simMean)

# maximum R-hat
max(model06_Samples$summary()$rhat, na.rm = TRUE)

# show results
View(model06_Samples$summary())

# posterior predictive histograms for data points
mcmc_hist(model06_Samples$draws("y_rep[1]")) + geom_vline(xintercept = DietData$WeightLB[1], color = "orange")
mcmc_hist(model06_Samples$draws("y_rep[30]")) + geom_vline(xintercept = DietData$WeightLB[30], color = "orange")

# posterior predictive histograms for statistics of y
mcmc_hist(model06_Samples$draws("mean_y_rep")) + geom_vline(xintercept = mean(DietData$WeightLB), color = "orange")
mcmc_hist(model06_Samples$draws("sd_y_rep")) + geom_vline(xintercept = sd(DietData$WeightLB), color = "orange")

# calculate WAIC for model comparisons
waic(x = model06_Samples$draws("log_lik"))

# calculate LOO for model comparisons
model06_Samples$loo()

# next: try more informative prior distributions =========================================
# build matrices of hyper parameters (for priors)
meanBeta = rep(0, P)
covBeta = diag(x = 1, nrow = P, ncol = P)
sigmaRate = 10

# build Stan data from model matrix
model06b_data = list(
  N = N,
  P = P,
  X = model06_predictorMatrix,
  y = DietData$WeightLB,
  meanBeta = meanBeta,
  covBeta = covBeta,
  sigmaRate = sigmaRate
)


model06b_Samples = model06_Stan$sample(
  data = model06b_data,
  seed = 031020221,
  chains = 4,
  parallel_chains = 4,
  iter_warmup = 1000,
  iter_sampling = 2000
)


# maximum R-hat
max(model06b_Samples$summary()$rhat, na.rm=TRUE)

# show results
View(model06b_Samples$summary())

# calculate WAIC for model comparisons
waic(x = model06_Samples$draws("log_lik"))
waic(x = model06b_Samples$draws("log_lik"))

# calculate LOO for model comparisons
model06b_Samples$loo()

# comparing two models with loo:
loo_compare(list(uniformative=model06_Samples$loo(), informative=model06b_Samples$loo()))

# final comparison: investigating homogeneity of variance assumption

model07_Syntax = "

data {
  int<lower=0> N;         // number of observations
  int<lower=0> P;         // number of predictors (plus column for intercept)
  matrix[N, P] X;         // model.matrix() from R 
  vector[N] y;            // outcome
  
  vector[P] meanBeta;       // prior mean vector for coefficients
  matrix[P, P] covBeta; // prior covariance matrix for coefficients
  
  vector[P] meanGamma;       // prior mean vector for coefficients
  matrix[P, P] covGamma; // prior covariance matrix for coefficients
}


parameters {
  vector[P] beta;         // vector of coefficients for conditional mean
  vector[P] gamma;        // vector of coefficients for residual sd
}


model {
  beta ~ multi_normal(meanBeta, covBeta); // prior for coefficients
  gamma ~ multi_normal(meanGamma, covGamma); // prior for coefficients
  y ~ normal(X*beta, exp(X*gamma));              // linear model
}

generated quantities{

  // general quantities used below:
  vector[N] y_pred;
  vector[N] y_sd;
  y_pred = X*beta; // predicted value (conditional mean)
  y_sd = exp(X*gamma); // conditional standard deviation
  
  // posterior predictive model checking
  
  array[N] real y_rep;
  y_rep = normal_rng(y_pred, y_sd);
  
  real mean_y = mean(y);
  real sd_y = sd(y);
  real mean_y_rep = mean(to_vector(y_rep));
  real<lower=0> sd_y_rep = sd(to_vector(y_rep));
  int<lower=0, upper=1> mean_gte = (mean_y_rep >= mean_y);
  int<lower=0, upper=1> sd_gte = (sd_y_rep >= sd(y));
  
  // WAIC and LOO for model comparison
  
  array[N] real log_lik;
  for (person in 1:N){
    log_lik[person] = normal_lpdf(y[person] | y_pred[person], y_sd[person]);
  }
}

"

# compile stan code into executable
model07_Stan = cmdstan_model(stan_file = write_stan_file(model07_Syntax))


# start with model formula
model07_formula = formula(WeightLB ~ Height60IN + factor(DietGroup) + Height60IN:factor(DietGroup), data = DietData)

# grab model matrix
model07_predictorMatrix = model.matrix(model07_formula, data=DietData)

# find details of model matrix
N = nrow(model07_predictorMatrix)
P = ncol(model07_predictorMatrix)

# build matrices of hyper parameters (for priors)
meanBeta = rep(0, P)
covBeta = diag(x = 1000, nrow = P, ncol = P)
meanGamma = rep(0, P)
covGamma = diag(x = 1000, nrow = P, ncol = P)



# build Stan data from model matrix
model07_data = list(
  N = N,
  P = P,
  X = model06_predictorMatrix,
  y = DietData$WeightLB,
  meanBeta = meanBeta,
  covBeta = covBeta,
  meanGamma = meanGamma,
  covGamma = covGamma
)


model07_Samples = model07_Stan$sample(
  data = model07_data,
  seed = 04102022,
  chains = 4,
  parallel_chains = 4,
  iter_warmup = 2000,
  iter_sampling = 4000
)

# maximum R-hat
max(model07_Samples$summary()$rhat, na.rm = TRUE)

# model results
View(model07_Samples$summary())
model07_Samples$summary(variables = "gamma")

# model comparisons
waic(x = model06_Samples$draws("log_lik"))
waic(x = model07_Samples$draws("log_lik"))

model06_Samples$loo()
model07_Samples$loo()

loo_compare(list(homogeneous = model06_Samples$loo(), heterogeneous = model07_Samples$loo()))

model06_Samples$save_object(file = "model06_samples.RDS")
model07_Samples$save_object(file = "model07_samples.RDS")
save.image(file = "lecture03c.RData")
