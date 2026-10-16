"""Audit the current Cluster Computing release against its manuscript claims.

This script reads only the versioned Strict V2 and 500-slot replay exports
shipped with the 2026-10-16 release. Historical result directories are not
interpreted as current evidence.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
OUT = ROOT / "audit" / "MANUSCRIPT_EVIDENCE_AUDIT_2026-10-16.md"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    strict_files = sorted((DATA / "STRICT_V2").glob("Strict_RunLevel_*.csv"))
    require(len(strict_files) == 3, "The three Strict V2 shard files are required.")
    strict = pd.concat((pd.read_csv(path) for path in strict_files), ignore_index=True)

    expected_arms = {"RawLocalOff", "RawLocalOn", "RepairLocalOff", "RepairLocalOn"}
    require(len(strict) == 720, f"Expected 720 Strict V2 rows, found {len(strict)}.")
    require(set(strict["Algorithm"]) == expected_arms, "Strict V2 arm set is incomplete.")
    require(set(strict["N"]) == {120, 150, 180, 200, 250, 300}, "Strict V2 loads are incomplete.")
    require(set(strict["Run"]) == set(range(1, 31)), "Strict V2 run identifiers are incomplete.")
    require(not strict.duplicated(["N", "Run", "Algorithm"]).any(), "Duplicate Strict V2 keys.")
    require((strict["CandidateScoreBudget"] == 10000).all(), "Score-call budget is not 10,000 in every arm.")
    require((strict["ScoreCalls"] == 10000).all(), "Realized score calls are not exactly 10,000.")
    require((strict["ResourceViolation"] == 0).all(), "A final Strict V2 row has a resource violation.")
    require((strict["ChangedLocalGenes"] == 0).all(), "A local update changed an integer gene.")
    for arm in expected_arms:
        require((strict["Algorithm"] == arm).sum() == 180, f"Arm {arm} is not 180 rows.")

    pivot = strict.pivot_table(index=["N", "Run"], columns="Algorithm", values="Sat")
    repair_gain = pivot["RepairLocalOff"] - pivot["RawLocalOff"]
    means = repair_gain.groupby(level=0).mean()
    require(round(float(means.min()), 2) == 8.82, "Minimum repair-aware gain does not match the manuscript.")
    require(round(float(means.max()), 2) == 29.83, "Maximum repair-aware gain does not match the manuscript.")

    replay = pd.read_csv(DATA / "REPLAY_500_SLOT" / "Replay_SlotLevel_60000.csv")
    require(len(replay) == 60000, f"Expected 60,000 replay rows, found {len(replay)}.")
    require(set(replay["N"]) == {180, 300}, "Replay loads are incomplete.")
    require(set(replay["Algorithm"]) == {"Greedy", "GAHybrid", "ALM"}, "Replay methods are incomplete.")
    group_sizes = replay.groupby(["N", "Run", "Algorithm"]).size()
    require(len(group_sizes) == 120 and (group_sizes == 500).all(), "Replay groups are not 120 groups of 500 slots.")
    require(not replay.duplicated(["N", "Run", "Slot", "Algorithm"]).any(), "Duplicate replay keys.")
    conservation = (
        replay["BacklogIn"] + replay["Arrivals"] - replay["SatisfiedCount"]
        - replay["DroppedByQueueCap"] - replay["BacklogOut"]
    )
    require((conservation == 0).all(), "Replay queue conservation failed.")

    summary = pd.read_csv(DATA / "REPLAY_500_SLOT" / "Replay_Summary_ByScale.csv")
    require(len(summary) == 6, "Replay summary does not contain six method/load rows.")
    n300 = summary[summary["N"] == 300]
    require((n300["mean_final_backlog"] == 300).all(), "Not every N=300 run summary reaches the queue cap.")

    OUT.write_text(
        "# Current manuscript evidence audit (2026-10-16)\n\n"
        "The release-facing audit passed against the versioned current exports.\n\n"
        f"- Strict V2: {len(strict)} rows, four arms, six loads, 30 paired runs per load.\n"
        f"- Repair-aware minus raw/local-off mean gain range: {means.min():.2f}--{means.max():.2f} percentage points.\n"
        "- Every arm used exactly 10,000 candidate-score calls; final resource violations and changed integer genes were zero.\n"
        f"- Replay: {len(replay)} rows in {len(group_sizes)} groups of 500 slots; queue conservation and unique keys passed.\n"
        "- The replay is a separate synthetic retry-state protocol and is not treated as an equal-compute comparison or queue-stability test.\n"
        "- Historical result directories are intentionally excluded from this audit.\n",
        encoding="utf-8",
    )
    print(f"PASS: wrote {OUT}")


if __name__ == "__main__":
    main()
