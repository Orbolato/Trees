#!/usr/bin/env Rscript

# Public entry point for the maintained random-forest analysis with the recovered
# signed-log input transform enabled. All preprocessing, model selection, legacy
# execution, and output handling are delegated to the shared runner.
source(file.path("R", "runner.R"))
run_tree_experiments(model = "rf", log_transform = TRUE)
