#!/usr/bin/env Rscript
source(file.path("R", "runner.R"))
run_tree_experiments(model = "dt", log_transform = TRUE)
