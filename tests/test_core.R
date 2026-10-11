#!/usr/bin/env Rscript
source(file.path("R", "cpt_core.R"))
source(file.path("R", "models.R"))
source(file.path("R", "cli.R"))

assert_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
assert_equal <- function(a, b, message, tolerance = 1e-10) {
  if (!isTRUE(all.equal(a, b, tolerance = tolerance, check.attributes = FALSE))) stop(message, call. = FALSE)
}

public_scripts <- c(
  "dt_full.R", "dt_full_log.R", "rf_full.R", "rf_full_log.R",
  "generate_data.R", file.path("R", "runner.R")
)
for (file in public_scripts) parse(file = file)

archive <- file.path("legacy", "2018", "Trees_recovered_source.tar.xz")
assert_true(file.exists(archive), "Recovered Trees source archive is missing")
source_dir <- tempfile("trees-source-")
dir.create(source_dir)
utils::untar(archive, exdir = source_dir)
legacy_scripts <- c(
  file.path("DT", "For submission", "dt_full.R"),
  file.path("DT", "For submission", "dt_full_log.R"),
  file.path("DT", "For submission", "generate_data.R"),
  file.path("RF", "For submission", "rf_full.R"),
  file.path("RF", "For submission", "rf_full_log.R"),
  file.path("RF", "For submission", "generate_data.R")
)
for (file in legacy_scripts) parse(file = file.path(source_dir, file))

assert_true(length(paper_experiments()) == 10L, "Historical experiment grid must contain 10 configurations")
assert_equal(signed_log_transform(c(0, 1)), c(0, 1), "Signed-log transform regression failed")
assert_equal(
  macro_recall(c(1, 1, 2, 2), c(1, 2, 2, 2)),
  (1 + 2 / 3) / 2,
  "Macro-recall regression failed"
)
assert_true(trial_step_for_classes(factor(c(1, 2, 3))) == 3L, "C5.0 trial-step regression failed")

validation <- make_validation_fold_map(10L, 2019L)
assert_true(length(unique(validation)) == 10L, "Validation folds must be unique")
assert_true(all(validation != seq_len(10L)), "Validation fold cannot equal its test fold")

sample_data <- data.frame(
  x = c(1, 2, 3, 10, 11, 12),
  y = c(2, 3, 4, 20, 21, 22),
  class = c(1, 1, 1, 2, 2, 2)
)
balanced <- balance_training_data(sample_data, "class", c("x", "y"), seed = 7L, minimum_per_class = 3L)
assert_true(length(unique(table(balanced$class))) == 1L, "Balancing regression failed")

historical_artifacts <- c(
  "complete.csv", "geology.csv", "data.RData",
  "results_dt_full.RData", "results_rf_full.RData"
)
for (file in historical_artifacts) assert_true(file.exists(file), sprintf("Historical artifact missing: %s", file))
workspace <- load_archived_workspace("data.RData")
assert_true(nrow(workspace$complete) == 9360L, "Unexpected complete dataset row count")
assert_true(nrow(workspace$geology) == 1721L, "Unexpected geological dataset row count")
assert_true(length(workspace$folds_complete) == 10L, "Expected 10 complete-data folds")
assert_true(length(workspace$folds_geology) == 10L, "Expected 10 geology folds")

# Current-package model smoke checks use a tiny synthetic dataset so they verify
# C50/randomForest API compatibility without running the historical experiment.
toy <- data.frame(
  x1 = c(0.00, 0.05, 0.10, 0.15, 0.20, 0.25, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00),
  x2 = c(0.05, 0.00, 0.15, 0.10, 0.25, 0.20, 0.80, 0.75, 0.90, 0.85, 1.00, 0.95),
  class = factor(rep(c("A", "B"), each = 6L))
)
dt_fit <- fit_c50(toy, "class", c("x1", "x2"), trials = 2L, seed = 11L)
dt_pred <- predict(dt_fit, toy, type = "class")
assert_true(length(dt_pred) == nrow(toy), "C5.0 current-package smoke test failed")

rf_fit <- fit_random_forest(toy, "class", c("x1", "x2"), seed = 12L, ntree = 20L)
rf_pred <- predict(rf_fit, toy, type = "class")
assert_true(length(rf_pred) == nrow(toy), "Random-forest current-package smoke test failed")

cat("All Trees core, provenance, and model smoke tests passed.\n")
