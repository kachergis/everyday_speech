"""Re-run the tCDS/ODS classifier on dataframes/everyday_cds_ods.csv with the correct model.

Why: everyday_cds_ods.csv was produced in 2023 by uploading each recording to the web app
(https://kachergis.shinyapps.io/classify_cds_ods/) via 1_pipeline.py. Until Nov 2026 that app
served a stale tCDS model trained with clock time as a 9th (first) feature, while the app passed
it only the 8 LENA features. Every feature landed one slot off and the last slot was empty, so the
published cds_prob / cds_pred values are wrong. (The sleep model was correct and is left as is.)

This script recomputes cds_prob / cds_pred for awake segments with the correct 8-feature model
(models/final_rawLENA_xgb.json, from github.com/kachergis/classify_cds_ods) using the same feature
transformation as the app, keeps the 0_loading.Rmd convention of cds_pred = cds_prob = 0 for sleep
segments, and recomputes AWC_COUNT_ODS. All other columns are unchanged.

As a check, it also recomputes predictions with the faulty model behaviour and confirms they
reproduce the published values, if the faulty model file is given with --check-faulty-model.

Usage:
    python reclassify_tcds.py [--input dataframes/everyday_cds_ods.csv]
                              [--output dataframes/everyday_cds_ods_reclassified.csv]
                              [--check-faulty-model path/to/old_9feature.model]
"""
import argparse

import numpy as np
import pandas as pd
import xgboost as xgb

FEATURES = ["AWC", "CTC", "CVC", "noise", "silence", "distant", "tv", "meaningful"]


def app_features(d):
    """Same transformation as the classify_cds_ods app does for LENA SP exports:
    counts per minute, and each audio category as a proportion of the segment."""
    dur_min = d["Duration_Secs"] / 60
    f = pd.DataFrame({
        "AWC": d["AWC_COUNT"] / dur_min,
        "CTC": d["CT_COUNT"] / dur_min,
        "CVC": d["CV_COUNT"] / dur_min,
        "noise": d["Noise"] / 60 / dur_min,
        "silence": d["Silence"] / 60 / dur_min,
        "distant": d["Distant"] / 60 / dur_min,
        "tv": d["TV_Secs"] / 60 / dur_min,
        "meaningful": d["Meaningful"] / 60 / dur_min,
    })
    return f[FEATURES].to_numpy(dtype=float)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default="dataframes/everyday_cds_ods.csv")
    ap.add_argument("--output", default="dataframes/everyday_cds_ods_reclassified.csv")
    ap.add_argument("--model", default="models/final_rawLENA_xgb.json")
    ap.add_argument("--check-faulty-model", default=None)
    args = ap.parse_args()

    d = pd.read_csv(args.input, index_col=0, dtype={"child_id": str})
    X = app_features(d)
    awake = (d["sleep_pred"] == 0).to_numpy()

    model = xgb.Booster()
    model.load_model(args.model)
    assert model.feature_names == FEATURES, model.feature_names
    p_new = model.predict(xgb.DMatrix(X, feature_names=FEATURES))

    if args.check_faulty_model:
        old = xgb.Booster()
        old.load_model(args.check_faulty_model)
        assert old.num_features() == 9
        # reproduce the app's bug: the 8 features fill slots 0-7 (so AWC lands in the 'time' slot,
        # etc.) and the last slot is missing
        X_shifted = np.column_stack([X, np.full(len(X), np.nan)])
        p_bug = old.predict(xgb.DMatrix(X_shifted, missing=np.nan, feature_names=old.feature_names))
        max_diff = np.abs(d.loc[awake, "cds_prob"].to_numpy() - p_bug[awake]).max()
        print(f"faulty-model check: max |published cds_prob - faulty app| over awake segments = {max_diff:.2e}")
        assert max_diff < 1e-5, "published values do not match the faulty app"

    out = d.copy()
    out["cds_prob"] = np.where(awake, p_new, 0.0)
    out["cds_pred"] = np.where(awake, (p_new > 0.5).astype(int), 0)
    out["AWC_COUNT_ODS"] = np.where(out["cds_pred"] == 0, 0, out["AWC_COUNT"])
    out.to_csv(args.output)

    old_pred = d.loc[awake, "cds_pred"].to_numpy()
    new_pred = out.loc[awake, "cds_pred"].to_numpy()
    print(f"awake segments: {awake.sum()} | CDS before: {old_pred.sum()} after: {new_pred.sum()} | "
          f"labels changed: {np.mean(old_pred != new_pred):.1%}")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
