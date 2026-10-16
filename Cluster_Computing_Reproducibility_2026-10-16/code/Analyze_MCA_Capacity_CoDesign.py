"""Analyze admission/capacity factorial replay outputs."""

from __future__ import annotations
from pathlib import Path
import sys
import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats

ROOT = Path(__file__).resolve().parent
MODE = sys.argv[1] if len(sys.argv) > 1 else "capacitycodesignsmoke"
RESULTS = ROOT / "Results" / f"{MODE.upper()}_FIXED5"
OUT = RESULTS / "CapacityCoDesign_Analysis"
POLICIES = ["ALMv9", "ALMv9Admission", "ALMv9Capacity", "ALMv9CoDesign"]
COLORS = {"ALMv9": "#777777", "ALMv9Admission": "#3B73A1",
          "ALMv9Capacity": "#C44E52", "ALMv9CoDesign": "#2E8B57"}

mpl.rcParams.update({"font.family": "sans-serif", "font.sans-serif": ["Arial", "DejaVu Sans"],
                     "font.size": 7, "axes.spines.top": False, "axes.spines.right": False,
                     "svg.fonttype": "none", "pdf.fonttype": 42, "legend.frameon": False})

def save(fig: plt.Figure, stem: Path) -> None:
    fig.savefig(stem.with_suffix(".svg"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".pdf"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".png"), dpi=240, bbox_inches="tight")
    fig.savefig(stem.with_suffix(".tiff"), dpi=600, bbox_inches="tight")

def markdown_table(frame: pd.DataFrame) -> str:
    values = frame.copy()
    for col in values.select_dtypes(include=[np.number]).columns:
        values[col] = values[col].map(lambda x: f"{x:.4g}")
    return "\n".join([
        "| " + " | ".join(values.columns) + " |",
        "|" + "|".join(["---"] * len(values.columns)) + "|",
        *["| " + " | ".join(map(str, row)) + " |" for row in values.itertuples(index=False, name=None)],
    ])

def paired_contrasts(run: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    wide = run[run["Algorithm"].isin(POLICIES)].pivot(
        index=["Profile", "NormalizedLoadTarget", "Run"],
        columns="Algorithm", values="MeanSat"
    ).reset_index()
    definitions = {
        "AdmissionMinusV9": ("ALMv9Admission", "ALMv9"),
        "CapacityMinusV9": ("ALMv9Capacity", "ALMv9"),
        "CoDesignMinusV9": ("ALMv9CoDesign", "ALMv9"),
        "CoDesignMinusAdmission": ("ALMv9CoDesign", "ALMv9Admission"),
        "CoDesignMinusCapacity": ("ALMv9CoDesign", "ALMv9Capacity"),
    }
    long_parts = []
    for name, (left, right) in definitions.items():
        part = wide[["Profile", "NormalizedLoadTarget", "Run"]].copy()
        part["Contrast"] = name
        part["DifferencePP"] = wide[left] - wide[right]
        long_parts.append(part)
    paired = pd.concat(long_parts, ignore_index=True)

    rows = []
    for keys, block in paired.groupby(["Profile", "NormalizedLoadTarget", "Contrast"], sort=False):
        values = block["DifferencePP"].dropna().to_numpy()
        n = len(values); mean = float(np.mean(values)); sd = float(np.std(values, ddof=1)) if n > 1 else np.nan
        half = float(stats.t.ppf(0.975, n - 1) * sd / np.sqrt(n)) if n > 1 else np.nan
        rows.append({"Profile": keys[0], "NormalizedLoadTarget": keys[1], "Contrast": keys[2],
                     "Pairs": n, "MeanDifferencePP": mean, "SDDifferencePP": sd,
                     "CI95LowPP": mean - half, "CI95HighPP": mean + half})
    return paired, pd.DataFrame(rows)

def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    run = pd.read_csv(RESULTS / "CapacityCoDesign_RunLevel_Merged.csv")
    slot = pd.read_csv(RESULTS / "CapacityCoDesign_SlotLevel_Merged.csv")
    summary = run.groupby(["Profile", "NormalizedLoadTarget", "Algorithm"], as_index=False).agg(
        Runs=("Run", "nunique"), MeanSat=("MeanSat", "mean"), TotalSatisfied=("TotalSatisfied", "mean"),
        AdmissionRejects=("AdmissionRejects", "mean"), BacklogAUC=("BacklogAUC", "mean"),
        QueueCapDrops=("QueueCapDrops", "mean"), CapacityActiveSlots=("CapacityActiveSlots", "mean"),
        MeanCapacityBoost=("MeanCapacityBoost", "mean"), ElasticComputeSlotUnits=("ElasticComputeSlotUnits", "mean"),
    )
    summary.to_csv(OUT / "CapacityCoDesign_Summary.csv", index=False)
    pivot = summary[summary["Algorithm"].isin(POLICIES)].pivot(
        index=["Profile", "NormalizedLoadTarget"], columns="Algorithm", values="MeanSat"
    ).reset_index()
    pivot["AdmissionMinusV9"] = pivot["ALMv9Admission"] - pivot["ALMv9"]
    pivot["CapacityMinusV9"] = pivot["ALMv9Capacity"] - pivot["ALMv9"]
    pivot["CoDesignMinusAdmission"] = pivot["ALMv9CoDesign"] - pivot["ALMv9Admission"]
    pivot["CoDesignMinusCapacity"] = pivot["ALMv9CoDesign"] - pivot["ALMv9Capacity"]
    pivot.to_csv(OUT / "CapacityCoDesign_Contrasts.csv", index=False)
    paired, paired_summary = paired_contrasts(run)
    paired.to_csv(OUT / "CapacityCoDesign_Paired_Differences.csv", index=False)
    paired_summary.to_csv(OUT / "CapacityCoDesign_Paired_Summary.csv", index=False)

    profiles = list(dict.fromkeys(summary["Profile"]))
    fig, axes = plt.subplots(2, 3, figsize=(183 / 25.4, 100 / 25.4), sharex=True, sharey=True)
    for ax, profile in zip(axes.flat, profiles):
        block = summary[summary["Profile"] == profile]
        for policy in POLICIES:
            part = block[block["Algorithm"] == policy].sort_values("NormalizedLoadTarget")
            ax.plot(part["NormalizedLoadTarget"], part["MeanSat"], marker="o", markersize=3,
                    linewidth=1.1, color=COLORS[policy], label=policy)
        ax.set_title(profile.replace("_", " "), fontsize=7.5)
        ax.grid(axis="y", color="#E5E5E5", linewidth=0.45)
    for ax in axes.flat[len(profiles):]: ax.axis("off")
    for ax in axes[-1, :2]: ax.set_xlabel("Normalized offered load, N/C")
    for ax in axes[:, 0]: ax.set_ylabel("Mean satisfaction (%)")
    handles, labels = axes.flat[0].get_legend_handles_labels()
    axes.flat[-1].legend(handles, labels, loc="center", fontsize=6)
    fig.subplots_adjust(left=0.075, right=0.99, bottom=0.13, top=0.94, wspace=0.25, hspace=0.34)
    save(fig, OUT / "Fig_Capacity_CoDesign")
    plt.close(fig)

    report = ["# Admission/capacity co-design analysis", "", f"Mode: `{MODE}`", "",
              "Rejected arrivals remain in the offered-task denominator. Capacity variants use the same base-profile schedule and alter deployment resources only.", "",
              "## Factorial contrasts", "", markdown_table(pivot), "", "## Policy summary", "",
              markdown_table(summary), "", "## Paired run-level contrasts", "",
              markdown_table(paired_summary), "", "## Evidence boundary", "",
              "Smoke/pilot contrasts are diagnostic only; multi-run paired confirmation is required before causal or superiority claims."]
    (OUT / "CAPACITY_CODESIGN_ANALYSIS_REPORT.md").write_text("\n".join(report), encoding="utf-8")
    print(f"CAPACITY CO-DESIGN ANALYSIS PASS: {len(slot)} slot rows, {len(run)} run rows")

if __name__ == "__main__":
    main()
