parse_cli <- function(args = commandArgs(trailingOnly = TRUE)) {
  value_after <- function(flag, default = NULL) {
    position <- match(flag, args)
    if (is.na(position)) return(default)
    if (position == length(args)) stop(sprintf("%s requires a value.", flag), call. = FALSE)
    args[[position + 1L]]
  }
  as_int <- function(flag, default) {
    value <- suppressWarnings(as.integer(value_after(flag, as.character(default))))
    if (is.na(value)) stop(sprintf("%s must be an integer.", flag), call. = FALSE)
    value
  }
  list(
    help = "--help" %in% args,
    legacy = "--legacy" %in% args,
    workspace = value_after("--workspace", "data.RData"),
    output_dir = value_after("--output-dir", "results"),
    seed = as_int("--seed", 2019L),
    minimum_per_class = as_int("--minimum-per-class", 1000L),
    max_configurations = as_int("--max-configurations", .Machine$integer.max),
    max_folds = as_int("--max-folds", 10L),
    remove_fsb_zero = "--remove-fsb-zero" %in% args,
    quiet = "--quiet" %in% args,
    max_iterations = as_int("--max-iterations", 2000L),
    max_hidden_multiplier = as_int("--max-hidden-multiplier", 2L),
    max_svm_degree = as_int("--max-svm-degree", 6L),
    max_svm_scale = as_int("--max-svm-scale", 6L),
    max_svm_offset = as_int("--max-svm-offset", 6L),
    max_dt_trials = as_int("--max-dt-trials", 100L)
  )
}

print_common_help <- function() {
  cat(paste(
    "Common options:",
    "  --workspace PATH             archived data/fold workspace (default: data.RData)",
    "  --output-dir PATH            output directory (default: results)",
    "  --seed N                     deterministic seed (default: 2019)",
    "  --minimum-per-class N        balancing target floor (default: 1000)",
    "  --max-configurations N       restrict the 10 historical experiment configurations",
    "  --max-folds N                restrict cross-validation folds (default: 10)",
    "  --remove-fsb-zero            remove MSBTn class 0, an option explored historically",
    "  --legacy                     run the exact recovered 2018 source instead",
    "  --quiet                      suppress progress messages",
    sep = "\n"
  ))
}
