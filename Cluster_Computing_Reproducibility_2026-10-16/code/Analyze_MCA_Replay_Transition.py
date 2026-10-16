"""Analyze the recoverable-congestion to immediate-overload transition."""

from __future__ import annotations

from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parent
FORMAL = ROOT / "Results" / "SELECTORFORMAL_FIXED5"
PILOT = ROOT / "Results" / "REPLAYTRANSITIONPILOT_FIXED5"
OUTPUT = PILOT / "Replay_Transition_Analysis"

METHODS = ["Greedy", "GAHybrid", "ALM"]
LABELS = {"Greedy": "Greedy", "GAHybrid": "GA-Hybrid", "ALM": "M-CA-ALM"}
COLORS = {"Greedy": "#777777", "GAHybrid": "#3B73A1", "ALM": "#C44E52"}
CAUSES = ["MemoryBlockCount", "IntrinsicLatencyBlockCount", "SpilloverBlockCount", "FeasibleMissedCount"]
CAUSE_LABELS = {
    "MemoryBlockCount": "Memory block",
    "IntrinsicLatencyBlockCount": "Intrinsic latency",
    "SpilloverBlockCount": "Spillover block",
    "FeasibleMissedCount": "Feasible opportunity missed",
}
CAUSE_COLORS = {
    "MemoryBlockCount": "#D98C38",
    "IntrinsicLatencyBlockCount": "#6E9A75",
    "SpilloverBlockCount": "#8A6AA8",
    "FeasibleMissedCount": "#B6B6B6",
}

mpl.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
    "font.size": 7,
    "axes.labelsize": 7,
    "axes.titlesize": 8,
    "axes.linewidth": 0.7,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "xtick.labelsize": 6.5,
    "ytick.labelsize": 6.5,
    "legend.fontsize": 6.2,
    "legend.frameon": False,
    "svg.fonttype": "none",
    "pdf.fonttype": 42,
})


def mean_ci(values: pd.Series) -> tuple[float, float]:
    values = values.dropna().astype(float)
    if len(values) < 2:
        return float(values.mean()), 0.0
    return float(values.mean()), float(1.96 * values.std(ddof=1) / np.sqrt(len(values)))


def save_figure(fig: plt.Figure, stem: Path) -> None:
    fig.savefig(stem.with_suffix(".svg"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".pdf"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".tiff"), dpi=600, bbox_inches="tight")
    fig.savefig(stem.with_suffix(".png"), dpi=240, bbox_inches="tight")


def first_saturation(slot: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (n_tasks, method, run), group in slot.groupby(["N", "Algorithm", "Run"]):
        hit = group.loc[group["BacklogOut"] >= n_tasks, "Slot"]
        rows.append({
            "N": n_tasks,
            "Algorithm": method,
            "Run": run,
            "FirstSaturationSlot": hit.iloc[0] if not hit.empty else np.nan,
        })
    return pd.DataFrame(rows)


def paired_gain(run: pd.DataFrame) -> pd.DataFrame:
    pivot = run.pivot(index=["N", "Run"], columns="Algorithm", values="MeanSat").reset_index()
    gain = pivot[["N", "Run", "ALM", "GAHybrid"]].copy()
    gain["ALMMinusGA"] = gain["ALM"] - gain["GAHybrid"]
    return gain


def draw_phase_figure(formal_slot: pd.DataFrame, formal_run: pd.DataFrame, pilot_slot: pd.DataFrame, pilot_run: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    transition_slot = pd.concat([formal_slot, pilot_slot], ignore_index=True)
    transition_run = pd.concat([formal_run, pilot_run], ignore_index=True)
    saturation = first_saturation(transition_slot)
    gain = paired_gain(transition_run)

    fig, axes = plt.subplots(2, 2, figsize=(183 / 25.4, 120 / 25.4))
    ax_a, ax_b, ax_c, ax_d = axes.flat

    # a: paired gain identifies the ranking crossover, not a universal trend.
    summary_rows = []
    for n_tasks, group in gain.groupby("N"):
        mean, ci = mean_ci(group["ALMMinusGA"])
        summary_rows.append({"N": n_tasks, "MeanALMMinusGA": mean, "CI95HalfWidth": ci, "Runs": len(group)})
    gain_summary = pd.DataFrame(summary_rows).sort_values("N")
    pilot_n = set(pilot_run["N"].unique())
    formal_mask = ~gain_summary["N"].isin(pilot_n)
    ax_a.axhline(0, color="#333333", linewidth=0.7, zorder=1)
    for mask, marker, label in [(formal_mask, "o", "formal replay (n=20)"), (~formal_mask, "s", "transition pilot (n=5)")]:
        part = gain_summary.loc[mask]
        ax_a.errorbar(part["N"], part["MeanALMMinusGA"], yerr=part["CI95HalfWidth"],
                      marker=marker, color=COLORS["ALM"], markersize=4.5, capsize=2,
                      linewidth=1.2, label=label, zorder=3)
    ax_a.set_xlabel("Tasks per arrival slot (N)")
    ax_a.set_ylabel("ALM minus GA mean satisfaction (pp)")
    ax_a.legend(loc="upper left")

    # b: all trajectories use identical backlog-cap semantics.
    for method in METHODS:
        med = saturation.loc[saturation["Algorithm"] == method].groupby("N")["FirstSaturationSlot"].median().sort_index()
        ax_b.plot(med.index, med.values, marker="o", markersize=3.8, color=COLORS[method], label=LABELS[method])
    ax_b.set_yscale("log")
    ax_b.set_xlabel("Tasks per arrival slot (N)")
    ax_b.set_ylabel("Median first full-backlog slot")
    ax_b.set_ylim(1, 600)
    ax_b.set_yticks([2, 5, 10, 20, 50, 100, 200, 500])
    ax_b.yaxis.set_major_formatter(mpl.ticker.ScalarFormatter())
    ax_b.legend(loc="upper right")

    # c: exclusive cause categories, calculated only for the new diagnostic schema.
    source_rows = []
    positions, labels = [], []
    x = 0
    for n_tasks in sorted(pilot_slot["N"].unique()):
        for method in ["GAHybrid", "ALM"]:
            block = pilot_slot.loc[(pilot_slot["N"] == n_tasks) & (pilot_slot["Algorithm"] == method)]
            unsatisfied = (block["OfferedTasks"] - block["SatisfiedCount"]).sum()
            bottom = 0.0
            for cause in CAUSES:
                share = 100 * block[cause].sum() / unsatisfied if unsatisfied else 0.0
                ax_c.bar(x, share, bottom=bottom, width=0.72, color=CAUSE_COLORS[cause], edgecolor="white", linewidth=0.35, label=CAUSE_LABELS[cause] if x == 0 else None)
                bottom += share
                source_rows.append({"N": n_tasks, "Algorithm": method, "Cause": cause, "Count": int(block[cause].sum()), "UnsatisfiedTasks": int(unsatisfied), "SharePct": share})
            positions.append(x)
            labels.append(f"{n_tasks}\n{LABELS[method]}")
            x += 1
        x += 0.28
    ax_c.set_xticks(positions, labels)
    ax_c.tick_params(axis="x", labelsize=5.2)
    ax_c.set_ylim(0, 100)
    ax_c.set_ylabel("Share of unsatisfied tasks (%)")
    ax_c.legend(loc="upper center", bbox_to_anchor=(0.5, 1.01), ncols=2, columnspacing=0.7, handlelength=1.0)
    cause_source = pd.DataFrame(source_rows)

    # d: observed deadline misses overlap the cause taxonomy; queue-cap drops are external truncation.
    burden_rows = []
    x = np.arange(len(sorted(pilot_slot["N"].unique())))
    width = 0.24
    for idx, method in enumerate(METHODS):
        block = pilot_slot.loc[pilot_slot["Algorithm"] == method]
        by_n = block.groupby("N")[["OfferedTasks", "DeadlineMissCount", "DroppedByQueueCap"]].sum().reindex(sorted(pilot_slot["N"].unique()))
        deadline_rate = 100 * by_n["DeadlineMissCount"] / by_n["OfferedTasks"]
        drop_rate = 100 * by_n["DroppedByQueueCap"] / by_n["OfferedTasks"]
        offset = (idx - 1) * width
        ax_d.bar(x + offset, drop_rate, width, color=COLORS[method], alpha=0.78, edgecolor="white", linewidth=0.35, label=LABELS[method])
        ax_d.scatter(x + offset, deadline_rate, color="#111111", s=10, zorder=4)
        for n_tasks, offered, deadline, dropped, d_rate, q_rate in zip(by_n.index, by_n["OfferedTasks"], by_n["DeadlineMissCount"], by_n["DroppedByQueueCap"], deadline_rate, drop_rate):
            burden_rows.append({"N": n_tasks, "Algorithm": method, "OfferedTasks": int(offered), "DeadlineMisses": int(deadline), "QueueCapDrops": int(dropped), "DeadlineMissRatePct": d_rate, "QueueCapDropRatePct": q_rate})
    ax_d.set_xticks(x, [str(n) for n in sorted(pilot_slot["N"].unique())])
    ax_d.set_xlabel("Tasks per arrival slot (N)")
    ax_d.set_ylabel("Rate across offered tasks (%)")
    method_handles = [mpl.patches.Patch(color=COLORS[method], alpha=0.78, label=LABELS[method]) for method in METHODS]
    deadline_handle = mpl.lines.Line2D([], [], marker="o", linestyle="", color="#111111", label="Deadline miss", markersize=3.6)
    ax_d.legend(handles=method_handles + [deadline_handle], loc="upper left", ncols=2, columnspacing=0.8, handlelength=1.0)

    for label, axis in zip("abcd", axes.flat):
        axis.text(-0.14, 1.06, label, transform=axis.transAxes, fontsize=8, fontweight="bold", va="top")
        axis.grid(axis="y", color="#E4E4E4", linewidth=0.45, zorder=0)
        axis.set_axisbelow(True)

    fig.subplots_adjust(left=0.09, right=0.985, bottom=0.13, top=0.96, wspace=0.32, hspace=0.40)
    save_figure(fig, OUTPUT / "Fig_Replay_Transition_Boundary")
    plt.close(fig)
    return gain_summary, pd.DataFrame(burden_rows), cause_source, saturation


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    formal_slot = pd.read_csv(FORMAL / "Replay_SlotLevel_Merged.csv")
    formal_run = pd.read_csv(FORMAL / "Replay_RunLevel_Merged.csv")
    pilot_slot = pd.read_csv(PILOT / "Replay_SlotLevel_Merged.csv")
    pilot_run = pd.read_csv(PILOT / "Replay_RunLevel_Merged.csv")
    required = set(CAUSES + ["DeadlineMissCount", "DroppedByQueueCap", "OfferedTasks", "SatisfiedCount"])
    missing = required.difference(pilot_slot.columns)
    if missing:
        raise ValueError(f"Pilot diagnostic columns missing: {sorted(missing)}")
    if len(pilot_slot) != 9000 or len(pilot_run) != 45:
        raise ValueError("Pilot evidence is incomplete.")
    partition = pilot_slot[CAUSES].sum(axis=1)
    if not (partition == pilot_slot["OfferedTasks"] - pilot_slot["SatisfiedCount"]).all():
        raise ValueError("Failure causes do not partition unsatisfied tasks.")

    gain, burden, cause, saturation = draw_phase_figure(formal_slot, formal_run, pilot_slot, pilot_run)
    gain.to_csv(OUTPUT / "SourceData_ALM_GA_Gain.csv", index=False)
    burden.to_csv(OUTPUT / "SourceData_Failure_Burden.csv", index=False)
    cause.to_csv(OUTPUT / "SourceData_Bottleneck_Composition.csv", index=False)
    saturation.to_csv(OUTPUT / "SourceData_First_Saturation.csv", index=False)

    crossover = gain.loc[gain["N"].isin([210, 240, 270]), ["N", "MeanALMMinusGA", "Runs"]]
    report = "# Replay Transition Pilot\n\n"
    report += "## Figure contract\n\n"
    report += "- Core conclusion: the dynamic ALM advantage persists through the N=240 pilot but is no longer stable at N=270, while failure burden is dominated by load spillover rather than intrinsic task latency.\n"
    report += "- Evidence: paired mean-satisfaction differences, saturation onset, exclusive unsatisfied-task causes, and observed deadline/queue-cap burden.\n"
    report += "- Design: N=180 and N=300 are completed formal replay with 20 paired runs; N=210/240/270 are exploratory transition pilots with 5 paired runs each. Pilot points are not formal confirmatory claims.\n\n"
    report += "## Paired transition estimates\n\n"
    report += "| N | Mean ALM minus GA (pp) | Paired runs |\n|---:|---:|---:|\n"
    for row in crossover.itertuples(index=False):
        report += f"| {row.N} | {row.MeanALMMinusGA:.3f} | {row.Runs} |\n"
    report += "\n"
    report += "## Interpretation guardrails\n\n"
    report += "The bottleneck causes are mutually exclusive counterfactual classifications of unsatisfied tasks. DeadlineMissCount is an observed admitted-task measure and may overlap the causal categories; QueueCapDrops is an external backlog truncation measure. Neither should be added to the cause shares.\n"
    (OUTPUT / "TRANSITION_PILOT_REPORT.md").write_text(report, encoding="utf-8")
    print(f"TRANSITION ANALYSIS PASS: {len(pilot_slot)} pilot slots, {len(pilot_run)} pilot runs.")


if __name__ == "__main__":
    main()
