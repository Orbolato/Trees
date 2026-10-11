# Common execution flow for the cleaned DT/RF analyses and exact legacy mode.
#
# Preprocessing is delegated to R/cpt_core.R and model-specific operations to
# R/models.R. This runner coordinates experiment selection, fold iteration,
# validation-based training-variant selection, final testing, and output writing.

source(file.path("R", "cpt_core.R"))
source(file.path("R", "models.R"))
source(file.path("R", "cli.R"))

# Print model-specific usage while sharing the common option list.
trees_help <- function(model, log_transform) {
  label <- if (model == "dt") "C5.0 decision-tree" else "random-forest"
  cat(sprintf("Run the cleaned %s%s CPT soil-classification experiments.\n\n", label, if (log_transform) " log-scaled" else ""))
  cat(sprintf("Usage: Rscript %s_full%s.R [options]\n\n", model, if (log_transform) "_log" else ""))
  print_common_help()
  if (model == "dt") cat("\nDT option:\n  --max-dt-trials N            C5.0 boosting-trial cap (default: 100)\n")
}

# Map a maintained model/log choice to the exact recovered submission script.
legacy_tree_script_path <- function(model, log_transform) {
  directory <- if (model == "dt") "DT" else "RF"
  filename <- sprintf("%s_full%s.R", model, if (log_transform) "_log" else "")
  file.path(directory, "For submission", filename)
}

# Execute the preserved 2018 script exactly as recovered. Unlike the cleaned
# runner, legacy mode intentionally keeps historical time-dependent reseeding and
# other implementation details. Execution occurs in a dedicated environment.
run_legacy_trees <- function(model, log_transform, options) {
  archive <- file.path("legacy", "2018", "Trees_recovered_source.tar.xz")
  if (!file.exists(archive)) stop("Recovered source archive is missing.", call. = FALSE)
  if (!file.exists(options$workspace)) stop(sprintf("Workspace not found: %s", options$workspace), call. = FALSE)

  # Unpack to a temporary directory so the preservation archive remains the
  # single source of truth for historical code.
  source_dir <- tempfile("trees-legacy-")
  dir.create(source_dir)
  utils::untar(archive, exdir = source_dir)
  script <- file.path(source_dir, legacy_tree_script_path(model, log_transform))
  if (!file.exists(script)) stop(sprintf("Recovered script missing: %s", script), call. = FALSE)

  env <- new.env(parent = globalenv())
  load(options$workspace, envir = env)
  sys.source(script, envir = env)

  # Save the complete historical analysis environment for auditing rather than
  # translating its objects into the cleaned result-table format.
  dir.create(options$output_dir, recursive = TRUE, showWarnings = FALSE)
  output <- file.path(options$output_dir, sprintf("legacy_%s_full%s.RData", model, if (log_transform) "_log" else ""))
  save(list = ls(env, all.names = TRUE), envir = env, file = output)
  message(sprintf("Saved legacy analysis environment to %s", output))
  invisible(output)
}

# Run the maintained DT or RF experiment grid. The cleaned path uses the archived
# folds by default, deterministic seeds, validation-only model selection, and a
# final held-out test evaluation for each experiment/fold combination.
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

  # Each experiment chooses the complete or geological dataset explicitly. The
  # archived validation-fold mapping is shared across all model families.
  for (config_index in seq_along(experiments)) {
    experiment <- experiments[[config_index]]
    data <- workspace[[experiment$data]]
    folds <- if (experiment$data == "complete") workspace$folds_complete else workspace$folds_geology
    if (!options$quiet) message(sprintf("%s: %s", toupper(model), experiment$id))

    for (fold_index in seq_len(max_folds)) {
      # prepare_fold() performs the historical two-stage scaling, editing, and
      # balancing sequence using only training-derived transformation parameters.
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

      # Use a configuration/fold-specific seed so model stochasticity is stable
      # across reruns without coupling one fold's random stream to another.
      fold_seed <- options$seed + 100000L * config_index + fold_index

      # The recovered DT scripts use one trial for the balanced/unbalanced
      # pretest only in the reduced Qtn+Fr_p+U2 -> MSBTn configuration; all
      # other DT configurations use the class-span trial step. RF is unchanged.
      dt_pretest_trials <- if (model == "dt" && identical(experiment$id, "reduced_fsb")) 1L else NULL
      selected <- choose_tree_training_variant(
        prepared, model, experiment$output, experiment$features,
        seed = fold_seed, ntree = 500L,
        dt_pretest_trials = dt_pretest_trials
      )
      split <- selected$split

      # After the training variant is selected on validation data, fit the final
      # fold model and evaluate it exactly once on the held-out test split.
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

      # Keep fold-level selection/tuning diagnostics so aggregate results remain
      # auditable rather than retaining only a final mean score.
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

  # Summarize each historical experiment across the folds actually requested.
  # Smoke-test limits therefore produce summaries over the limited fold count.
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

  # Write a detailed CSV, a compact summary CSV, and an RDS bundle containing
  # options plus both tables for downstream reproducibility/auditing.
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
