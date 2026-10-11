# Workspace generation

The historical generator used Windows-root paths and time-dependent random validation-fold selection. The cleaned generator is portable and deterministic:

```bash
Rscript generate_data.R --complete complete.csv --geology geology.csv --output data.RData --seed 2019
```

For historical reproduction, prefer the archived `data.RData` already in this repository. Regeneration creates a new partition.
