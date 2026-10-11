# Running the decision-tree and random-forest analyses

Main commands:

```bash
Rscript dt_full.R
Rscript dt_full_log.R
Rscript rf_full.R
Rscript rf_full_log.R
```

For a short smoke run:

```bash
Rscript rf_full.R --max-configurations 1 --max-folds 1 --minimum-per-class 50
```

Use `--legacy` with any main entry point to run the exact recovered 2018 submission script.
