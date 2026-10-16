# Outcome-Aligned Fog Placement: Strict V2 and 500-Slot Replay

Version 2026-10-16. This package accompanies the manuscript PDF/source in `manuscript/` and contains the versioned code and synthetic experiment artifacts cited in the manuscript's Data Availability statement. No measured device traces are included.

Public release: [GitHub repository folder](https://github.com/dpy3/A-User-Satisfaction-Oriented-Task-Segmentation-Scheme-for-Joint-Communication-and-Task-Offloading/tree/main/Cluster_Computing_Reproducibility_2026-10-16). The adjacent ZIP is the same release; verify it with the supplied SHA-256 manifest.

## Contents

- `manuscript/`: the 20-page PDF, LaTeX source, bibliography, and Springer class/style files.
- `code/`: MATLAB/Python implementation snapshot, dependencies, analysis and validation scripts, and formal run records.
- `data/STRICT_V2/`: 720 factorial run records (six loads, 30 paired environments per load, four arms), paired contrasts, and protocol notes.
- `data/OFFLINEGNN/`: run-level output and frozen checkpoint for the internal comparator; descriptive only.
- `data/REPLAY_500_SLOT/`: merged 60,000 method-slot rows, independent run-level recomputation, summaries, paired descriptive contrasts, nine checkpoint snapshots, and audit/configuration records. Original shard CSV exports were not retained in the final folder; the merged exports and checkpoint comparison are supplied.
- `audit/`: citation-claim, replay/evidence, companion-study file-overlap, and targeted primary-run numerical cross-check records. The cross-study numeric check is deliberately scoped and does not certify that every derived result is independent.

## Reproduction

Use MATLAB with Statistics and Machine Learning Toolbox for the formal experiment and replay; use Python 3 with NumPy, pandas, SciPy, and Matplotlib as needed by the included analysis scripts. Add `code/` and its subfolders to the MATLAB path and read the protocol notes before rerunning; formal runs are computationally intensive.

The replay can be audited without rerunning: it contains 60,000 rows in 120 N/run/method groups of 500 consecutive slots. See the independent audit under `data/REPLAY_500_SLOT/`.

## Evidence boundaries

The static factorial experiment and retry-state replay are distinct protocols. The replay is not an equal-compute comparison and every method reaches the queue cap in every N=300 run. Hardware profiles are synthetic and uncalibrated; replay latency allowances do not age while tasks wait. The OfflineGNN checkpoint was selected under an earlier pipeline and is descriptive only. The manuscript contains tables and no embedded figures.
