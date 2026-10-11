#!/usr/bin/env Rscript
source(file.path("R", "runner.R"))
run_tree_experiments(model = "rf", log_transform = TRUE)
