#!/usr/bin/env Rscript

# Public entry point for the maintained C5.0 decision-tree analysis with the
# recovered signed-log input transform enabled. Shared execution logic lives in
# R/runner.R so log and non-log variants cannot diverge operationally.
source(file.path("R", "runner.R"))
run_tree_experiments(model = "dt", log_transform = TRUE)
