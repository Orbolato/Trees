# Decision Trees and Random Forests for CPT Soil Classification

This repository preserves and refactors the 2018 decision-tree (DT) and random-forest (RF) code developed for soil classification from cone penetration test (CPT) data.

The historical README described the work as **“Soil classification from cone penetration test data using symbolic machine learning techniques up to five-dimensional feature spaces.”** The recovered source predates the final 2021 article in which the DT and RF techniques were incorporated into a broader five-model comparison and ensemble:

**Lucas O. Carvalho and Dimas B. Ribeiro, “A multiple model machine learning approach for soil classification from cone penetration test data,” *Soils and Rocks*, 44(4), e2021072121, 2021.**

DOI: https://doi.org/10.28927/SR.2021.072121

This repository should therefore be read as a **historical predecessor implementation plus a cleaned rerun framework**, not as a claim that the 2018 scripts are the byte-for-byte final 2021 analysis code.

## Recovery status

The original repository already contained `dt_full.R`, `rf_full.R`, `generate_data.R`, the two historical CSV datasets, `data.RData`, and saved DT/RF result workspaces. Comparison against the recovered `RF.zip` confirms that all of those artifacts are byte-for-byte identical to the 2018 `For submission` copies.

The recovered ZIP additionally supplied:

- the previously missing `dt_full_log.R` and `rf_full_log.R` variants;
- earlier DT/RF development scripts (`*_biased`, `*_cg`, `*_conf`, and log variants);
- an independent provenance source for the historical submission snapshot.

Those exact sources are preserved in `legacy/2018/Trees_recovered_source.tar.xz`.

## Historical experiment design

The full scripts evaluate **10 configurations**:

- three four-variable feature families on the complete dataset, each for `SBTn` and `MSBTn` (6 configurations);
- two five-variable configurations that add geological age `CG`, both for `MSBTn` (2 configurations);
- reduced `Qtn + Fr_p` and `Qtn + Fr_p + U2` configurations (2 configurations).

Each test fold uses a distinct validation fold. Historical preprocessing includes training-based min-max scaling, optional logarithmic scaling, class-wise IQR screening, a 1-NN edited-neighbor check, class balancing, and a second min-max scaling stage before model fitting.

The class-balancing rule undersamples larger classes and creates minority examples from the feature-wise mean of `d + 1` randomly selected same-class rows. This is the same historical rule later observed in the recovered MMP source.

## Model behavior

### Decision tree

The DT implementation uses `C50::C5.0`. For each fold it:

- compares balanced and unbalanced training variants on the **validation** fold;
- selects the better variant;
- increases the number of boosting trials in increments derived from the class-number span until validation performance stops improving or the trial cap is reached;
- evaluates the selected/tuned model on the held-out test fold.

### Random forest

The RF implementation uses `randomForest` with **500 trees**. It compares balanced and unbalanced training variants on the validation fold and evaluates the selected variant on the test fold.

Performance is summarized with mean class recall (macro recall), matching the historical scripts' calculation even where comments call the quantity “mean precision.”

## Cleanup decisions

The cleaned default preserves the methodology while addressing reproducibility and maintainability:

- repeated system-time random seeds are replaced by one explicit deterministic `--seed`;
- preprocessing is centralized in `R/cpt_core.R`;
- DT/RF model logic is centralized in `R/models.R`;
- the archived `data.RData` is used by default so the original folds remain available;
- log variants consistently use the recovered signed base-10 transform;
- result tables are written to `results/` as CSV and RDS files;
- exact historical behavior remains available through `--legacy` and the preservation archive.

Because deterministic balancing changes the synthetic-sampling sequence, newly generated cleaned results should be treated as **paper-oriented reproducible reruns**, not assumed to match the historical `.RData` workspaces bit-for-bit.

## Repository structure

```text
.
├── R/
│   ├── cpt_core.R              # data, folds, preprocessing, balancing, metrics
│   ├── models.R                # C5.0 and random-forest helpers
│   ├── cli.R                   # command-line options
│   └── runner.R                # common experiment runner + legacy execution
├── dt_full.R
├── dt_full_log.R
├── rf_full.R
├── rf_full_log.R
├── generate_data.R
├── complete.csv                # unchanged historical dataset
├── geology.csv                 # unchanged historical geological subset
├── data.RData                  # unchanged historical data/fold workspace
├── results_dt_full.RData       # unchanged historical DT result workspace
├── results_rf_full.RData       # unchanged historical RF result workspace
├── legacy/2018/                # exact recovered source + provenance
├── tests/test_core.R
└── .github/workflows/tests.yml
```

## Requirements

```r
install.packages(c("kknn", "C50", "randomForest"))
```

Regenerating the workspace also requires `caret`.

## Run the cleaned analyses

```bash
Rscript dt_full.R
Rscript dt_full_log.R
Rscript rf_full.R
Rscript rf_full_log.R
```

For short checks:

```bash
Rscript dt_full.R --max-configurations 1 --max-folds 1 --minimum-per-class 50 --max-dt-trials 20
Rscript rf_full.R --max-configurations 1 --max-folds 1 --minimum-per-class 50
```

Common options include `--seed`, `--minimum-per-class`, `--max-configurations`, `--max-folds`, `--remove-fsb-zero`, `--output-dir`, and `--quiet`. Run an entry point with `--help` for details.

## Exact historical mode

```bash
Rscript dt_full.R --legacy
Rscript dt_full_log.R --legacy
Rscript rf_full.R --legacy
Rscript rf_full_log.R --legacy
```

Legacy mode executes the recovered submission script directly and intentionally preserves time-dependent random seeding and other historical implementation details.

## Historical data and outputs

The cleanup leaves these existing binary/data artifacts untouched:

- `complete.csv`
- `geology.csv`
- `data.RData`
- `results_dt_full.RData`
- `results_rf_full.RData`

Their byte-level agreement with the recovered archive was verified before refactoring the public entry points.

## Tests

```bash
Rscript tests/test_core.R
```

Tests cover the experiment grid, transforms, macro recall, class balancing, C5.0 trial-step logic, archived workspace structure, cleaned-script parsing, and key recovered-source parsing. GitHub Actions runs the same checks automatically.

## Citation

For the published study incorporating these techniques, cite:

```text
Carvalho, L. O., & Ribeiro, D. B. (2021).
A multiple model machine learning approach for soil classification from
cone penetration test data. Soils and Rocks, 44(4), e2021072121.
https://doi.org/10.28927/SR.2021.072121
```

## License

No separate software license has been assigned to this repository. The presence of source code on GitHub should not be interpreted as granting rights beyond those provided by applicable law or an explicit license.
