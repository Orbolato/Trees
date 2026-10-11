source(file.path("R", "cpt_core.R"))
source(file.path("R", "models.R"))
source(file.path("R", "cli.R"))

trees_help <- function(model, log_transform) {
  label <- if (model == "dt") "C5.0 decision-tree" else "random-forest"
  cat(sprintf("Run the cleaned %s%s CPT soil-classification experiments.\n\n", label, if (log_transform) " log-scaled" else ""))
  cat(sprintf("Usage: Rscript %s_full%s.R [options]\n\n", model, if (log_transform) "_log" else ""))
  print_common_help()
  if (model == "dt") cat("\nDT option:\n  --max-dt-trials N            C5.0 boosting-trial cap (default: 100)\n")
}

legacy_tree_script_path <- function(model, log_transform) {
  directory <- if (model == "dt") "DT" else "RF"
  filename <- sprintf("%s_full%s.R", model, if (log_transform) "_log" else "")
  file.path(directory, "For submission", filename)
}

run_legacy_trees <- function(model, log_transform, options) {
  archive <- file.path("legacy", "2018", "Trees_recovered_source.tar.xz")
  if (!file.exists(archive)) stop("Recovered source archive is missing.", call. = FALSE)
  if (!file.exists(options$workspace)) stop(sprintf("Workspace not found: %s", options$workspace), call. = FALSE)
  source_dir <- tempfile("trees-legacy-")
  dir.create(source_dir)
  utils::untar(archive, exdir = source_dir)
  script <- file.path(source_dir, legacy_tree_script_path(model, log_transform))
  if (!file.exists(script)) stop(sprintf("Recovered script missing: %s", script), call. = FALSE)
  env <- new.env(parent = globalenv())
  load(options$workspace, envir = env)
  sys.source(script, envir = env)
  dir.create(options$output_dir, recursive = TRUE, showWarnings = FALSE)
  output <- file.path(options$output_dir, sprintf("legacy_%s_full%s.RData", model, if (log_transform) "_log" else ""))
  save(list = ls(env, all.names = TRUE), envir = env, file = output)
  message(sprintf("Saved legacy analysis environment to %s", output))
  invisible(output)
}

run_tree_experiments <- function(model = c("dt", "rf"), log_transform = FALSE, options = parse_cli()) {
  model <- match.arg(model)
  if (options$help) {
    trees_help(model, log_transform)
    return(invisible(NULL))
  }
  if (options$legacy) return(run_legacy_trees(model, log_transform, options))

  workspace <- load_archived_workspace(options$workspace)
  experiments <- select_experiments(options$max_configurations)
  max_folds <- min(10L, max(1L, options$max_folds))
  rows <- list()
  row_index <- 0L

  for (config_index in seq_along(experiments)) {
    experiment <- experiments[[config_index]]
    data <- workspace[[experiment$data]]
    folds <- if (experiment$data == "complete") workspace$folds_complete else workspace$folds_geology
    if (!options$quiet) message(sprintf("%s: %s", toupper(model), experiment$id))

    for (fold_index in seq_len(max_folds)) {
      prepared <- prepare_fold(
        data = data,
        folds = folds,
        validation_folds = workspace$validation_folds,
        fold_index = fold_index,
        output = experiment$output,
        features = experiment$features,
        log_transform = log_transform,
        remove_fsb_zero = options$remove_fsb_zero,
        minimum_per_class = options$minimum_per_class,
        seed = options$seed + 1000L * config_index
      )
      fold_seed <- options$seed + 100000L * config_index + fold_index
      selected <- choose_tree_training_variant(
        prepared, model, experiment$output, experiment$features,
        seed = fold_seed, ntree = 500L
      )
      split <- selected$split

      if (model == "rf") {
        fit <- fit_random_forest(split$train, experiment$output, experiment$features, fold_seed + 50000L, ntree = 500L)
        predictions <- predict(fit, split$test, type = "class")
        tuning_validation <- selected$validation_score
        parameters <- "ntree=500"
      } else {
        tuning <- tune_c50_trials(
          split$train, split$validation,
          experiment$output, experiment$features,
          seed = fold_seed,
          max_trials = options$max_dt_trials
        )
        fit <- fit_c50(
          split$train, experiment$output, experiment$features,
          trials = tuning$trials, seed = fold_seed + 50000L
        )
        predictions <- predict(fit, split$test, type = "class")
        tuning_validation <- tuning$validation_score
        parameters <- sprintf("trials=%d", tuning$trials)
      }

      test_score <- macro_recall(predictions, split$test[[experiment$output]])
      row_index <- row_index + 1L
      rows[[row_index]] <- data.frame(
        model = toupper(model),
        log_transform = log_transform,
        experiment = experiment$id,
        output = experiment$output,
        features = paste(experiment$features, collapse = "+"),
        fold = fold_index,
        training_variant = selected$variant,
        selection_validation_macro_recall = selected$validation_score,
        tuning_validation_macro_recall = tuning_validation,
        test_macro_recall = test_score,
        parameters = parameters,
        stringsAsFactors = FALSE
      )
      if (!options$quiet) message(sprintf("  fold %d: %s, test macro recall %.4f", fold_index, selected$variant, test_score))
    }
  }

  results <- do.call(rbind, rows)
  summary_rows <- do.call(rbind, lapply(base::split(results, results$experiment), function(group) {
    data.frame(
      experiment = group$experiment[[1L]],
      output = group$output[[1L]],
      features = group$features[[1L]],
      mean_macro_recall = mean(group$test_macro_recall),
      sd_macro_recall = if (nrow(group) > 1L) stats::sd(group$test_macro_recall) else NA_real_,
      balanced_folds = sum(group$training_variant == "balanced"),
      unbalanced_folds = sum(group$training_variant == "unbalanced"),
      folds = nrow(group),
      stringsAsFactors = FALSE
    )
  }))
  rownames(summary_rows) <- NULL

  dir.create(options$output_dir, recursive = TRUE, showWarnings = FALSE)
  stem <- sprintf("%s_full%s", model, if (log_transform) "_log" else "")
  utils::write.csv(results, file.path(options$output_dir, paste0(stem, "_folds.csv")), row.names = FALSE)
  utils::write.csv(summary_rows, file.path(options$output_dir, paste0(stem, "_summary.csv")), row.names = FALSE)
  saveRDS(
    list(model = model, log_transform = log_transform, options = options, fold_results = results, summary = summary_rows),
    file.path(options$output_dir, paste0(stem, ".rds"))
  )
  invisible(list(fold_results = results, summary = summary_rows))
}
