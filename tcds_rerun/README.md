# Re-running the CDS analyses with the corrected tCDS classifier

## What went wrong

The CDS/ODS labels in `dataframes/everyday_cds_ods.csv` came from the online classifier
(https://kachergis.shinyapps.io/classify_cds_ods/), driven by `1_pipeline.py` in 2023. From August 2022
until November 2026 that app served a stale tCDS model. That model had been trained with clock time as
an extra first feature (9 features). The app passed it only the 8 LENA features, so every feature landed
one slot off and the last slot was empty. The model the paper describes (Kachergis et al.) was retrained
without time two days later, but it never reached the app. See
[classify_cds_ods@fb18716](https://github.com/kachergis/classify_cds_ods/commit/fb18716).

**Confirmed for this dataset:**
- Recomputing with the faulty model and the app's misaligned input reproduces every published
  `cds_prob` for the 76,013 awake segments (max difference 1.2e-7). The correct model does not.
- The sleep classifier was correct: every published `sleep_prob` matches it.
- `sleep_cds_min.csv` (1-minute epochs) was made with the same app, so its `cds_pred` is also faulty.
  The analyses only use its `sleep_pred` column, so nothing downstream is affected.

With the correct model, **41.7% of awake-segment labels change**. CDS segments go from 49,498 to 46,141.

## What depends on the tCDS labels

| Result | Depends on tCDS? |
|---|---|
| Mean CDS probability, % CDS epochs (Sec 3.2) | yes |
| Burst amplitude and duration (Table 2, Sec 4.1, 4.2, Table 3, Table 4, Figs) | yes, computed on CDS epochs |
| Hourly words (`avg_hrly_words`, "quantity") | **no**: the code sums `AWC_COUNT` over all awake epochs, ODS included, although the text calls it "hourly CDS words" |
| Sleep removal, Supp. II (turns), Supp. III (all speech), Supp. IV (naps) | no, these use only sleep labels |

## The burstiness file had to be reconstructed

The shipped `burstiness_compiled_results.csv` cannot be regenerated from `burst_detection_v1.py`, which
uses all rows in file order (see `reproducibility_report.md`, 3a). I tested recipes against it.
- **What matches:** awake CDS epochs only, in chronological order, threshold > 3*SD as coded. This
  reproduces amplitude, duration and burst count exactly for every child in corpora D and M (40/40).
  It also confirms that the paper's burst metrics were computed on the (faulty) CDS labels.
- **What doesn't:** corpora R (0/211) and L (88/306). The shipped file was built from an earlier version
  of their epoch data that is not in the repo.

So the paper's exact numbers cannot be recomputed with corrected labels. Instead, `burst_detection_v2.py`
applies the reconstructed recipe to both the faulty and the corrected labels, so the two can be compared
with the pipeline held fixed. It also runs the paper's stated threshold (mean + 3 SD, Sec 3.3) as a
sensitivity check.

## Results

All models are the paper's own code from `1_modeling.Rmd`, run unchanged by `rerun_tcds_analysis.R`.
Values in **bold** are p < .05. The first column reproduces the manuscript exactly.

| | Paper (shipped burst file) | Faulty labels, 3 SD | **Corrected labels, 3 SD** | Faulty labels, mean + 3 SD | **Corrected labels, mean + 3 SD** |
|---|---|---|---|---|---|
| Recordings / children | 555 / 292 | 555 / 292 | 555 / 292 | 483 / 274 | 488 / 280 |
| Mean CDS prob (SD) | .67 (.10) | .67 (.10) | .71 (.12) | .67 (.10) | .71 (.12) |
| % CDS epochs | 67.19 | 67.19 | 64.18 | 67.19 | 64.18 |
| Mean burst amplitude (words) | 400 | 430 | 389 | 530 | 482 |
| Mean burst duration (0.1-epoch units) | 10.4 | 15.0 | 14.6 | 9.5 | 9.8 |
| **4.1 Age → amplitude**: χ², p | 4.25, **.039** | 1.15, .28 | 7.09, **.008** | 2.17, .14 | 6.20, **.013** |
| β (p) | −0.0022 (**.041**) | −0.0012 (.29) | −0.0037 (**.008**) | −0.0016 (.14) | −0.0034 (**.013**) |
| **4.1 Age → duration**: χ², p | 16.63, **<.001** | 0.26, .61 | 0.62, .43 | 0.12, .73 | 4.41, **.036** |
| β (p) | −0.0047 (**<.001**) | −0.0005 (.61) | −0.0009 (.44) | −0.0007 (.73) | −0.0043 (**.037**) |
| 4.1 Age → quantity: χ², p | 0.35, .56 | 0.35, .56 | 0.35, .56 | 0.14, .71 | 0.68, .41 |
| **4.2 Vocab ~ amplitude**: χ², p | 4.42, **.036** | 4.30, **.038** | 8.12, **.004** | 3.64, .057 | 8.31, **.004** |
| β (p) | 4.55 (**.037**) | 4.24 (**.039**) | 4.79 (**.005**) | 5.18 (.059) | 6.33 (**.004**) |
| **4.2 Vocab ~ duration**: χ², p | 4.12, **.042** | 0.87, .35 | 3.30, .069 | 4.65, **.031** | 0.25, .62 |
| β (p) | 3.17 (**.043**) | 1.14 (.35) | 2.05 (.072) | 1.44 (**.033**) | 0.36 (.62) |
| Vocab model N | 472 | 472 | 472 | 410 | 421 |

The mean + 3 SD columns drop children with no bursts above the threshold (74 faulty, 68 corrected),
because the paper's model comparison cannot run with missing burst values.

## Takeaways

1. **Burst amplitude results hold, and get stronger, with the correct classifier.** Age → amplitude and
   vocabulary ~ amplitude are significant under both thresholds with corrected labels (p ≤ .013). With
   the faulty labels in the same pipeline they were weaker or non-significant.
2. **Burst duration results are not robust.** With corrected labels, age → duration and vocabulary ~
   duration are not significant under the coded 3 SD threshold. Under mean + 3 SD, age → duration is
   significant (p = .036) but vocabulary ~ duration is not (p = .62). The paper's strong age → duration
   effect (p < .001) is not reproduced by any reconstructed variant, with either set of labels.
3. **The descriptive statistics in Sec 3.2 change:** mean CDS probability .71 (.12) instead of .67 (.10),
   and 64.18% CDS epochs instead of 67.19%. Table 2's burst means change too.
4. **Unaffected:** the input-quantity results, sleep removal, and Supp. II–IV.
5. **Caveat:** the comparison uses the reconstructed burst pipeline, not the exact one behind the paper.
   For corpora R and L it differs from the shipped file even with the faulty labels (third column vs
   first). Exact updated numbers need the original epoch data for R and L.

## Files

| File | What it does |
|---|---|
| `models/final_rawLENA_xgb.json` | Correct 8-feature tCDS model (from `classify_cds_ods`) |
| `models/faulty_app_tCDS_9feature.json` | The faulty model the app served, kept so the check can be repeated |
| `reclassify_tcds.py` | Writes `dataframes/everyday_cds_ods_reclassified.csv` (not committed, 29 MB; regenerate with this script) |
| `burst_detection_v2.py` | Reconstructed burst recipe: CDS-only, chronological, `--threshold 3sd` or `mean3sd` |
| `rerun_tcds_analysis.R` | Runs the paper's own model chunks for each condition; writes `tcds_rerun/results.csv` |
| `tcds_rerun/burstiness_*.csv` | Burst metrics per condition |

To reproduce (from the repo root, with `dataframes/` unzipped):

```bash
python reclassify_tcds.py --check-faulty-model models/faulty_app_tCDS_9feature.json
for t in 3sd mean3sd; do
  python burst_detection_v2.py --input dataframes/everyday_cds_ods.csv --output tcds_rerun/burstiness_faulty_labels_$t.csv --threshold $t
  python burst_detection_v2.py --input dataframes/everyday_cds_ods_reclassified.csv --output tcds_rerun/burstiness_corrected_labels_$t.csv --threshold $t
done
Rscript rerun_tcds_analysis.R
```

Tested with Python 3.11 (xgboost 3.2, pandas 3.0, scipy 1.15) and R 4.6 (lme4 2.0.1, lmerTest 3.2.1, dplyr 1.2.1).
