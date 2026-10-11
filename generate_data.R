#!/usr/bin/env Rscript

# Deterministic workspace generator for maintained DT/RF reruns. It recreates
# the object names expected by both the cleaned runner and the preserved 2018
# scripts while using explicit seeds for every newly generated fold assignment.

source(file.path("R", "cpt_core.R"))
args <- commandArgs(trailingOnly = TRUE)

# Return the token following one named command-line option.
value_after <- function(flag, default) {
  position <- match(flag, args)
  if (is.na(position)) return(default)
  if (position == length(args)) stop(sprintf("%s requires a value.", flag), call. = FALSE)
  args[[position + 1L]]
}

if ("--help" %in% args) {
  cat("Usage: Rscript generate_data.R [--complete complete.csv] [--geology geology.csv] [--output data.RData] [--seed 2019]\n")
  quit(status = 0L)
}

.require_namespace("caret")
complete_path <- value_after("--complete", "complete.csv")
geology_path <- value_after("--geology", "geology.csv")
output_path <- value_after("--output", "data.RData")
seed <- suppressWarnings(as.integer(value_after("--seed", "2019")))
if (is.na(seed)) stop("--seed must be an integer.", call. = FALSE)

# Preserve the historical stratification targets: SBTn for the complete dataset
# and MSBTn for the geological subset. Independent seeds keep both partitions
# reproducible without coupling their random streams.
data <- load_cpt_csvs(complete_path, geology_path)
dataNet <- data$complete
dataGeo <- data$geology
set.seed(seed)
foldsNet <- caret::createFolds(dataNet$SBTn, k = 10L, list = TRUE, returnTrain = FALSE)
set.seed(seed + 1L)
foldsGeo <- caret::createFolds(dataGeo$MSBTn, k = 10L, list = TRUE, returnTrain = FALSE)
validFolds <- make_validation_fold_map(10L, seed + 2L)

# A regenerated workspace is a new deterministic partition. The archived
# data.RData remains the preferred input when preservation of historical folds
# matters for comparison with the original repository outputs.
save(dataNet, dataGeo, foldsNet, foldsGeo, validFolds, file = output_path)
message(sprintf("Saved reproducible workspace to %s", output_path))
