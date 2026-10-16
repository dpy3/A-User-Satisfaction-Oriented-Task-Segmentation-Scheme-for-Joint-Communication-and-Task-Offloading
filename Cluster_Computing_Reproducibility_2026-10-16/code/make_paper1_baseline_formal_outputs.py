"""Render Paper 1 static main-result outputs from BASELINEFORMAL_FIXED5 only."""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data" / "BASELINEFORMAL_FIXED5"
OUT = ROOT / "figures"
MANUSCRIPT_OUT = ROOT / "manuscript" / "springer_official" / "figures"
SOURCE_OUT = ROOT / "data" / "figure_source_data"
MANUSCRIPT_ROOT = ROOT / "manuscript" / "springer_official"
METHODS = ["Greedy", "LPRelax", "DPP", "MPC", "GAHybrid", "ALM"]
LABELS = {
    "Greedy": "Greedy", "LPRelax": "LP relaxation", "DPP": "DPP",
    "MPC": "MPC", "GAHybrid": "GA-Hybrid", "ALM": "M-CA-ALM",
}
COLORS = {
    "Greedy": "#6E7781", "LPRelax": "#4C78A8", "DPP": "#72B7B2",
    "MPC": "#F2A541", "GAHybrid": "#B279A2", "ALM": "#C44E52",
}


def export(fig: plt.Figure, stem: str) -> None:
    for directory in (OUT, MANUSCRIPT_OUT):
        directory.mkdir(parents=True, exist_ok=True)
        for suffix, kwargs in {
            ".pdf": {}, ".svg": {}, ".png": {"dpi": 300},
            ".tiff": {"dpi": 600},
        }.items():
            fig.savefig(directory / f"{stem}{suffix}", bbox_inches="tight", **kwargs)


def write_static_table_rows(summary: pd.DataFrame, paired_ga: pd.DataFrame) -> None:
    """Generate the two static-result table bodies used by the manuscript."""
    by_n = summary.set_index(["N", "Algorithm"])
    paired_by_n = paired_ga.set_index("N")
    table1_rows = []
    table5_rows = []
    levels = sorted(summary.N.unique())
    for n in levels:
        ga_test = paired_by_n.loc[n]
        row_end = r" \\" if n != levels[-1] else ""
        table1_rows.append(
            f"{n} & {by_n.loc[(n, 'Greedy'), 'SatMean']:.2f} & "
            f"{by_n.loc[(n, 'GAHybrid'), 'SatMean']:.2f} & "
            f"{by_n.loc[(n, 'ALM'), 'SatMean']:.2f} & "
            f"{ga_test.MeanDiffSat_ALMminusGA:.2f} & "
            f"[{ga_test.DiffCI95Low:.2f}, {ga_test.DiffCI95High:.2f}] & "
            f"{ga_test.PairedCohenDz:.2f} & $<0.001${row_end}"
        )
        table5_rows.append(
            f"{n} & {by_n.loc[(n, 'Greedy'), 'SatMean']:.2f} & "
            f"{by_n.loc[(n, 'GAHybrid'), 'SatMean']:.2f} & "
            f"{by_n.loc[(n, 'LPRelax'), 'SatMean']:.2f} & "
            f"{by_n.loc[(n, 'DPP'), 'SatMean']:.2f} & "
            f"{by_n.loc[(n, 'MPC'), 'SatMean']:.2f} & "
            f"{by_n.loc[(n, 'ALM'), 'SatMean']:.2f}{row_end}"
        )
    (MANUSCRIPT_ROOT / "Paper1_Static_Table1_Rows_BASELINEFORMAL_FIXED5.tex").write_text(
        "\n".join(table1_rows) + "\n", encoding="utf-8"
    )
    (MANUSCRIPT_ROOT / "Paper1_Static_Table5_Rows_BASELINEFORMAL_FIXED5.tex").write_text(
        "\n".join(table5_rows) + "\n", encoding="utf-8"
    )


def main() -> None:
    runs = pd.read_csv(SOURCE / "Static_RunLevel.csv")
    summary = pd.read_csv(SOURCE / "Static_Summary_Official.csv")
    paired_ga = pd.read_csv(SOURCE / "Static_ALM_vs_GAHybrid_Paired.csv")
    paired_all = pd.read_csv(SOURCE / "Static_ALM_vs_AllBaselines_Paired.csv")

    expected = len(METHODS) * 6 * 30
    if len(runs) != expected or (runs.groupby(["N", "Algorithm"]).size() != 30).any():
        raise RuntimeError("BASELINEFORMAL_FIXED5 does not contain a complete 6-by-6-by-30 design.")
    if set(summary.Algorithm) != set(METHODS):
        raise RuntimeError("Static summary methods do not match the frozen baseline design.")

    SOURCE_OUT.mkdir(parents=True, exist_ok=True)
    runs.to_csv(SOURCE_OUT / "SourceData_Table2_Static_RunLevel_BASELINEFORMAL_FIXED5.csv", index=False)
    summary.to_csv(SOURCE_OUT / "SourceData_Fig1_Static_Baseline_Summary_BASELINEFORMAL_FIXED5.csv", index=False)
    paired_ga.to_csv(SOURCE_OUT / "SourceData_Table2_ALM_vs_GA_BASELINEFORMAL_FIXED5.csv", index=False)
    paired_all.to_csv(SOURCE_OUT / "SourceData_Table5_ALM_vs_AllBaselines_BASELINEFORMAL_FIXED5.csv", index=False)
    write_static_table_rows(summary, paired_ga)

    plt.rcParams.update({
        "font.family": "sans-serif", "font.sans-serif": ["Arial", "DejaVu Sans"],
        "font.size": 7.4, "axes.labelsize": 7.8, "axes.titlesize": 8.3,
        "legend.fontsize": 6.6, "pdf.fonttype": 42, "svg.fonttype": "none",
        "axes.spines.top": False, "axes.spines.right": False,
    })
    fig, axes = plt.subplots(1, 2, figsize=(7.1, 2.65), gridspec_kw={"width_ratios": [1.25, 1.0]})
    levels = sorted(summary.N.unique())
    for method in METHODS:
        part = summary[summary.Algorithm.eq(method)].sort_values("N")
        axes[0].plot(part.N, part.SatMean, marker="o", ms=3.6, lw=1.35,
                     color=COLORS[method], label=LABELS[method])
        axes[0].fill_between(part.N, part.SatCI95Low, part.SatCI95High,
                             color=COLORS[method], alpha=0.10, linewidth=0)
    axes[0].set_xlabel("Offered tasks, N")
    axes[0].set_ylabel("Mean satisfaction (%)")
    axes[0].set_xticks(levels)
    axes[0].set_ylim(15, 100)
    axes[0].grid(axis="y", color="#E3E6E8", linewidth=0.55)
    axes[0].set_axisbelow(True)
    axes[0].legend(ncol=2, loc="upper right", frameon=False, handlelength=1.4)
    axes[0].text(-0.12, 1.04, "a", transform=axes[0].transAxes, weight="bold", fontsize=9)

    alm = paired_all[paired_all.Comparator.ne("ALM")].copy()
    x = np.arange(len(levels))
    for method in ["Greedy", "LPRelax", "DPP", "MPC", "GAHybrid"]:
        part = alm[alm.Comparator.eq(method)].set_index("N").loc[levels]
        axes[1].plot(x, part.MeanDiffALMMinusComparator, marker="o", ms=3.3,
                     lw=1.25, color=COLORS[method], label=f"vs {LABELS[method]}")
        axes[1].fill_between(x, part.DiffCI95Low, part.DiffCI95High,
                             color=COLORS[method], alpha=0.11, linewidth=0)
    axes[1].axhline(0, color="#363A3E", linewidth=0.7)
    axes[1].set_xlabel("Offered tasks, N")
    axes[1].set_ylabel("M-CA-ALM gain (pp)")
    axes[1].set_xticks(x, levels)
    axes[1].grid(axis="y", color="#E3E6E8", linewidth=0.55)
    axes[1].set_axisbelow(True)
    axes[1].legend(ncol=1, loc="upper right", frameon=False, handlelength=1.4)
    axes[1].text(-0.12, 1.04, "b", transform=axes[1].transAxes, weight="bold", fontsize=9)
    fig.subplots_adjust(left=0.075, right=0.995, bottom=0.22, top=0.91, wspace=0.34)
    export(fig, "Fig_Static_Baseline_Comparison")
    print("Wrote static source tables and Figure 1 from BASELINEFORMAL_FIXED5.")


if __name__ == "__main__":
    main()
