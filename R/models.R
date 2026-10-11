# Decision-tree and random-forest model helpers.
#
# These functions isolate model fitting and validation-based model-selection
# decisions from the fold-preparation code. The maintained runner uses explicit
# seeds so repeated cleaned runs are reproducible.

# Reproduce the historical C5.0 boosting-trial increment derived from the span
# of numeric class labels. If labels are not numeric, fall back to the number of
# factor levels so the step remains positive and well-defined.
trial_step_for_classes <- function(labels) {
  values <- suppressWarnings(as.numeric(as.character(labels)))
  values <- values[is.finite(values)]
  if (length(values) == 0L) return(max(1L, nlevels(as.factor(labels))))
  max(1L, as.integer(max(values) - min(values) + 1L))
}

# Fit the historical 500-tree RF model unless a different tree count is supplied
# explicitly for testing or sensitivity analysis.
fit_random_forest <- function(train, output, features, seed = 2019L, ntree = 500L) {
  .require_namespace("randomForest")
  set.seed(seed)
  randomForest::randomForest(make_formula(output, features), data = train, ntree = as.integer(ntree))
}

# Fit one C5.0 model with the requested boosting-trial count.
fit_c50 <- function(train, output, features, trials, seed = 2019L) {
  .require_namespace("C50")
  set.seed(seed)
  C50::C5.0(make_formula(output, features), data = train, trials = as.integer(trials))
}

# Train RF on one prepared split and return macro recall on the validation fold.
validation_score_rf <- function(split, output, features, seed, ntree = 500L) {
  model <- fit_random_forest(split$train, output, features, seed, ntree)
  macro_recall(predict(model, split$validation, type = "class"), split$validation[[output]])
}

# Train C5.0 on one prepared split and return macro recall on validation data.
validation_score_dt <- function(split, output, features, trials, seed) {
  model <- fit_c50(split$train, output, features, trials, seed)
  macro_recall(predict(model, split$validation, type = "class"), split$validation[[output]])
}

# Select between the balanced and unbalanced training variants using validation
# performance only. This keeps the held-out test fold untouched until the final
# evaluation. DT uses the historical pretest trial rule; RF always uses ntree.
choose_tree_training_variant <- function(prepared, model = c("dt", "rf"), output, features,
                                         seed = 2019L, ntree = 500L,
                                         dt_pretest_trials = NULL) {
  model <- match.arg(model)
  unbalanced <- as_classification_frames(prepared$unbalanced, output)
  balanced <- as_classification_frames(prepared$balanced, output)

  if (model == "rf") {
    unbalanced_score <- validation_score_rf(unbalanced, output, features, seed + 1L, ntree)
    balanced_score <- validation_score_rf(balanced, output, features, seed + 2L, ntree)
  } else {
    pretest_trials <- if (is.null(dt_pretest_trials)) {
      trial_step_for_classes(unbalanced$train[[output]])
    } else {
      as.integer(dt_pretest_trials)
    }
    unbalanced_score <- validation_score_dt(unbalanced, output, features, pretest_trials, seed + 1L)
    balanced_score <- validation_score_dt(balanced, output, features, pretest_trials, seed + 2L)
  }

  # Ties intentionally prefer the unbalanced variant, matching the maintained
  # implementation before this documentation pass.
  if (balanced_score > unbalanced_score) {
    list(split = balanced, variant = "balanced", validation_score = balanced_score)
  } else {
    list(split = unbalanced, variant = "unbalanced", validation_score = unbalanced_score)
  }
}

# Increase C5.0 trials by the historical class-span step. Track the best
# validation score and stop after the first decline, subject to the caller's
# trial cap. The final test fold is not used during this tuning process.
tune_c50_trials <- function(train, validation, output, features, seed = 2019L, max_trials = 100L) {
  step <- trial_step_for_classes(train[[output]])
  trials <- step
  best_trials <- trials
  best_score <- -Inf
  previous <- -Inf

  while (trials <= max_trials) {
    score <- validation_score_dt(
      list(train = train, validation = validation),
      output, features, trials, seed + trials
    )
    if (score >= best_score) {
      best_score <- score
      best_trials <- trials
    }
    if (previous > -Inf && score < previous) break
    previous <- score
    trials <- trials + step
  }
  list(trials = best_trials, validation_score = best_score)
}
