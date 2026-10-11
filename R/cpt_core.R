# Shared CPT preprocessing and evaluation helpers for the 2018/2019 soil-classification studies.

.require_namespace <- function(package) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop(sprintf("Package '%s' is required for this operation.", package), call. = FALSE)
  }
}

validate_columns <- function(data, columns, data_name = "data") {
  missing <- setdiff(columns, names(data))
  if (length(missing) > 0L) {
    stop(sprintf("%s is missing required column(s): %s", data_name, paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

load_archived_workspace <- function(path = "data.RData") {
  if (!file.exists(path)) stop(sprintf("Archived workspace not found: %s", path), call. = FALSE)
  env <- new.env(parent = baseenv())
  loaded <- load(path, envir = env)
  required <- c("dataNet", "dataGeo", "foldsNet", "foldsGeo", "validFolds")
  missing <- setdiff(required, loaded)
  if (length(missing) > 0L) {
    stop(sprintf("Workspace is missing required object(s): %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  list(
    complete = env$dataNet,
    geology = env$dataGeo,
    folds_complete = env$foldsNet,
    folds_geology = env$foldsGeo,
    validation_folds = as.integer(env$validFolds)
  )
}

load_cpt_csvs <- function(complete_path = "complete.csv", geology_path = "geology.csv") {
  if (!file.exists(complete_path)) stop(sprintf("Complete CSV not found: %s", complete_path), call. = FALSE)
  if (!file.exists(geology_path)) stop(sprintf("Geology CSV not found: %s", geology_path), call. = FALSE)
  list(
    complete = utils::read.csv(complete_path, check.names = FALSE),
    geology = utils::read.csv(geology_path, check.names = FALSE)
  )
}

make_validation_fold_map <- function(k = 10L, seed = 2019L) {
  if (k < 2L) stop("k must be at least 2.", call. = FALSE)
  set.seed(seed)
  test_folds <- seq_len(k)
  repeat {
    validation <- sample(test_folds, k, replace = FALSE)
    if (all(validation != test_folds)) return(validation)
  }
}

paper_experiments <- function() {
  list(
    list(id = "raw_isg", data = "complete", output = "SBTn", features = c("Depth_m", "qt_MPa", "fs_kPa", "u_kPa")),
    list(id = "raw_fsb", data = "complete", output = "MSBTn", features = c("Depth_m", "qt_MPa", "fs_kPa", "u_kPa")),
    list(id = "qt1_isg", data = "complete", output = "SBTn", features = c("Depth_m", "Qt1", "Fr_p", "Bq")),
    list(id = "qt1_fsb", data = "complete", output = "MSBTn", features = c("Depth_m", "Qt1", "Fr_p", "Bq")),
    list(id = "qtn_isg", data = "complete", output = "SBTn", features = c("Depth_m", "Qtn", "Fr_p", "U2")),
    list(id = "qtn_fsb", data = "complete", output = "MSBTn", features = c("Depth_m", "Qtn", "Fr_p", "U2")),
    list(id = "geology_raw_fsb", data = "geology", output = "MSBTn", features = c("CG", "Depth_m", "qt_MPa", "fs_kPa", "u_kPa")),
    list(id = "geology_qtn_fsb", data = "geology", output = "MSBTn", features = c("CG", "Depth_m", "Qtn", "Fr_p", "U2")),
    list(id = "reduced_isg", data = "complete", output = "SBTn", features = c("Qtn", "Fr_p")),
    list(id = "reduced_fsb", data = "complete", output = "MSBTn", features = c("Qtn", "Fr_p", "U2"))
  )
}

fit_minmax <- function(data, features) {
  validate_columns(data, features)
  mins <- vapply(data[features], min, numeric(1), na.rm = TRUE)
  maxs <- vapply(data[features], max, numeric(1), na.rm = TRUE)
  spans <- maxs - mins
  if (any(!is.finite(mins)) || any(!is.finite(maxs))) stop("Non-finite values found while fitting scaling.", call. = FALSE)
  if (any(spans == 0)) stop(sprintf("Cannot scale constant feature(s): %s", paste(names(spans)[spans == 0], collapse = ", ")), call. = FALSE)
  list(min = mins, max = maxs)
}

apply_minmax <- function(data, scaler, features) {
  result <- data
  for (feature in features) {
    result[[feature]] <- (result[[feature]] - scaler$min[[feature]]) / (scaler$max[[feature]] - scaler$min[[feature]])
  }
  result
}

signed_log_transform <- function(x) {
  # Transform used consistently by the recovered SVM/DT/RF log scripts and by
  # the later MMP implementation. It maps 0 -> 0 and 1 -> 1.
  sign(x) * log10(1 + 99 * abs(x)) / 2
}

apply_signed_log <- function(data, features) {
  result <- data
  for (feature in features) result[[feature]] <- signed_log_transform(result[[feature]])
  result
}

scale_split <- function(train, validation, test, features, log_transform = FALSE) {
  scaler <- fit_minmax(train, features)
  train <- apply_minmax(train, scaler, features)
  validation <- apply_minmax(validation, scaler, features)
  test <- apply_minmax(test, scaler, features)
  if (log_transform) {
    train <- apply_signed_log(train, features)
    validation <- apply_signed_log(validation, features)
    test <- apply_signed_log(test, features)
  }
  list(train = train, validation = validation, test = test, scaler = scaler)
}

macro_recall <- function(predicted, observed) {
  predicted <- as.character(predicted)
  observed <- as.character(observed)
  observed_classes <- sort(unique(observed[!is.na(observed)]))
  all_classes <- sort(unique(c(predicted, observed)))
  all_classes <- all_classes[!is.na(all_classes)]
  confusion <- table(factor(predicted, levels = all_classes), factor(observed, levels = all_classes))
  recalls <- vapply(observed_classes, function(class_value) {
    denominator <- sum(confusion[, class_value])
    if (denominator == 0L) return(NA_real_)
    confusion[class_value, class_value] / denominator
  }, numeric(1))
  mean(recalls, na.rm = TRUE)
}

remove_unclassified <- function(data, output, remove_fsb_zero = FALSE) {
  if (identical(output, "SBTn") || (identical(output, "MSBTn") && remove_fsb_zero)) {
    data <- data[data[[output]] != 0, , drop = FALSE]
  }
  data
}

find_iqr_candidates <- function(train, output, features, multiplier = 1.5) {
  screening_features <- setdiff(features, "Depth_m")
  if (length(screening_features) == 0L) return(integer())
  candidates <- logical(nrow(train))
  for (class_value in sort(unique(train[[output]]))) {
    rows <- which(train[[output]] == class_value)
    for (feature in screening_features) {
      values <- train[rows, feature]
      q <- stats::quantile(values, probs = c(0.25, 0.75), na.rm = TRUE, names = FALSE, type = 7)
      iqr <- q[[2L]] - q[[1L]]
      lower <- q[[1L]] - multiplier * iqr
      upper <- q[[2L]] + multiplier * iqr
      candidates[rows] <- candidates[rows] | values < lower | values > upper
    }
  }
  which(candidates)
}

make_formula <- function(output, features) stats::reformulate(features, response = output)

edit_nearest_neighbor <- function(train, output, features, candidate_rows = NULL) {
  .require_namespace("kknn")
  if (is.null(candidate_rows)) candidate_rows <- find_iqr_candidates(train, output, features)
  if (length(candidate_rows) == 0L) return(train)
  work <- train
  work$.row_id <- seq_len(nrow(work))
  candidate_ids <- work$.row_id[candidate_rows]
  formula <- make_formula(output, features)
  for (candidate_id in candidate_ids) {
    current <- which(work$.row_id == candidate_id)
    if (length(current) != 1L || nrow(work) <= 1L) next
    candidate <- work[current, setdiff(names(work), ".row_id"), drop = FALSE]
    reference <- work[-current, setdiff(names(work), ".row_id"), drop = FALSE]
    levels_all <- sort(unique(as.character(reference[[output]])))
    reference[[output]] <- factor(reference[[output]], levels = levels_all)
    candidate[[output]] <- factor(candidate[[output]], levels = levels_all)
    prediction <- kknn::kknn(
      formula = formula, train = reference, test = candidate,
      k = 1, distance = 2, kernel = "rectangular", scale = FALSE
    )$fitted.values
    if (as.character(prediction[[1L]]) != as.character(candidate[[output]][[1L]])) work <- work[-current, , drop = FALSE]
  }
  work$.row_id <- NULL
  work
}

balance_training_data <- function(train, output, features, seed = 2019L, minimum_per_class = 1000L) {
  validate_columns(train, c(features, output), "training data")
  classes <- sort(unique(train[[output]]))
  counts <- vapply(classes, function(value) sum(train[[output]] == value), integer(1))
  target <- max(as.integer(minimum_per_class), 2L * min(counts))
  set.seed(seed)
  result <- train
  for (class_value in classes) {
    class_rows <- result[result[[output]] == class_value, , drop = FALSE]
    n_class <- nrow(class_rows)
    if (n_class > target) {
      keep <- sample(seq_len(n_class), target)
      result <- rbind(result[result[[output]] != class_value, , drop = FALSE], class_rows[keep, , drop = FALSE])
    } else if (n_class < target) {
      d_plus_one <- length(features) + 1L
      if (n_class < d_plus_one) stop(sprintf("Class %s has %d rows; at least %d are required.", class_value, n_class, d_plus_one), call. = FALSE)
      synthetic <- vector("list", target - n_class)
      for (index in seq_along(synthetic)) {
        sampled <- sample(seq_len(n_class), d_plus_one)
        row <- class_rows[1L, , drop = FALSE]
        for (feature in features) row[[feature]] <- mean(class_rows[sampled, feature])
        row[[output]] <- class_value
        synthetic[[index]] <- row
      }
      result <- rbind(result, do.call(rbind, synthetic))
    }
  }
  rownames(result) <- NULL
  result
}

prepare_fold <- function(data, folds, validation_folds, fold_index, output, features,
                         log_transform = FALSE, remove_fsb_zero = FALSE,
                         minimum_per_class = 1000L, seed = 2019L) {
  validate_columns(data, c(features, output))
  test_rows <- folds[[fold_index]]
  validation_rows <- folds[[validation_folds[[fold_index]]]]
  training_rows <- setdiff(seq_len(nrow(data)), c(test_rows, validation_rows))
  train <- data[training_rows, c(features, output), drop = FALSE]
  validation <- data[validation_rows, c(features, output), drop = FALSE]
  test <- data[test_rows, c(features, output), drop = FALSE]
  train <- remove_unclassified(train, output, remove_fsb_zero)
  validation <- remove_unclassified(validation, output, remove_fsb_zero)
  test <- remove_unclassified(test, output, remove_fsb_zero)

  # Historical preprocessing first scales (and, for *_log scripts, log-scales)
  # the raw split, then edits and balances the transformed training set.
  transformed <- scale_split(train, validation, test, features, log_transform = log_transform)
  clean_train <- edit_nearest_neighbor(transformed$train, output, features)
  balanced_train <- balance_training_data(
    clean_train, output, features,
    seed = seed + fold_index, minimum_per_class = minimum_per_class
  )

  # The recovered scripts then rescale balanced and unbalanced variants before
  # model fitting. The second stage is min-max only, including in *_log scripts.
  unbalanced <- scale_split(clean_train, transformed$validation, transformed$test, features, log_transform = FALSE)
  balanced <- scale_split(balanced_train, transformed$validation, transformed$test, features, log_transform = FALSE)
  list(unbalanced = unbalanced, balanced = balanced)
}

as_classification_frames <- function(split, output) {
  class_levels <- sort(unique(c(
    as.character(split$train[[output]]),
    as.character(split$validation[[output]]),
    as.character(split$test[[output]])
  )))
  class_levels <- class_levels[!is.na(class_levels)]
  result <- split
  result$train[[output]] <- factor(result$train[[output]], levels = class_levels)
  result$validation[[output]] <- factor(result$validation[[output]], levels = class_levels)
  result$test[[output]] <- factor(result$test[[output]], levels = class_levels)
  result
}

select_experiments <- function(max_configurations = Inf) {
  experiments <- paper_experiments()
  if (is.finite(max_configurations)) experiments <- head(experiments, as.integer(max_configurations))
  experiments
}
