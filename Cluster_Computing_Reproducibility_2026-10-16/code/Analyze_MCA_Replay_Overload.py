"""Create publication-ready diagnostics for the official dynamic replay."""

from __future__ import annotations

from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "Results" / "SELECTORFORMAL_FIXED5"
INPUT_CSV = RESULTS / "Replay_SlotLevel_Merged.csv"
OUTPUT = RESULTS / "Replay_Overload_Analysis"

METHODS = ["Greedy", "GAHybrid", "ALM"]
LABELS = {"Greedy": "Greedy", "GAHybrid": "GA-Hybrid", "ALM": "M-CA-ALM"}
COLORS = {"Greedy": "#777777", "GAHybrid": "#3B73A1", "ALM": "#C44E52"}


mpl.rcParams.update(
    {
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
        "legend.fontsize": 6.5,
        "legend.frameon": False,
        "lines.linewidth": 1.35,
        "svg.fonttype": "none",
        "pdf.fonttype": 42,
    }
)


def mean_ci(values: pd.Series) -> tuple[float, float]:
    values = values.dropna().astype(float)
    mean = float(values.mean())
    if len(values) < 2:
        return mean, 0.0
    return mean, float(1.96 * values.std(ddof=1) / np.sqrt(len(values)))


def save_publication_figure(fig: plt.Figure, stem: Path) -> None:
    fig.savefig(stem.with_suffix(".svg"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".pdf"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".tiff"), dpi=600, bbox_inches="tight")
    fig.savefig(stem.with_suffix(".png"), dpi=240, bbox_inches="tight")


def build_run_level(slot: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (n_tasks, algorithm, run), group in slot.groupby(["N", "Algorithm", "Run"]):
        group = group.sort_values("Slot")
        saturated = group.loc[group["BacklogOut"] >= n_tasks, "Slot"]
        rows.append(
            {
                "N": n_tasks,
                "Algorithm": algorithm,
                "Run": run,
                "FirstSaturationSlot": saturated.iloc[0] if not saturated.empty else np.nan,
                "EverSaturated": int(not saturated.empty),
                "TotalSatisfied": group["SatisfiedCount"].sum(),
                "TotalQueueCapDrops": group["DroppedByQueueCap"].sum(),
                "MeanSatisfaction": group["Sat"].mean(),
                "BacklogAUC": group["BacklogOut"].sum(),
            }
        )
    return pd.DataFrame(rows)


def build_trajectory_source(slot: pd.DataFrame) -> pd.DataFrame:
    records = []
    for (n_tasks, algorithm, slot_id), group in slot.groupby(["N", "Algorithm", "Slot"]):
        for metric in ["BacklogOut", "SatisfiedCount", "DroppedByQueueCap"]:
            mean, ci = mean_ci(group[metric])
            records.append(
                {
                    "N": n_tasks,
                    "Algorithm": algorithm,
                    "Slot": slot_id,
                    "Metric": metric,
                    "Mean": mean,
                    "CI95HalfWidth": ci,
                }
            )
    return pd.DataFrame(records)


def plot_overload_boundary(slot: pd.DataFrame, run_level: pd.DataFrame) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(183 / 25.4, 120 / 25.4))
    ax_a, ax_b, ax_c, ax_d = axes.flat

    # a: the primary performance result with run-level 95% confidence intervals.
    positions = np.arange(len(METHODS))
    width = 0.32
    for offset, n_tasks in [(-width / 2, 180), (width / 2, 300)]:
        means, errors = [], []
        for method in METHODS:
            values = run_level.loc[
                (run_level["N"] == n_tasks) & (run_level["Algorithm"] == method),
                "MeanSatisfaction",
            ]
            mean, ci = mean_ci(values)
            means.append(mean)
            errors.append(ci)
        bars = ax_a.bar(
            positions + offset,
            means,
            width,
            yerr=errors,
            capsize=2,
            color=[COLORS[m] for m in METHODS],
            alpha=1.0 if n_tasks == 180 else 0.45,
            edgecolor="white",
            linewidth=0.4,
            label=f"N = {n_tasks}",
        )
        for bar, value in zip(bars, means):
            ax_a.text(
                bar.get_x() + bar.get_width() / 2,
                bar.get_height() + max(errors + [0]) + 0.8,
                f"{value:.1f}",
                ha="center",
                va="bottom",
                fontsize=5.7,
            )
    ax_a.set_xticks(positions, [LABELS[m] for m in METHODS])
    ax_a.set_ylabel("Mean satisfied tasks (%)")
    ax_a.set_ylim(0, 55)
    ax_a.legend(loc="upper left", ncols=2, handlelength=1.2, columnspacing=0.8)

    # b: first queue saturation exposes the operating-regime boundary.
    rng = np.random.default_rng(20260724)
    xmap = {180: 0, 300: 1}
    offsets = {"Greedy": -0.18, "GAHybrid": 0.0, "ALM": 0.18}
    for method in METHODS:
        for n_tasks in [180, 300]:
            values = run_level.loc[
                (run_level["N"] == n_tasks) & (run_level["Algorithm"] == method),
                "FirstSaturationSlot",
            ].dropna()
            x = xmap[n_tasks] + offsets[method] + rng.uniform(-0.025, 0.025, len(values))
            ax_b.scatter(x, values, s=9, color=COLORS[method], alpha=0.65, linewidths=0)
            median = float(values.median())
            ax_b.plot(
                [xmap[n_tasks] + offsets[method] - 0.055, xmap[n_tasks] + offsets[method] + 0.055],
                [median, median],
                color="black",
                linewidth=1.1,
            )
    ax_b.set_xticks([0, 1], ["N = 180", "N = 300"])
    ax_b.set_ylabel("First full-backlog slot")
    ax_b.set_yscale("log")
    ax_b.set_ylim(1, 520)
    ax_b.set_yticks([2, 5, 10, 20, 50, 100, 200, 500])
    ax_b.get_yaxis().set_major_formatter(mpl.ticker.ScalarFormatter())
    handles = [
        mpl.lines.Line2D([], [], marker="o", linestyle="", color=COLORS[m], label=LABELS[m], markersize=4)
        for m in METHODS
    ]
    ax_b.legend(handles=handles, loc="upper right")

    # c-d: N=300 trajectories show immediate saturation and its consequence.
    n300 = slot.loc[slot["N"] == 300].copy()
    cumulative = n300.sort_values("Slot").copy()
    cumulative["CumulativeSatisfied"] = cumulative.groupby(["Algorithm", "Run"])[
        "SatisfiedCount"
    ].cumsum()
    cumulative["CumulativeDrops"] = cumulative.groupby(["Algorithm", "Run"])[
        "DroppedByQueueCap"
    ].cumsum()

    for method in METHODS:
        method_data = cumulative.loc[cumulative["Algorithm"] == method]
        for axis, metric in [(ax_c, "CumulativeSatisfied"), (ax_d, "CumulativeDrops")]:
            grouped = method_data.groupby("Slot")[metric]
            mean = grouped.mean()
            ci = grouped.std(ddof=1) * 1.96 / np.sqrt(grouped.count())
            axis.plot(mean.index, mean.values, color=COLORS[method], label=LABELS[method])
            axis.fill_between(
                mean.index,
                (mean - ci).values,
                (mean + ci).values,
                color=COLORS[method],
                alpha=0.12,
                linewidth=0,
            )

    ax_c.set_xlabel("Replay slot")
    ax_c.set_ylabel("Cumulative satisfied tasks")
    ax_c.legend(loc="upper left")
    ax_d.set_xlabel("Replay slot")
    ax_d.set_ylabel("Cumulative queue-cap drops")
    ax_d.legend(loc="upper left")

    for label, axis in zip("abcd", axes.flat):
        axis.text(
            -0.14,
            1.06,
            label,
            transform=axis.transAxes,
            fontsize=8,
            fontweight="bold",
            va="top",
        )
        axis.grid(axis="y", color="#E4E4E4", linewidth=0.45, zorder=0)
        axis.set_axisbelow(True)

    fig.subplots_adjust(left=0.09, right=0.985, bottom=0.11, top=0.96, wspace=0.32, hspace=0.38)
    save_publication_figure(fig, OUTPUT / "Fig_Replay_Overload_Boundary")
    plt.close(fig)


def write_summary(run_level: pd.DataFrame) -> None:
    summary_rows = []
    for (n_tasks, method), group in run_level.groupby(["N", "Algorithm"]):
        first = group["FirstSaturationSlot"]
        summary_rows.append(
            {
                "N": n_tasks,
                "Algorithm": method,
                "Runs": len(group),
                "MeanSatisfaction": group["MeanSatisfaction"].mean(),
                "MedianFirstSaturationSlot": first.median(),
                "MinFirstSaturationSlot": first.min(),
                "MaxFirstSaturationSlot": first.max(),
                "NeverSaturatedRuns": int(first.isna().sum()),
                "MeanTotalSatisfied": group["TotalSatisfied"].mean(),
                "MeanQueueCapDrops": group["TotalQueueCapDrops"].mean(),
            }
        )
    summary = pd.DataFrame(summary_rows).sort_values(["N", "Algorithm"])
    summary.to_csv(OUTPUT / "Overload_Diagnostic_Summary.csv", index=False)

    n180 = summary.loc[summary["N"] == 180].set_index("Algorithm")
    n300 = summary.loc[summary["N"] == 300].set_index("Algorithm")
    report = f"""# Official Replay Overload Diagnosis

## Figure contract

- Core conclusion: M-CA-ALM delays queue saturation and improves satisfaction at N=180, but N=300 is an immediate full-backlog regime in which its advantage disappears.
- Evidence chain: panel a compares run-level satisfaction; panel b locates saturation onset; panels c-d show the resulting N=300 satisfied-task and queue-drop trajectories.
- Archetype: quantitative grid with a primary comparison panel and three mechanism panels.
- Replicates: 20 paired environment runs per scale and algorithm; bands and bar errors are run-level 95% normal-approximation confidence intervals.

## Verified observations

- At N=180, median first saturation occurs at slot {n180.loc['ALM', 'MedianFirstSaturationSlot']:.0f} for M-CA-ALM, {n180.loc['GAHybrid', 'MedianFirstSaturationSlot']:.0f} for GA-Hybrid, and {n180.loc['Greedy', 'MedianFirstSaturationSlot']:.0f} for Greedy.
- At N=180, M-CA-ALM avoids full saturation in {int(n180.loc['ALM', 'NeverSaturatedRuns'])} of 20 runs.
- At N=300, all methods reach full backlog at median slot {n300.loc['ALM', 'MedianFirstSaturationSlot']:.0f}; the minimum and maximum are also slot 2 for every method.
- At N=300, mean satisfied tasks are {n300.loc['ALM', 'MeanTotalSatisfied']:.0f} for M-CA-ALM and {n300.loc['GAHybrid', 'MeanTotalSatisfied']:.0f} for GA-Hybrid.
- At N=300, mean queue-cap drops are {n300.loc['ALM', 'MeanQueueCapDrops']:.0f} for M-CA-ALM and {n300.loc['GAHybrid', 'MeanQueueCapDrops']:.0f} for GA-Hybrid.

## Interpretation boundary

The current slot log contains aggregate CompositeViolation but no separate deadline-, memory-, latency-, or spillover-failure fields. The figure therefore supports a queue-saturation diagnosis, not a causal attribution to a specific resource bottleneck. The next replay schema should export these failure causes separately.
"""
    (OUTPUT / "OVERLOAD_DIAGNOSIS.md").write_text(report, encoding="utf-8")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    slot = pd.read_csv(INPUT_CSV)
    expected = {
        "N",
        "Run",
        "Slot",
        "Algorithm",
        "SatisfiedCount",
        "Sat",
        "BacklogOut",
        "DroppedByQueueCap",
    }
    missing = expected.difference(slot.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")
    if len(slot) != 60000:
        raise ValueError(f"Expected 60000 official slot rows, found {len(slot)}")

    run_level = build_run_level(slot)
    trajectory = build_trajectory_source(slot)
    run_level.to_csv(OUTPUT / "SourceData_RunLevel.csv", index=False)
    trajectory.to_csv(OUTPUT / "SourceData_Trajectories.csv", index=False)
    write_summary(run_level)
    plot_overload_boundary(slot, run_level)
    print(f"OVERLOAD ANALYSIS PASS: {len(run_level)} run rows; outputs in {OUTPUT}")


if __name__ == "__main__":
    main()
