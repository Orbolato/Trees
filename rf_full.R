#!/usr/bin/env Rscript

# Public entry point for the maintained random-forest analysis without the
# recovered signed-log transform. The shared runner fixes the historical RF size
# at 500 trees for normal runs and handles all fold/output bookkeeping.
source(file.path("R", "runner.R"))
run_tree_experiments(model = "rf", log_transform = FALSE)
