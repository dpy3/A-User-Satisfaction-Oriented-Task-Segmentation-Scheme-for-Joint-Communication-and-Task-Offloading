from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats


ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "replay_fast_v1_code" / "Results" / "REPLAYCORRECTED_CANDIDATE_V1"
OUT = ROOT / "replay_final_audit"
OUT.mkdir(exist_ok=True)
ALGORITHMS = ["Greedy", "GAHybrid", "ALM"]
SCALES = [180, 300]


def t_ci(values: pd.Series) -> list[float]:
    x = values.astype(float).to_numpy()
    mean = float(np.mean(x))
    if len(x) < 2:
        return [mean, mean]
    half = float(stats.t.ppf(0.975, len(x) - 1) * stats.sem(x))
    return [mean - half, mean + half]


def main() -> None:
    slot_paths = sorted(RESULTS.glob("Replay_SlotLevel_*.csv"))
    run_paths = sorted(RESULTS.glob("Replay_RunLevel_*.csv"))
    if len(slot_paths) != 9 or len(run_paths) != 9:
        raise SystemExit(f"Expected 9 slot and run CSVs; found {len(slot_paths)} and {len(run_paths)}")

    slots = pd.concat([pd.read_csv(p) for p in slot_paths], ignore_index=True)
    program_runs = pd.concat([pd.read_csv(p) for p in run_paths], ignore_index=True)
    keys = ["N", "Run", "Slot", "Algorithm"]
    errors: dict[str, int] = {}
    errors["row_count"] = abs(len(slots) - 60000)
    errors["duplicate_keys"] = int(slots.duplicated(keys).sum())
    errors["unknown_algorithm_rows"] = int((~slots.Algorithm.isin(ALGORITHMS)).sum())
    errors["wrong_evidence_class_rows"] = int((slots.EvidenceClass != "REPLAYCORRECTED").sum())
    errors["wrong_schema_rows"] = int((slots.SchemaVersion != "MCA-CANDIDATE-1.0-REPLAY").sum())
    errors["satisfaction_formula_rows"] = int(
        (np.abs(slots.Sat - 100 * slots.SatisfiedCount / slots.OfferedTasks) > 1e-8).sum()
    )
    errors["resource_violation_rows"] = int((slots.ResourceViolation != 0).sum())
    errors["offered_count_rows"] = int(
        (slots.OfferedTasks != slots.BacklogIn + slots.Arrivals).sum()
    )
    accounted = slots.SatisfiedCount + slots.BacklogOut + slots.DroppedByQueueCap
    errors["queue_conservation_rows"] = int((slots.OfferedTasks != accounted).sum())
    errors["backlog_cap_rows"] = int((slots.BacklogOut > slots.N).sum())
    errors["cap_drop_rows"] = int((slots.DroppedByQueueCap < 0).sum())
    errors["invalid_slot_rows"] = int((~slots.Slot.between(1, 500)).sum())

    group_sizes = slots.groupby(["N", "Run", "Algorithm"], observed=True).size()
    errors["wrong_group_count"] = abs(len(group_sizes) - 120)
    errors["incomplete_groups"] = int((group_sizes != 500).sum())
    slots = slots.sort_values(["N", "Run", "Algorithm", "Slot"], kind="stable")
    run_rows = (
        slots.groupby(["N", "Run", "Algorithm"], as_index=False, observed=True)
        .agg(
            Slots=("Slot", "size"),
            MeanSat=("Sat", "mean"),
            TotalSatisfied=("SatisfiedCount", "sum"),
            BacklogAUC=("BacklogOut", "sum"),
            PeakBacklog=("BacklogOut", "max"),
            FinalBacklog=("BacklogOut", "last"),
            QueueCapDrops=("DroppedByQueueCap", "sum"),
            DeadlineMisses=("DeadlineMissCount", "sum"),
            MemoryBlocks=("MemoryBlockCount", "sum"),
            IntrinsicLatencyBlocks=("IntrinsicLatencyBlockCount", "sum"),
            SpilloverBlocks=("SpilloverBlockCount", "sum"),
            FeasibleMisses=("FeasibleMissedCount", "sum"),
            MeanRuntimeSec=("RuntimeSec", "mean"),
        )
    )

    id_cols = ["N", "Run", "Algorithm"]
    compare = run_rows.merge(program_runs, on=id_cols, suffixes=("_recalc", "_program"), validate="one_to_one")
    errors["run_rows_missing_or_extra"] = abs(len(compare) - 120)
    numeric = [c for c in run_rows.columns if c not in id_cols]
    for c in numeric:
        delta = np.abs(compare[f"{c}_recalc"].astype(float) - compare[f"{c}_program"].astype(float))
        errors[f"runlevel_mismatch_{c}"] = int((delta > 1e-7).sum())

    run_rows.to_csv(OUT / "Replay_RunLevel_RECOMPUTED.csv", index=False, float_format="%.12g")
    slots.to_csv(OUT / "Replay_SlotLevel_60000.csv", index=False, float_format="%.12g")

    summaries = []
    for n in SCALES:
        for alg in ALGORITHMS:
            r = run_rows[(run_rows.N == n) & (run_rows.Algorithm == alg)].sort_values("Run")
            summaries.append({
                "N": n,
                "Algorithm": alg,
                "n_runs": int(len(r)),
                "mean_run_mean_slot_satisfaction_pct": float(r.MeanSat.mean()),
                "sd_across_run_mean_slot_satisfaction_pct": float(r.MeanSat.std(ddof=1)),
                "ci95_run_mean_slot_satisfaction_pct": t_ci(r.MeanSat),
                "mean_completions_per_run": float(r.TotalSatisfied.mean()),
                "mean_queue_cap_drops_per_run": float(r.QueueCapDrops.mean()),
                "mean_backlog_auc_per_run": float(r.BacklogAUC.mean()),
                "mean_peak_backlog": float(r.PeakBacklog.mean()),
                "mean_final_backlog": float(r.FinalBacklog.mean()),
                "mean_runtime_per_slot_s": float(r.MeanRuntimeSec.mean()),
            })
    summary_frame = pd.DataFrame(summaries)
    summary_frame.to_csv(OUT / "Replay_Summary_ByScale.csv", index=False, float_format="%.12g")

    contrasts = []
    for n in SCALES:
        pivot = run_rows[run_rows.N == n].pivot(index="Run", columns="Algorithm", values="MeanSat")
        for comp in ["Greedy", "GAHybrid"]:
            diff = pivot["ALM"] - pivot[comp]
            contrasts.append({
                "N": n, "contrast": f"ALM - {comp}", "n_paired_runs": int(diff.notna().sum()),
                "mean_difference_percentage_points": float(diff.mean()),
                "ci95_percentage_points": t_ci(diff),
                "positive_pairs": int((diff > 0).sum()),
                "ties": int((diff == 0).sum()),
                "negative_pairs": int((diff < 0).sum()),
            })
    pd.DataFrame(contrasts).to_csv(OUT / "Replay_PairedContrasts_Descriptive.csv", index=False, float_format="%.12g")

    # Equal weight to each scale and run, keeping the two scales distinct in primary tables.
    scale_means = run_rows.groupby(["N", "Algorithm"], as_index=False).MeanSat.mean()
    pooled = scale_means.groupby("Algorithm").MeanSat.mean().to_dict()
    report = {
        "source_slot_files": [p.name for p in slot_paths],
        "source_program_run_files": [p.name for p in run_paths],
        "slot_rows": int(len(slots)),
        "run_rows_recomputed": int(len(run_rows)),
        "unique_method_slot_keys": int(slots[keys].drop_duplicates().shape[0]),
        "group_count": int(len(group_sizes)),
        "all_groups_500_slots": bool((group_sizes == 500).all()),
        "all_queue_and_count_checks_pass": bool(all(v == 0 for k, v in errors.items() if k.startswith(("queue_", "offered_", "backlog_", "cap_", "satisfaction_", "resource_", "invalid_")))),
        "program_runlevel_matches_recomputed": bool(all(v == 0 for k, v in errors.items() if k.startswith("runlevel_mismatch_"))),
        "errors": errors,
        "summary_by_scale": summaries,
        "paired_contrasts_descriptive": contrasts,
        "equal_scale_weight_mean_satisfaction_pct": {k: float(v) for k, v in pooled.items()},
        "interpretation_boundary": "Algorithm comparisons are descriptive for this synthetic replay protocol; run durations are not a controlled equal-budget timing experiment.",
    }
    (OUT / "REPLAY_FINAL_RECOMPUTATION_AUDIT.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"rows": report["slot_rows"], "runs": report["run_rows_recomputed"], "all_groups_500": report["all_groups_500_slots"], "errors": errors, "summary": summaries, "paired": contrasts}, indent=2))

    if any(v != 0 for v in errors.values()):
        raise SystemExit("Recomputation audit found discrepancies; inspect REPLAY_FINAL_RECOMPUTATION_AUDIT.json")


if __name__ == "__main__":
    main()
