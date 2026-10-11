# Recovered 2018 DT/RF development source

`Trees_recovered_source.tar.xz` is a source-only preservation archive created from the author's recovered `RF.zip` in October 2026. Despite the archive name, the ZIP contains both decision-tree (DT) and random-forest (RF) development trees.

Archive SHA-256:

```text
ec46760be16d46f1ca3636c6bc7971e7b7cf21ecb87008e764fef60011bdd812  Trees_recovered_source.tar.xz
```

The archive contains 22 R source files and an internal SHA-256 manifest. It excludes `.Rhistory`, PDFs, and duplicate data/result workspaces.

Key recovered submission scripts:

| File | SHA-256 |
| --- | --- |
| `DT/For submission/dt_full.R` | `168c5a92146b233d7174ba60cefe15e84c3161c5b546fa73bce81302f2ccee76` |
| `DT/For submission/dt_full_log.R` | `95d37564ab916bd57254eff3d5c618261d43af647aa2c01df2efe00a96957225` |
| `RF/For submission/rf_full.R` | `102103b2f1a50bdaa4b4c3a3d7f17cb018fcc84e1b7ed7bca15e1b7607e6a801` |
| `RF/For submission/rf_full_log.R` | `c0693b20d7e278e6cb248af9ce4588ff40507773775ac0f8fa479d67d979992f` |
| `RF/For submission/generate_data.R` | `61ba95a4e0a8867744915852fb35a9dcdca024912f2467d79ec6811020c61c2b` |

The non-log submission scripts and historical data/result workspaces already present in this GitHub repository were compared with the recovered ZIP and match byte-for-byte. The archive therefore serves primarily to preserve the broader development history and the previously missing log variants.

The historical scripts repeatedly derive balancing seeds from system time. Exact reruns are therefore not deterministic. The cleaned default uses an explicit seed while legacy mode preserves the original behavior.
