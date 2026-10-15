"""Submission-grade redraw of the two formal Paper 1 figures.

Only frozen CSV evidence is read.  The script changes visual encoding and
exports; it does not change experiment values or claims.
"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.lines import Line2D
from matplotlib.patches import Patch


plt.rcParams.update(
    {
        "font.family": "sans-serif",
        "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "Liberation Sans"],
        "svg.fonttype": "none",
        "pdf.fonttype": 42,
        "font.size": 7.1,
        "axes.labelsize": 7.4,
        "axes.titlesize": 8.0,
        "xtick.labelsize": 6.7,
        "ytick.labelsize": 6.7,
        "legend.fontsize": 6.5,
        "axes.linewidth": 0.75,
        "axes.spines.right": False,
        "axes.spines.top": False,
        "xtick.major.width": 0.7,
        "ytick.major.width": 0.7,
        "xtick.major.size": 2.8,
        "ytick.major.size": 2.8,
        "legend.frameon": False,
        "savefig.facecolor": "white",
    }
)


ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "Results"
V9_DIR = RESULTS / "SELECTORV9FORMAL_FIXED5"
V9_ANALYSIS = V9_DIR / "SelectorV9_Analysis"
REPLAY_DIR = RESULTS / "SELECTORFORMAL_FIXED5" / "Replay_Overload_Analysis"
PACKAGE_FIGURES = (
    ROOT.parent.parent
    / "Manuscript"
    / "Submission_Docs"
    / "Cluster_Computing_Final_Package_2026-06-23"
    / "Manuscript"
    / "figures"
)

N_LEVELS = [240, 270, 300]
METHODS = ["Greedy", "GAHybrid", "ALM", "ALMv9"]
COLORS = {
    "Greedy": "#6B7280",
    "GAHybrid": "#2B6CA3",
    "ALM": "#A96E3B",
    "ALMv9": "#C54B55",
}
LABELS = {"Greedy": "Greedy", "GAHybrid": "GA-Hybrid", "ALM": "M-CA-ALM", "ALMv9": "M-CA-ALM-v9"}


def ci(values: np.ndarray, seed: int, n_boot: int = 10000) -> tuple[float, float, float]:
    values = np.asarray(values, dtype=float)
    rng = np.random.default_rng(seed)
    means = rng.choice(values, (n_boot, len(values)), replace=True).mean(axis=1)
    lo, hi = np.quantile(means, [0.025, 0.975])
    return float(values.mean()), float(lo), float(hi)


def panel(ax: plt.Axes, label: str) -> None:
    ax.text(-0.12, 1.045, label, transform=ax.transAxes, ha="left", va="bottom",
            fontsize=9.0, fontweight="bold")


def clean(ax: plt.Axes, axis: str = "y") -> None:
    ax.grid(axis=axis, color="#E6E8EB", linewidth=0.5)
    ax.set_axisbelow(True)


def save(fig: plt.Figure, stem: Path) -> None:
    stem.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(stem.with_suffix(".svg"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".pdf"), bbox_inches="tight")
    fig.savefig(stem.with_suffix(".tiff"), dpi=600, bbox_inches="tight")
    fig.savefig(stem.with_suffix(".png"), dpi=300, bbox_inches="tight")
    plt.close(fig)


def write_source(frame: pd.DataFrame, name: str, directory: Path) -> None:
    frame.to_csv(directory / name, index=False)


def v9_run_level() -> pd.DataFrame:
    return pd.read_csv(V9_DIR / "Replay_RunLevel_Merged.csv")


def fig_selector_v9() -> None:
    run = v9_run_level()
    run = run[run.Algorithm.isin(METHODS)].copy()
    run.to_csv(V9_ANALYSIS / "SourceData_Fig_SelectorV9_RunLevel.csv", index=False)

    paired = pd.read_csv(V9_ANALYSIS / "SelectorV9_Paired_Deltas.csv")
    burden = pd.read_csv(V9_ANALYSIS / "SelectorV9_Burden_Deltas.csv")
    trigger = pd.read_csv(V9_ANALYSIS / "SelectorV9_Trigger_Burden.csv")
    write_source(paired, "SourceData_Fig_SelectorV9_PairedDeltas.csv", V9_ANALYSIS)
    write_source(burden, "SourceData_Fig_SelectorV9_BurdenDeltas.csv", V9_ANALYSIS)
    write_source(trigger, "SourceData_Fig_SelectorV9_TriggerBurden.csv", V9_ANALYSIS)

    fig, axes = plt.subplots(1, 3, figsize=(7.2, 2.72), gridspec_kw={"width_ratios": [1.18, 1.0, 1.12]})
    rng = np.random.default_rng(20260802)

    # a: comparison against all three frozen baselines.
    comparators = ["ALM", "GAHybrid", "Greedy"]
    x = np.arange(len(N_LEVELS))
    offsets = {"ALM": -0.18, "GAHybrid": 0.0, "Greedy": 0.18}
    for comp in comparators:
        means, lows, highs = [], [], []
        for n in N_LEVELS:
            v9 = run[(run.N == n) & (run.Algorithm == "ALMv9")].sort_values("Run").MeanSat.to_numpy()
            base = run[(run.N == n) & (run.Algorithm == comp)].sort_values("Run").MeanSat.to_numpy()
            vals = v9 - base
            m, lo, hi = ci(vals, 1000 + N_LEVELS.index(n) * 10 + comparators.index(comp))
            means.append(m); lows.append(lo); highs.append(hi)
            xx = x[N_LEVELS.index(n)] + offsets[comp]
            axes[0].scatter(np.full(len(vals), xx) + rng.uniform(-0.035, 0.035, len(vals)), vals,
                            s=9, color=COLORS[comp], alpha=0.24, linewidths=0, zorder=2)
        axes[0].errorbar(x + np.array([offsets[c] for c in [comp] * len(x)]), means,
                         yerr=[np.array(means) - np.array(lows), np.array(highs) - np.array(means)],
                         fmt="o", ms=4.5, lw=1.15, capsize=2.0, color=COLORS[comp],
                         markeredgecolor="white", markeredgewidth=0.45, label=f"vs {LABELS[comp]}")
    axes[0].axhline(0, color="#42464B", linewidth=0.75)
    axes[0].axvspan(0.65, 1.35, color="#F4F0EA", zorder=-10)
    axes[0].set_xticks(x, [str(n) for n in N_LEVELS])
    axes[0].set_xlabel("Offered tasks, N")
    axes[0].set_ylabel("V9 satisfaction gain (pp)")
    axes[0].set_ylim(-9, 18)
    axes[0].text(0.98, 0.97, "transition", transform=axes[0].transAxes,
                 ha="right", va="top", fontsize=5.9, color="#7A5D3B")
    axes[0].legend(loc="upper left", ncol=1, handlelength=1.25, borderaxespad=0.2)
    clean(axes[0])

    # b: paired seed-level v9 minus ALM, with the run distribution visible.
    for i, n in enumerate(N_LEVELS):
        v9 = run[(run.N == n) & (run.Algorithm == "ALMv9")].sort_values("Run").MeanSat.to_numpy()
        alm = run[(run.N == n) & (run.Algorithm == "ALM")].sort_values("Run").MeanSat.to_numpy()
        vals = v9 - alm
        m, lo, hi = ci(vals, 2200 + i)
        axes[1].scatter(np.full(len(vals), i) + rng.uniform(-0.10, 0.10, len(vals)), vals,
                        s=12, color=COLORS["ALMv9"], alpha=0.42, linewidths=0, zorder=2)
        axes[1].errorbar(i, m, yerr=[[m - lo], [hi - m]], fmt="o", ms=5.2, lw=1.2,
                         capsize=2.2, color=COLORS["ALMv9"], markeredgecolor="white",
                         markeredgewidth=0.45, zorder=4)
        axes[1].text(i, hi + 0.35, f"{m:+.2f}", ha="center", va="bottom", fontsize=5.9, color="#7B3038")
    axes[1].axhline(0, color="#42464B", linewidth=0.75)
    axes[1].axvspan(0.65, 1.35, color="#F4F0EA", zorder=-10)
    axes[1].set_xticks(x, [str(n) for n in N_LEVELS])
    axes[1].set_xlabel("Offered tasks, N")
    axes[1].set_ylabel("V9 − M-CA-ALM (pp)")
    axes[1].set_ylim(-10.5, 16.5)
    clean(axes[1])

    # c: aggregate queue-cap drop rates, where the mechanism diagnosis is clearest.
    methods = ["GAHybrid", "ALM", "ALMv9"]
    width = 0.22
    xpos = np.arange(len(N_LEVELS))
    for j, method in enumerate(methods):
        rows = trigger[trigger.Algorithm.eq(method)].set_index("N").loc[N_LEVELS]
        vals = rows.DropRatePct.to_numpy(dtype=float)
        bars = axes[2].bar(xpos + (j - 1) * width, vals, width=width, color=COLORS[method],
                           alpha=0.88, linewidth=0, label=LABELS[method])
        for bar, val in zip(bars, vals):
            axes[2].text(bar.get_x() + bar.get_width() / 2, val + 0.8, f"{val:.1f}",
                         ha="center", va="bottom", fontsize=5.4, color="#35383D")
    axes[2].axvspan(0.65, 1.35, color="#F4F0EA", zorder=-10)
    axes[2].set_xticks(xpos, [str(n) for n in N_LEVELS])
    axes[2].set_xlabel("Offered tasks, N")
    axes[2].set_ylabel("Queue-cap drop rate (%)")
    axes[2].set_ylim(0, 56)
    axes[2].legend(loc="upper left", ncol=1, handlelength=1.25, borderaxespad=0.2)
    clean(axes[2])

    for ax, label in zip(axes, "abc"):
        panel(ax, label)
    fig.subplots_adjust(left=0.075, right=0.995, bottom=0.20, top=0.90, wspace=0.36)
    save(fig, V9_ANALYSIS / "Fig_SelectorV9_Formal")
    save(fig, PACKAGE_FIGURES / "Fig_SelectorV9_Formal")


def trajectories_for(n: int, metric: str) -> pd.DataFrame:
    """Return exact cumulative trajectories and run-level 95% CIs.

    The frozen slot table stores per-slot counts.  Cumulative curves are
    reconstructed per run before aggregation so that the y-axis and caption
    describe the same quantity.
    """
    slot = pd.read_csv(REPLAY_DIR.parent / "Replay_SlotLevel_Merged.csv")
    slot = slot[(slot.N == n) & slot.Algorithm.isin(["Greedy", "GAHybrid", "ALM"])].copy()
    slot = slot.sort_values(["Algorithm", "Run", "Slot"])
    value = slot[metric].astype(float)
    slot["Cumulative"] = value.groupby([slot.Algorithm, slot.Run]).cumsum()
    out = (slot.groupby(["Algorithm", "Slot"], as_index=False)["Cumulative"]
           .agg(Mean="mean", CI95HalfWidth=lambda s: 1.96 * s.std(ddof=1) / np.sqrt(len(s))))
    out["N"] = n
    out["Metric"] = metric
    return out


def fig_replay_overload() -> None:
    run = pd.read_csv(REPLAY_DIR / "SourceData_RunLevel.csv")
    summary = pd.read_csv(REPLAY_DIR / "Overload_Diagnostic_Summary.csv")
    run.to_csv(REPLAY_DIR / "SourceData_Fig_Replay_RunLevel.csv", index=False)
    summary.to_csv(REPLAY_DIR / "SourceData_Fig_Replay_Summary.csv", index=False)
    fig, axes = plt.subplots(2, 2, figsize=(7.2, 4.48), gridspec_kw={"height_ratios": [0.92, 1.08]})
    rng = np.random.default_rng(20260803)

    # a: grouped mean satisfaction with run-level 95% CIs.
    methods = ["Greedy", "GAHybrid", "ALM"]
    x = np.arange(len(methods))
    width = 0.34
    for j, n in enumerate([180, 300]):
        vals_means, lows, highs = [], [], []
        for method in methods:
            vals = run[(run.N == n) & (run.Algorithm == method)].MeanSatisfaction.to_numpy(dtype=float)
            m, lo, hi = ci(vals, 3000 + j * 10 + methods.index(method))
            vals_means.append(m); lows.append(lo); highs.append(hi)
        pos = x + (j - 0.5) * width
        bars = axes[0, 0].bar(pos, vals_means, width=width, color=[COLORS[m] for m in methods],
                              alpha=0.92 if n == 180 else 0.46, edgecolor="white", linewidth=0.35,
                              label=f"N = {n}", zorder=2)
        axes[0, 0].errorbar(pos, vals_means,
                            yerr=[np.array(vals_means) - np.array(lows), np.array(highs) - np.array(vals_means)],
                            fmt="none", ecolor="#23272B", elinewidth=0.9, capsize=2.1, zorder=3)
        for bar, val in zip(bars, vals_means):
            axes[0, 0].text(bar.get_x() + bar.get_width() / 2, val + 1.0, f"{val:.1f}",
                            ha="center", va="bottom", fontsize=5.5)
    axes[0, 0].set_xticks(x, [LABELS[m] for m in methods])
    axes[0, 0].set_ylabel("Mean satisfaction (%)")
    axes[0, 0].set_ylim(0, 57)
    axes[0, 0].legend(loc="upper left", ncol=2, handlelength=1.2)
    clean(axes[0, 0])

    # b: first full-backlog slot, with the immediate-overload boundary explicit.
    positions = {180: 0, 300: 1}
    for n, base_x in positions.items():
        for j, method in enumerate(methods):
            vals = run[(run.N == n) & (run.Algorithm == method)].FirstSaturationSlot.to_numpy(dtype=float)
            pos = base_x + (j - 1) * 0.22
            axes[0, 1].scatter(np.full(len(vals), pos) + rng.uniform(-0.045, 0.045, len(vals)), vals,
                              s=11, color=COLORS[method], alpha=0.48, linewidths=0, zorder=2)
            med = np.median(vals)
            axes[0, 1].plot([pos - 0.075, pos + 0.075], [med, med], color="#15191D", lw=1.5, zorder=4)
    axes[0, 1].set_xticks([0, 1], ["N = 180", "N = 300"])
    axes[0, 1].set_yscale("log")
    axes[0, 1].set_ylim(1.7, 550)
    axes[0, 1].set_ylabel("First full-backlog slot (log)")
    axes[0, 1].axhline(2, color="#A8ADB3", linestyle="--", linewidth=0.65)
    axes[0, 1].text(1.03, 2.12, "immediate cap", ha="left", va="bottom", fontsize=5.6, color="#6B7076")
    clean(axes[0, 1])

    # c/d: N=300 cumulative trajectories; shaded bands are supplied 95% CIs.
    for ax, metric, ylabel, title in [
        (axes[1, 0], "SatisfiedCount", "Cumulative satisfied tasks", "N = 300: completions"),
        (axes[1, 1], "DroppedByQueueCap", "Cumulative queue-cap drops", "N = 300: queue-cap losses"),
    ]:
        data = trajectories_for(300, metric)
        for method in methods:
            part = data[data.Algorithm.eq(method)].sort_values("Slot")
            slot = part.Slot.to_numpy(dtype=float)
            mean = part.Mean.to_numpy(dtype=float)
            band = part.CI95HalfWidth.to_numpy(dtype=float)
            ax.plot(slot, mean, color=COLORS[method], lw=1.25, label=LABELS[method])
            ax.fill_between(slot, np.maximum(0, mean - band), mean + band, color=COLORS[method], alpha=0.10, linewidth=0)
        ax.axvline(2, color="#A8ADB3", linestyle="--", linewidth=0.65)
        ax.text(0.98, 0.95, "backlog cap by slot 2", transform=ax.transAxes,
                ha="right", va="top", fontsize=5.5, color="#6B7076")
        ax.set_title(title, loc="left", fontsize=7.6, fontweight="bold", pad=4)
        ax.set_xlabel("Replay slot")
        ax.set_ylabel(ylabel)
        ax.set_xlim(0, 505)
        clean(ax)
        ax.legend(loc="upper left", ncol=1, handlelength=1.2)

    panel(axes[0, 0], "a"); panel(axes[0, 1], "b"); panel(axes[1, 0], "c"); panel(axes[1, 1], "d")
    fig.subplots_adjust(left=0.085, right=0.995, bottom=0.13, top=0.94, wspace=0.28, hspace=0.42)
    save(fig, REPLAY_DIR / "Fig_Replay_Overload_Boundary")
    save(fig, PACKAGE_FIGURES / "Fig_Replay_Overload_Boundary")


def main() -> None:
    fig_selector_v9()
    fig_replay_overload()
    print("Wrote Paper 1 formal figures to frozen-analysis and canonical package directories.")


if __name__ == "__main__":
    main()
