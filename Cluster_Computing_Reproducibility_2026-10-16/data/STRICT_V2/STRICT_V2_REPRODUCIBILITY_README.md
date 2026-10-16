# Strict V2 reproducibility record (working package)

**Status: not a submission release.** The exact-budget factorial study is complete and internally audited. The 500-slot stateful replay is still running; this package intentionally does not present partial replay output as complete evidence. The repository copy, final figures, and final submission archive remain to be synchronized after the replay gate passes.

## Study and claim boundary

The study asks whether an evolutionary search should rank a raw integer task assignment or the phenotype produced by the shared feasibility repair. It does not propose a new augmented-Lagrangian theory. The simulator uses synthetic hardware and workload parameters without device calibration.

Strict V2 uses four arms in the same inherited evolutionary search: raw ranking with local search disabled/enabled, and repaired-phenotype ranking with local search disabled/enabled. Each of 6 loads × 30 paired runs × 4 arms is assigned exactly 10,000 candidate-score calls. All arms share environment and solver seeds. The delivered assignment receives the common feasibility repair; the V2 primary experiment does not apply post-selection polishing.

## Main verified outputs

- `STRICT_V2_ALL_RUNLEVEL.csv`: 720 run/load/arm rows.
- `STRICT_V2_PAIRED_ANALYSIS.json`: paired effects, pointwise confidence intervals, sign-flip tests, Holm adjustments, operation counts, and descriptive timing records.
- `STRICT_V2_FORMAL_PROGRESS.json`: coverage and invariants for the 720-row run.
- `strict_v2_code/`: frozen V2 code and runner.
- `strict_v2_code/Results/STRICT_V2_OFFLINEGNN/OfflineGNN_RunLevel.csv`: 180 paired evaluations of the previously frozen model with shared final repair and reporting. Its checkpoint was selected under the earlier polishing-enabled validation pipeline; this comparison is descriptive, not a newly optimized learned baseline.
- `STRICT_V2_SOURCE_*.json`: actual-byte source hashes for the V2 source tree, excluding generated result files.

The runtime boundary records solver/inference plus final repair and reporting. Because the formal shards ran concurrently with other workloads, elapsed times are retained for audit but are not used as comparative speed claims. Score-call matching does not equate computation: repair-aware ranking performs one repair for each candidate score, while raw ranking repairs only the final output.

## Audit boundaries

The current result files passed internal checks for row coverage, unique keys, paired seeds, exact score-call counts, zero local invocations in disabled arms, metric ranges, and zero final resource violations. These checks do not establish physical calibration, historical source provenance, or generalization beyond the simulator. Historical hash records remain defective and are not retroactively repaired by the V2 snapshot.

The replay target is 60,000 method-slot rows (2 loads × 20 runs × 500 slots × 3 methods). Do not use replay data or describe that experiment as complete until every run has 500 contiguous slots and the audit validates unique keys, seeds, backlog carry-over, cap accounting, and final aggregation.

## Citation review

BibTeX metadata were checked against Crossref records and corrected where discrepancies were confirmed. The unverified firefly reference was removed, together with the sentence that depended on it. Metadata matching does not by itself validate every literature claim; the manuscript explicitly limits its related-work conclusions.

## Rebuild

Compile `LaTeX/main.tex` with the included `references.bib` using the Springer Nature `sn-jnl` template available in the author environment. This working package is not the final synchronized repository or submission ZIP.
