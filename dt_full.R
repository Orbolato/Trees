#!/usr/bin/env Rscript

# Public entry point for the maintained C5.0 decision-tree analysis without the
# recovered signed-log transform. The shared runner contains all experiment,
# legacy-mode, reproducibility, and output logic.
source(file.path("R", "runner.R"))
run_tree_experiments(model = "dt", log_transform = FALSE)
