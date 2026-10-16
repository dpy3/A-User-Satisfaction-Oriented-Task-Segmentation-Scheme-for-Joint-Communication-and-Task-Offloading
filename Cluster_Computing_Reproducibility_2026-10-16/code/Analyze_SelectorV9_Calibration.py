"""Analyze selector-v9 calibration, formal, or independent replication outputs."""

from __future__ import annotations

from pathlib import Path
import math
import sys

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

try:
    from scipy import stats as scipy_stats
except Exception:  # pragma: no cover - optional publication-stat dependency
    scipy_stats = None


ROOT = Path(__file__).resolve().parent
MODE = sys.argv[1] if len(sys.argv) > 1 else "selectorv9calibrationaudit"
RESULTS = ROOT / "Results" / f"{MODE.upper()}_FIXED5"
OUT = RESULTS / "SelectorV9_Analysis"
PRIMARY = "ALMv9"
COMPARATORS = ["ALM", "GAHybrid", "Greedy"]
CAUSES = ["MemoryBlockCount", "IntrinsicLatencyBlockCount", "SpilloverBlockCount", "FeasibleMissedCount"]
COLORS = {"ALMv9": "#C44E52", "ALM": "#9C6B3F", "GAHybrid": "#3B73A1", "Greedy": "#777777"}
IS_REPLICATION = "replication" in MODE.lower()
IS_FORMAL = "formal" in MODE.lower()

mpl.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
    "font.size": 7,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.linewidth": 0.7,
    "legend.frameon": False,
    "svg.fonttype": "none",
    "pdf.fonttype": 42,
})


def save(fig: plt.Figure, stem: Path) -> None:
    fig.savefig(stem.with_suffix(".svg"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".pdf"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".png"), dpi=240, bbox_inches="tight")
    fig.savefig(stem.with_suffix(".tiff"), dpi=600, bbox_inches="tight")


def mean_ci(x: pd.Series) -> tuple[float, float]:
    x = x.dropna().astype(float)
    if len(x) < 2:
        return float(x.mean()), 0.0
    return float(x.mean()), float(1.96 * x.std(ddof=1) / np.sqrt(len(x)))


def paired_stats(x: pd.Series) -> dict[str, float]:
    x = x.dropna().astype(float)
    n = int(len(x))
    mean = float(x.mean()) if n else float("nan")
    sd = float(x.std(ddof=1)) if n > 1 else float("nan")
    ci = float(1.96 * sd / math.sqrt(n)) if n > 1 else 0.0
    dz = float(mean / sd) if n > 1 and sd > 1e-12 else float("nan")
    t_stat = float(mean / (sd / math.sqrt(n))) if n > 1 and sd > 1e-12 else float("nan")
    if scipy_stats is not None and n > 1 and not math.isnan(t_stat):
        p_value = float(2 * scipy_stats.t.sf(abs(t_stat), df=n - 1))
    else:
        p_value = float("nan")
    return {
        "Mean": mean,
        "CI95HalfWidth": ci,
        "PairedCohenDz": dz,
        "PairedT": t_stat,
        "PairedPValue": p_value,
        "Runs": n,
    }


def fmt_float(x: float, digits: int = 3) -> str:
    if pd.isna(x):
        return "NA"
    return f"{x:.{digits}f}"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    run_path = RESULTS / "Replay_RunLevel_Merged.csv"
    slot_path = RESULTS / "Replay_SlotLevel_Merged.csv"
    if not run_path.exists() or not slot_path.exists():
        raise SystemExit(f"Merged replay files not found in {RESULTS}; run Finalize_MCA_Official_Replay('{MODE}') first.")
    run = pd.read_csv(run_path)
    slot = pd.read_csv(slot_path)

    expected = {PRIMARY, *COMPARATORS}
    found = set(run["Algorithm"].unique())
    missing = expected.difference(found)
    if missing:
        raise ValueError(f"Missing algorithms: {sorted(missing)}")
    if "OverloadModeActive" not in slot.columns:
        raise ValueError("Replay slot log lacks OverloadModeActive; rerun with audit schema.")

    # Run-level paired deltas.
    pivot = run.pivot(index=["N", "Run"], columns="Algorithm", values="MeanSat").reset_index()
    runtime_pivot = run.pivot(index=["N", "Run"], columns="Algorithm", values="MeanRuntimeSec").reset_index()
    delta_rows = []
    for n, group in pivot.groupby("N"):
        for comp in COMPARATORS:
            d = group[PRIMARY] - group[comp]
            stats = paired_stats(d)
            rt_group = runtime_pivot[runtime_pivot["N"] == n]
            rt_delta = rt_group[PRIMARY] - rt_group[comp]
            rt_stats = paired_stats(rt_delta)
            delta_rows.append({
                "N": n,
                "Comparator": comp,
                "MeanDeltaSatPP": stats["Mean"],
                "CI95HalfWidth": stats["CI95HalfWidth"],
                "PairedCohenDz": stats["PairedCohenDz"],
                "PairedT": stats["PairedT"],
                "PairedPValue": stats["PairedPValue"],
                "MeanRuntimeDeltaSec": rt_stats["Mean"],
                "RuntimeDeltaCI95HalfWidth": rt_stats["CI95HalfWidth"],
                "Wins": int((d > 0).sum()),
                "Losses": int((d < 0).sum()),
                "Ties": int((d == 0).sum()),
                "Runs": stats["Runs"],
            })
    deltas = pd.DataFrame(delta_rows)
    official_pair_path = RESULTS / "Replay_ALM_Paired.csv"
    if official_pair_path.exists():
        official = pd.read_csv(official_pair_path)
        official = official[official["Metric"] == "MeanSat"][
            ["N", "Comparator", "PSignFlip", "PHolm"]
        ]
        deltas = deltas.merge(official, on=["N", "Comparator"], how="left", validate="one_to_one")
    else:
        deltas["PSignFlip"] = np.nan
        deltas["PHolm"] = np.nan
    deltas.to_csv(OUT / "SelectorV9_Paired_Deltas.csv", index=False)

    # Slot-level trigger and burden summary.
    trigger = slot.groupby(["N", "Algorithm"]).agg(
        Slots=("Slot", "count"),
        Triggered=("OverloadModeActive", "sum"),
        MeanBacklogRatioIn=("BacklogRatioIn", "mean"),
        TotalSatisfied=("SatisfiedCount", "sum"),
        TotalOffered=("OfferedTasks", "sum"),
        QueueCapDrops=("DroppedByQueueCap", "sum"),
        DeadlineMisses=("DeadlineMissCount", "sum"),
    ).reset_index()
    trigger["TriggerRatePct"] = 100 * trigger["Triggered"] / trigger["Slots"]
    trigger["SatRatePct"] = 100 * trigger["TotalSatisfied"] / trigger["TotalOffered"]
    trigger["DropRatePct"] = 100 * trigger["QueueCapDrops"] / trigger["TotalOffered"]
    trigger["DeadlineMissRatePct"] = 100 * trigger["DeadlineMisses"] / trigger["TotalOffered"]
    trigger.to_csv(OUT / "SelectorV9_Trigger_Burden.csv", index=False)

    burden_rows = []
    burden_metrics = [
        "SatRatePct",
        "DropRatePct",
        "DeadlineMissRatePct",
        "QueueCapDrops",
        "DeadlineMisses",
        "MeanBacklogRatioIn",
    ]
    burden_pivot = trigger.pivot(index="N", columns="Algorithm", values=burden_metrics)
    for n in sorted(trigger["N"].unique()):
        for comp in COMPARATORS:
            row = {"N": n, "Comparator": comp}
            for metric in burden_metrics:
                row[f"Delta_{metric}"] = float(burden_pivot.loc[n, (metric, PRIMARY)] - burden_pivot.loc[n, (metric, comp)])
            burden_rows.append(row)
    burdens = pd.DataFrame(burden_rows)
    burdens.to_csv(OUT / "SelectorV9_Burden_Deltas.csv", index=False)

    cause_rows = []
    for (n, alg), block in slot.groupby(["N", "Algorithm"]):
        unsat = (block["OfferedTasks"] - block["SatisfiedCount"]).sum()
        for cause in CAUSES:
            count = int(block[cause].sum())
            cause_rows.append({"N": n, "Algorithm": alg, "Cause": cause, "Count": count,
                               "UnsatisfiedTasks": int(unsat), "SharePct": 100 * count / unsat if unsat else 0})
    causes = pd.DataFrame(cause_rows)
    causes.to_csv(OUT / "SelectorV9_Bottleneck_Composition.csv", index=False)

    fig, axes = plt.subplots(1, 3, figsize=(183 / 25.4, 58 / 25.4))
    ax = axes[0]
    for comp in COMPARATORS:
        part = deltas[deltas["Comparator"] == comp]
        ax.errorbar(part["N"], part["MeanDeltaSatPP"], yerr=part["CI95HalfWidth"], marker="o", capsize=2,
                    color=COLORS[comp], label=f"vs {comp}", linewidth=1.1)
    ax.axhline(0, color="#222222", linewidth=0.7)
    ax.set_xlabel("N")
    ax.set_ylabel("ALMv9 satisfaction gain (pp)")
    ax.legend(loc="best")

    ax = axes[1]
    paired_alm = pivot[["N", "Run", PRIMARY, "ALM"]].copy()
    paired_alm["Delta"] = paired_alm[PRIMARY] - paired_alm["ALM"]
    for n, part in paired_alm.groupby("N"):
        offsets = np.linspace(-2.2, 2.2, len(part))
        ax.scatter(np.full(len(part), n) + offsets, part["Delta"], s=10, color="#6F6F6F", alpha=0.65,
                   edgecolors="none", zorder=2)
        summary = deltas[(deltas["N"] == n) & (deltas["Comparator"] == "ALM")].iloc[0]
        ax.errorbar(n, summary["MeanDeltaSatPP"], yerr=summary["CI95HalfWidth"], marker="o", markersize=4.5,
                    color=COLORS[PRIMARY], capsize=2.5, linewidth=1.2, zorder=3)
    ax.axhline(0, color="#222222", linewidth=0.7)
    ax.set_xlabel("N")
    ax.set_ylabel("Paired ALMv9 - ALM (pp)")
    ax.set_xticks(sorted(paired_alm["N"].unique()))

    ax = axes[2]
    subset = trigger[trigger["Algorithm"].isin([PRIMARY, "ALM", "GAHybrid"])]
    width = 0.22
    xs = np.arange(len(sorted(subset["N"].unique())))
    for idx, alg in enumerate(["GAHybrid", "ALM", PRIMARY]):
        part = subset[subset["Algorithm"] == alg].sort_values("N")
        ax.bar(xs + (idx - 1) * width, part["DropRatePct"], width, color=COLORS[alg], label=alg, alpha=0.82)
    ax.set_xticks(xs, [str(n) for n in sorted(subset["N"].unique())])
    ax.set_xlabel("N")
    ax.set_ylabel("Queue-cap drop rate (%)")
    ax.legend(loc="best")

    for label, axis in zip("abc", axes):
        axis.text(-0.16, 1.08, label, transform=axis.transAxes, fontsize=8, fontweight="bold", va="top")
        axis.grid(axis="y", color="#E4E4E4", linewidth=0.45)
        axis.set_axisbelow(True)
    fig.subplots_adjust(left=0.075, right=0.99, bottom=0.22, top=0.92, wspace=0.42)
    if IS_REPLICATION:
        fig_stem = "Fig_SelectorV9_N300_Replication"
    elif IS_FORMAL:
        fig_stem = "Fig_SelectorV9_Formal"
    else:
        fig_stem = "Fig_SelectorV9_Calibration"
    save(fig, OUT / fig_stem)
    plt.close(fig)

    if IS_REPLICATION:
        evidence_note = (
            "Independent frozen-parameter N=300 replication on runs 31--50; these runs were not used "
            "for calibration and are reported separately from runs 11--30."
        )
    elif IS_FORMAL:
        evidence_note = "Held-out confirmatory runs 11--30; v9 thresholds were frozen from calibration seeds 6--10."
    else:
        evidence_note = "Calibration/audit runs only; use these rows to freeze v9 settings, not as confirmatory evidence."
    report = [
        "# Selector-v9 Replay Analysis",
        "",
        "Mode: " + chr(96) + MODE + chr(96),
        "",
        f"Evidence note: {evidence_note}",
        "",
        "## Paired Mean-Satisfaction Deltas",
        "",
        "| N | Comparator | Mean delta pp | 95% half-width | Cohen dz | Sign-flip p | Holm p | Runtime delta s | Wins | Losses | Ties | Runs |",
        "|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in deltas.itertuples(index=False):
        report.append(
            f"| {row.N} | {row.Comparator} | {fmt_float(row.MeanDeltaSatPP)} | {fmt_float(row.CI95HalfWidth)} | "
            f"{fmt_float(row.PairedCohenDz)} | {fmt_float(row.PSignFlip, 4)} | {fmt_float(row.PHolm, 4)} | "
            f"{fmt_float(row.MeanRuntimeDeltaSec)} | "
            f"{row.Wins} | {row.Losses} | {row.Ties} | {row.Runs} |"
        )
    report.extend([
        "",
        "## Burden Deltas",
        "",
        "Positive satisfaction-rate delta is good; negative drop/deadline deltas are good.",
        "",
        "| N | Comparator | Delta sat-rate pp | Delta drop-rate pp | Delta deadline-rate pp | Delta queue drops | Delta deadline misses |",
        "|---:|---|---:|---:|---:|---:|---:|",
    ])
    for row in burdens.itertuples(index=False):
        report.append(
            f"| {row.N} | {row.Comparator} | {fmt_float(row.Delta_SatRatePct)} | "
            f"{fmt_float(row.Delta_DropRatePct)} | {fmt_float(row.Delta_DeadlineMissRatePct)} | "
            f"{fmt_float(row.Delta_QueueCapDrops, 0)} | {fmt_float(row.Delta_DeadlineMisses, 0)} |"
        )
    report.extend(["", "## Guardrail", "", evidence_note])
    (OUT / "SELECTOR_V9_ANALYSIS_REPORT.md").write_text("\n".join(report), encoding="utf-8")
    print(f"SELECTOR V9 ANALYSIS PASS: {len(run)} run rows, {len(slot)} slot rows.")


if __name__ == "__main__":
    main()
