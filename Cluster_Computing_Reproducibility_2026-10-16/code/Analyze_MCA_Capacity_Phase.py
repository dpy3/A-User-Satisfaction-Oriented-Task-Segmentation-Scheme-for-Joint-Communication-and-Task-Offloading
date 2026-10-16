"""Analyze capacity-normalized multi-profile replay results."""

from __future__ import annotations

from pathlib import Path
import sys

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parent
MODE = sys.argv[1] if len(sys.argv) > 1 else "capacityphasesmoke"
RESULTS = ROOT / "Results" / f"{MODE.upper()}_FIXED5"
OUT = RESULTS / "CapacityPhase_Analysis"
PROFILE_ORDER = ["balanced", "compute_bound", "memory_bound", "latency_filtered", "edge_rich"]
ALGORITHMS = ["Greedy", "GAHybrid", "ALM", "ALMv9"]
COLORS = {"Greedy": "#777777", "GAHybrid": "#3B73A1", "ALM": "#9C6B3F", "ALMv9": "#C44E52"}

mpl.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
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


def markdown_table(frame: pd.DataFrame) -> str:
    values = frame.copy()
    for col in values.select_dtypes(include=[np.number]).columns:
        values[col] = values[col].map(lambda x: f"{x:.4g}")
    header = "| " + " | ".join(map(str, values.columns)) + " |"
    rule = "|" + "|".join(["---"] * len(values.columns)) + "|"
    rows = ["| " + " | ".join(map(str, row)) + " |" for row in values.itertuples(index=False, name=None)]
    return "\n".join([header, rule, *rows])


def build_transition_diagnostics(summary: pd.DataFrame, burden: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Select phase cells using a frozen, outcome-independent rule.

    The transition cell is the largest adjacent satisfaction loss for ALMv9.
    Its predecessor is retained as the recoverable-side control, and the
    largest offered load is retained as the extreme-overload cell.
    """
    v9 = summary[summary["Algorithm"] == "ALMv9"].merge(
        burden[burden["Algorithm"] == "ALMv9"],
        on=["Profile", "NormalizedLoadTarget"],
        how="left",
        validate="one_to_one",
    ).sort_values(["Profile", "NormalizedLoadTarget"])
    v9["PreviousLoad"] = v9.groupby("Profile")["NormalizedLoadTarget"].shift()
    v9["SatChangeFromPreviousPP"] = v9.groupby("Profile")["MeanSat"].diff()
    v9["FullQueueChangeFromPrevious"] = v9.groupby("Profile")["FullQueueRate"].diff()

    roles: list[dict[str, object]] = []
    for profile, block in v9.groupby("Profile", sort=False):
        block = block.sort_values("NormalizedLoadTarget").reset_index(drop=True)
        candidates = block.dropna(subset=["SatChangeFromPreviousPP"])
        transition_idx = candidates["SatChangeFromPreviousPP"].idxmin()
        transition_pos = int(block.index[block["NormalizedLoadTarget"] == block.loc[transition_idx, "NormalizedLoadTarget"]][0])
        pre_pos = max(0, transition_pos - 1)
        choices = [
            ("pre_transition", pre_pos),
            ("transition", transition_pos),
            ("extreme", len(block) - 1),
        ]
        for role, pos in choices:
            row = block.iloc[pos]
            roles.append({
                "Profile": profile,
                "CellRole": role,
                "NormalizedLoadTarget": row["NormalizedLoadTarget"],
                "N": int(row["N"]),
                "MeanSat": row["MeanSat"],
                "SatChangeFromPreviousPP": row["SatChangeFromPreviousPP"],
                "FullQueueRate": row["FullQueueRate"],
                "QueueDropRate": row["QueueDropRate"],
            })
    role_frame = pd.DataFrame(roles).drop_duplicates(
        ["Profile", "NormalizedLoadTarget"], keep="first"
    )
    return v9, role_frame


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    run = pd.read_csv(RESULTS / "CapacityPhase_RunLevel_Merged.csv")
    slot = pd.read_csv(RESULTS / "CapacityPhase_SlotLevel_Merged.csv")
    capacity = pd.read_csv(RESULTS / "Capacity_Reference_Frozen.csv")
    expected_profiles = [p for p in PROFILE_ORDER if p in set(run["Profile"])]
    if set(run["Algorithm"]) != set(ALGORITHMS):
        raise ValueError("Capacity-phase algorithm set is incomplete")

    summary = run.groupby(["Profile", "NormalizedLoadTarget", "N", "CapacityRef", "Algorithm"], as_index=False).agg(
        Runs=("Run", "nunique"), MeanSat=("MeanSat", "mean"), SDSat=("MeanSat", "std"),
        TotalSatisfied=("TotalSatisfied", "mean"), BacklogAUC=("BacklogAUC", "mean"),
        QueueCapDrops=("QueueCapDrops", "mean"), DeadlineMisses=("DeadlineMisses", "mean"),
    )
    summary.to_csv(OUT / "CapacityPhase_Summary.csv", index=False)

    full = slot.assign(Full=lambda x: x["BacklogOut"] >= x["N"])
    burden = full.groupby(["Profile", "NormalizedLoadTarget", "Algorithm"], as_index=False).agg(
        FullQueueRate=("Full", "mean"), TriggerRate=("OverloadModeActive", "mean"),
        MemoryBlocks=("MemoryBlockCount", "sum"), IntrinsicLatencyBlocks=("IntrinsicLatencyBlockCount", "sum"),
        SpilloverBlocks=("SpilloverBlockCount", "sum"), FeasibleMisses=("FeasibleMissedCount", "sum"),
        QueueDrops=("DroppedByQueueCap", "sum"), OfferedTasks=("OfferedTasks", "sum"),
    )
    denominator = burden["OfferedTasks"].clip(lower=1)
    burden["QueueDropRate"] = burden["QueueDrops"] / denominator
    burden["MemoryFailureShare"] = burden["MemoryBlocks"] / denominator
    burden["LatencyFailureShare"] = burden["IntrinsicLatencyBlocks"] / denominator
    burden["SpilloverFailureShare"] = burden["SpilloverBlocks"] / denominator
    burden["FeasibleMissShare"] = burden["FeasibleMisses"] / denominator
    burden.to_csv(OUT / "CapacityPhase_Burden.csv", index=False)
    diagnostics, selected_cells = build_transition_diagnostics(summary, burden)
    diagnostics.to_csv(OUT / "CapacityPhase_Transition_Diagnostics.csv", index=False)
    selected_cells.to_csv(OUT / "CapacityPhase_CoDesign_Cell_Roles.csv", index=False)

    fig, axes = plt.subplots(2, 3, figsize=(183 / 25.4, 100 / 25.4), sharex=True, sharey=True)
    for ax, profile in zip(axes.flat, expected_profiles):
        block = summary[summary["Profile"] == profile]
        for alg in ALGORITHMS:
            part = block[block["Algorithm"] == alg].sort_values("NormalizedLoadTarget")
            ax.plot(part["NormalizedLoadTarget"], part["MeanSat"], marker="o", linewidth=1.1,
                    markersize=3, color=COLORS[alg], label=alg)
        cap = int(capacity.loc[capacity["Profile"] == profile, "CapacityRef"].iloc[0])
        ax.set_title(f"{profile.replace('_', ' ')} (C={cap})", fontsize=7.5)
        ax.axhline(50, color="#CCCCCC", linewidth=0.6, linestyle="--")
        ax.grid(axis="y", color="#E5E5E5", linewidth=0.45)
        ax.set_ylim(0, 102)
    axes.flat[-1].axis("off")
    for ax in axes[-1, :2]:
        ax.set_xlabel("Normalized offered load, N/C")
    for ax in axes[:, 0]:
        ax.set_ylabel("Mean satisfaction (%)")
    handles, labels = axes.flat[0].get_legend_handles_labels()
    axes.flat[-1].legend(handles, labels, loc="center", ncol=1)
    fig.subplots_adjust(left=0.075, right=0.99, bottom=0.13, top=0.94, wspace=0.25, hspace=0.34)
    save(fig, OUT / "Fig_Capacity_Normalized_Phase")
    plt.close(fig)

    lines = [
        "# Capacity-normalized phase analysis", "", f"Mode: `{MODE}`", "",
        "Capacity references are frozen from separate LP calibration runs and are not fitted to replay outcomes.", "",
        "## Frozen capacity references", "",
        markdown_table(capacity), "", "## Replay summary", "", markdown_table(summary), "",
        "## Frozen cell-selection rule", "",
        "For each profile, the transition cell is the adjacent load step with the largest ALMv9 satisfaction loss. "
        "The immediately preceding cell is the recoverable-side control, and the largest load is the extreme-overload cell. "
        "Duplicate roles at the same load are collapsed. The rule is fixed before any co-design outcomes are observed.", "",
        markdown_table(selected_cells), "",
        "## Evidence boundary", "",
        "Smoke/pilot rows locate phase behavior only. They are not confirmatory evidence and must not be pooled with future formal runs.",
    ]
    (OUT / "CAPACITY_PHASE_ANALYSIS_REPORT.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"CAPACITY PHASE ANALYSIS PASS: {len(slot)} slot rows, {len(run)} run rows")


if __name__ == "__main__":
    main()
