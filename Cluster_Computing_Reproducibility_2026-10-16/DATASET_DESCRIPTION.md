# Dataset Description

## Dataset title

Outcome-Aligned Fog Placement: Strict V2 and 500-Slot Replay

## Associated code and data package

Outcome-Aligned Fog Placement: Strict V2 and 500-Slot Replay (version 2026-10-16)

## Contents

- 720 run-level Strict V2 factorial records across six loads, 30 paired environments per load, and four experimental arms.
- Run-level output for a frozen internal OfflineGNN comparator, reported descriptively.
- 60,000 method-slot records from the 500-slot retry-state replay, 120 recomputed run summaries, scale summaries, and descriptive paired contrasts.
- Nine checkpoint snapshots, frozen replay configuration, independent recomputation and audit records, MATLAB/Python code, manuscript source/PDF, and SHA-256 checksums.

## Data generation and limitations

All task, network, and hardware profiles are simulator-generated and synthetic. No measured device traces or empirical hardware calibration are included. Static Strict V2 and the retry-state replay are different protocols. The replay does not use deadline aging while tasks wait and reaches the queue cap under every N=300 run; it should not be interpreted as evidence of stable queues or deployment performance.

## Reproducibility

See `README.md`, `ENVIRONMENT.md`, the protocol notes under `code/`, and the audit records under `data/REPLAY_500_SLOT/` and `audit/`. `CHECKSUMS_SHA256.txt` lists the digest of every file in this package except the checksum index itself.
