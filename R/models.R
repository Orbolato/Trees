# Decision-tree and random-forest model helpers.

trial_step_for_classes <- function(labels) {
  values <- suppressWarnings(as.numeric(as.character(labels)))
  values <- values[is.finite(values)]
  if (length(values) == 0L) return(max(1L, nlevels(as.factor(labels))))
  max(1L, as.integer(max(values) - min(values) + 1L))
}

fit_random_forest <- function(train, output, features, seed = 2019L, ntree = 500L) {
  .require_namespace("randomForest")
  set.seed(seed)
  randomForest::randomForest(make_formula(output, features), data = train, ntree = as.integer(ntree))
}

fit_c50 <- function(train, output, features, trials, seed = 2019L) {
  .require_namespace("C50")
  set.seed(seed)
  C50::C5.0(make_formula(output, features), data = train, trials = as.integer(trials))
}

validation_score_rf <- function(split, output, features, seed, ntree = 500L) {
  model <- fit_random_forest(split$train, output, features, seed, ntree)
  macro_recall(predict(model, split$validation, type = "class"), split$validation[[output]])
}

validation_score_dt <- function(split, output, features, trials, seed) {
  model <- fit_c50(split$train, output, features, trials, seed)
  macro_recall(predict(model, split$validation, type = "class"), split$validation[[output]])
}

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

  if (balanced_score > unbalanced_score) {
    list(split = balanced, variant = "balanced", validation_score = balanced_score)
  } else {
    list(split = unbalanced, variant = "unbalanced", validation_score = unbalanced_score)
  }
}

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
