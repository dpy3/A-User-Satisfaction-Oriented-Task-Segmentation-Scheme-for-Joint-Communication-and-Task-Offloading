# Current manuscript evidence audit (2026-10-16)

The release-facing audit passed against the versioned current exports.

- Strict V2: 720 rows, four arms, six loads, 30 paired runs per load.
- Repair-aware minus raw/local-off mean gain range: 8.82--29.83 percentage points.
- Every arm used exactly 10,000 candidate-score calls; final resource violations and changed integer genes were zero.
- Replay: 60000 rows in 120 groups of 500 slots; queue conservation and unique keys passed.
- The replay is a separate synthetic retry-state protocol and is not treated as an equal-compute comparison or queue-stability test.
- Historical result directories are intentionally excluded from this audit.
