"""Audit manuscript-facing MCA evidence against finalized CSV outputs."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "Results"
MANUSCRIPT = (
    ROOT.parent.parent
    / "Manuscript"
    / "Submission_Docs"
    / "Cluster_Computing_Final_Package_2026-06-23"
    / "Manuscript"
)
OUT = RESULTS / "MANUSCRIPT_EVIDENCE_AUDIT.md"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def close(actual: float, expected: float, tol: float = 5e-3) -> None:
    require(abs(actual - expected) <= tol, f"Expected {expected}, found {actual}")


def manuscript_text() -> str:
    files = [MANUSCRIPT / "manuscript.tex", *sorted((MANUSCRIPT / "sections").glob("*.tex"))]
    return "\n".join(path.read_text(encoding="utf-8") for path in files)


def main() -> None:
    checks: list[str] = []

    # Static evidence and manuscript range claim.
    static_pairs = pd.read_csv(RESULTS / "SELECTORFORMAL_FIXED5" / "Static_ALM_vs_GAHybrid_Paired.csv")
    congested = static_pairs[static_pairs["N"].isin([120, 150, 180, 200, 250, 300])]
    close(float(congested["MeanDiffSat_ALMminusGA"].min()), 0.72, tol=0.01)
    close(float(congested["MeanDiffSat_ALMminusGA"].max()), 5.28, tol=0.01)
    require((congested["PHolm"] < 0.05).all(), "A congested static comparison is not Holm-significant.")
    checks.append("Static 0.72--5.28 pp range and Holm-significant congested comparisons")

    # Original replay boundary.
    replay_summary = pd.read_csv(RESULTS / "SELECTORFORMAL_FIXED5" / "Replay_Summary_Official.csv")
    replay_pair = pd.read_csv(RESULTS / "SELECTORFORMAL_FIXED5" / "Replay_ALM_Paired.csv")
    lookup = replay_summary.set_index(["N", "Algorithm"])
    close(float(lookup.loc[(180, "GAHybrid"), "MeanSat"]), 33.45, tol=0.01)
    close(float(lookup.loc[(180, "ALM"), "MeanSat"]), 46.41, tol=0.01)
    pair_180 = replay_pair[(replay_pair["N"] == 180) & (replay_pair["Comparator"] == "GAHybrid") &
                             (replay_pair["Metric"] == "MeanSat")].iloc[0]
    close(float(pair_180["MeanAdvantageALM"]), 12.96, tol=0.01)
    require(int(pair_180["Wins"]) == 20, "N=180 ALM does not win all paired runs.")
    checks.append("Original N=180 replay means, 12.96 pp gain, and 20/20 wins")

    # Selector-v9 held-out integrity.
    v9_root = RESULTS / "SELECTORV9FORMAL_FIXED5"
    slot = pd.read_csv(v9_root / "Replay_SlotLevel_Merged.csv")
    run = pd.read_csv(v9_root / "Replay_RunLevel_Merged.csv")
    expected_algorithms = {"Greedy", "GAHybrid", "ALM", "ALMv9"}
    require(len(slot) == 120_000, f"Expected 120000 formal slot rows, found {len(slot)}")
    require(len(run) == 240, f"Expected 240 formal run rows, found {len(run)}")
    require(set(slot["N"].unique()) == {240, 270, 300}, "Unexpected formal replay scales.")
    require(set(slot["Run"].unique()) == set(range(11, 31)), "Formal replay is not restricted to runs 11--30.")
    require(set(slot["Algorithm"].unique()) == expected_algorithms, "Formal replay algorithm set is incomplete.")
    key = ["N", "Run", "Slot", "Algorithm"]
    require(not slot.duplicated(key).any(), "Duplicate formal slot key detected.")
    group_sizes = slot.groupby(["N", "Run", "Algorithm"]).size()
    require((group_sizes == 500).all(), "A formal run/algorithm does not contain 500 slots.")
    seed_counts = slot.groupby(["N", "Run", "Slot"])["EnvironmentSeed"].nunique()
    require((seed_counts == 1).all(), "Paired algorithms received different environment seeds.")
    unsatisfied = slot["OfferedTasks"] - slot["SatisfiedCount"]
    causes = slot[["MemoryBlockCount", "IntrinsicLatencyBlockCount", "SpilloverBlockCount", "FeasibleMissedCount"]].sum(axis=1)
    require(np.array_equal(unsatisfied.to_numpy(), causes.to_numpy()), "Failure causes do not partition unsatisfied tasks.")
    checks.append("V9 formal 120000-slot completeness, unique keys, paired seeds, and failure partition")

    # Calibration/formal separation.
    calibration = pd.read_csv(
        RESULTS / "SELECTORV9CALIBRATIONAUDIT2_FIXED5" / "Replay_RunLevel_Merged.csv"
    )
    require(set(calibration["Run"].unique()) == {6, 7, 8, 9, 10}, "Calibration runs are not 6--10.")
    require(set(calibration["Run"]).isdisjoint(set(run["Run"])), "Calibration and formal runs overlap.")
    checks.append("Calibration runs 6--10 are disjoint from formal runs 11--30")

    # Key selector-v9 claims.
    pair = pd.read_csv(v9_root / "Replay_ALM_Paired.csv")
    def paired_row(n: int, comparator: str) -> pd.Series:
        rows = pair[(pair["N"] == n) & (pair["Comparator"] == comparator) & (pair["Metric"] == "MeanSat")]
        require(len(rows) == 1, f"Missing paired MeanSat row for N={n}, comparator={comparator}")
        return rows.iloc[0]

    n240_alm = paired_row(240, "ALM")
    n270_alm = paired_row(270, "ALM")
    n270_ga = paired_row(270, "GAHybrid")
    n300_alm = paired_row(300, "ALM")
    n300_ga = paired_row(300, "GAHybrid")
    close(float(n240_alm["MeanAdvantageALM"]), -0.003, tol=0.001)
    close(float(n270_alm["MeanAdvantageALM"]), 9.814, tol=0.001)
    require(int(n270_alm["Wins"]) == 17 and float(n270_alm["PHolm"]) < 0.05,
            "N=270 v9-vs-ALM confirmatory claim failed.")
    close(float(n270_ga["MeanAdvantageALM"]), 2.603, tol=0.001)
    require(float(n270_ga["PHolm"]) >= 0.05, "N=270 v9-vs-GA unexpectedly passes Holm correction.")
    close(float(n300_alm["MeanAdvantageALM"]), -0.950, tol=0.001)
    close(float(n300_ga["MeanAdvantageALM"]), -6.785, tol=0.001)
    checks.append("V9 neutral N=240, transition rescue N=270, and failure N=300 claims")

    # Fully unseen N=300 replication. Keep it separate from the formal runs above.
    replication_root = RESULTS / "SELECTORV9N300REPLICATION_FIXED5"
    replication_slot = pd.read_csv(replication_root / "Replay_SlotLevel_Merged.csv")
    replication_run = pd.read_csv(replication_root / "Replay_RunLevel_Merged.csv")
    require(len(replication_slot) == 40_000, f"Expected 40000 replication slot rows, found {len(replication_slot)}")
    require(len(replication_run) == 80, f"Expected 80 replication run rows, found {len(replication_run)}")
    require(set(replication_slot["N"].unique()) == {300}, "Replication contains a scale other than N=300.")
    require(set(replication_slot["Run"].unique()) == set(range(31, 51)), "Replication is not runs 31--50.")
    require(set(replication_slot["Algorithm"].unique()) == expected_algorithms,
            "Replication algorithm set is incomplete.")
    require(not replication_slot.duplicated(key).any(), "Duplicate replication slot key detected.")
    replication_sizes = replication_slot.groupby(["N", "Run", "Algorithm"]).size()
    require((replication_sizes == 500).all(), "A replication run/algorithm does not contain 500 slots.")
    replication_seed_counts = replication_slot.groupby(["N", "Run", "Slot"])["EnvironmentSeed"].nunique()
    require((replication_seed_counts == 1).all(), "Replication algorithms received different environment seeds.")
    require(set(replication_run["Run"]).isdisjoint(set(run["Run"])),
            "Formal and replication runs overlap.")
    replication_unsatisfied = replication_slot["OfferedTasks"] - replication_slot["SatisfiedCount"]
    replication_causes = replication_slot[
        ["MemoryBlockCount", "IntrinsicLatencyBlockCount", "SpilloverBlockCount", "FeasibleMissedCount"]
    ].sum(axis=1)
    require(np.array_equal(replication_unsatisfied.to_numpy(), replication_causes.to_numpy()),
            "Replication failure causes do not partition unsatisfied tasks.")

    replication_pair = pd.read_csv(replication_root / "Replay_ALM_Paired.csv")
    def replication_row(comparator: str) -> pd.Series:
        rows = replication_pair[(replication_pair["N"] == 300) &
                                (replication_pair["Comparator"] == comparator) &
                                (replication_pair["Metric"] == "MeanSat")]
        require(len(rows) == 1, f"Missing replication MeanSat row for comparator={comparator}")
        return rows.iloc[0]

    replication_alm = replication_row("ALM")
    replication_ga = replication_row("GAHybrid")
    close(float(replication_alm["MeanAdvantageALM"]), -0.794, tol=0.001)
    close(float(replication_alm["CI95Low"]), -1.471, tol=0.001)
    close(float(replication_alm["CI95High"]), -0.116, tol=0.001)
    require(float(replication_alm["PHolm"]) >= 0.05,
            "Replication v9-vs-ALM unexpectedly passes Holm correction.")
    close(float(replication_ga["MeanAdvantageALM"]), -1.761, tol=0.001)
    require(float(replication_ga["CI95Low"]) < 0 < float(replication_ga["CI95High"]),
            "Replication v9-vs-GA confidence interval no longer crosses zero.")
    checks.append("Independent N=300 runs 31--50 completeness, separation, pairing, and bounded replication claims")

    # Manuscript-facing strings prevent silent number drift after editing.
    text = manuscript_text()
    required_claims = [
        "0.72--5.28",
        "33.45\\% to 46.41\\%",
        "120,000 slot rows and 240 run rows",
        "runs 6--10",
        "runs 11--30",
        "9.81",
        "2.60-point advantage",
        "2.13\\% satisfaction",
        "runs 31--50",
        "below M-CA-ALM by 0.79 points",
        "below GA-Hybrid by 1.76 points",
    ]
    missing = [claim for claim in required_claims if claim not in text]
    require(not missing, f"Manuscript is missing audited claims: {missing}")
    checks.append("Manuscript contains all audited rounded claims and protocol identifiers")

    report = [
        "# MCA Manuscript Evidence Audit",
        "",
        "Status: **PASS**",
        "",
        "## Checks",
        "",
        *[f"- PASS: {item}" for item in checks],
        "",
        "## Boundary",
        "",
        "This audit verifies internal consistency and evidence partitioning. It does not establish external validity, causal resource attribution, or hardware generalization.",
    ]
    OUT.write_text("\n".join(report), encoding="utf-8")
    print(f"MCA MANUSCRIPT AUDIT PASS: {len(checks)} checks; report={OUT}")


if __name__ == "__main__":
    main()
