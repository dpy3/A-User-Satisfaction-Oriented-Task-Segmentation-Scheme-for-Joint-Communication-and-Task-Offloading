# Companion-study numeric cross-check (2026-10-16)

## Scope and source records

This targeted check compares the primary formal run-level evidence in the two currently available releases. It supplements, but does not replace, the file-hash comparison in `COMPANION_STUDY_OVERLAP_CHECK_2026-10-16.md`.

| Item | PMC companion study | Cluster Computing study |
|---|---|---|
| Run-level source | `Paper2_PMC_Reproducibility_2026-08-03/data/FORMAL_V2/Paper2_Revision_RunLevel.csv` | `data/STRICT_V2/Strict_RunLevel_R1to10.csv`, `R11to20.csv`, `R21to30.csv` |
| Records | 360 | 720 |
| Design | 3 persistent-hotspot scenarios × 4 algorithms × 30 paired seeds; N=180; 200 slots | 6 task loads (N=120, 150, 180, 200, 250, 300) × 4 factorial arms × 30 runs; static placement evaluation |
| Main outcome field | `MeanSatisfaction` | `Sat` |
| Seed fields | `Seed` | `EnvironmentSeed` and `SolverSeed` |

The PMC run-level source is distributed in the separate `Paper2_PMC_Reproducibility_2026-08-03` data release. Its SHA-256 is `b99ec73f656118bdeB2CEC627A52274E8D23EE4EC37EF9CB0E2FB3E3FFD20ECC` (case-insensitive). The Cluster CSV source files are bound by this release's `CHECKSUMS_SHA256.txt`.

The papers ask different questions: the PMC study evaluates persistent-hotspot reconfiguration, migration counts and a migration-volume proxy; the Cluster study evaluates repair-aware versus raw candidate ranking, local-heuristic behavior, and a separate retry-state replay. Both use synthetic experiments and share 20 byte-identical code components, including simulator/environment, hardware-profile and comparator files. That shared implementation is material and should be disclosed; it does not by itself establish that the reported outcomes are duplicated.

## Checks and findings

- Seed-token comparison across every seed-bearing CSV in the PMC data release (12 files) and every seed-bearing Cluster CSV in this release (6 files) found no shared token. The narrower primary-formal comparison likewise has no intersection.
- Restricting the Cluster primary formal records to N=180 yields 120 rows (four arms × 30 runs). None of their exact stored `Sat` values equals any of the 360 exact PMC `MeanSatisfaction` values.
- Across all six Cluster loads, one exact scalar value, 39.2, occurs in two Cluster rows (N=250, `RepairLocalOff` and `RepairLocalOn`) and in one PMC row (N=180, `link_hotspot`, `BigMECGreedy`, run 20). These are not matched load, run, seed, scenario, or method conditions. A coincident scalar is not evidence of copied data; it is recorded here so it is not hidden or overinterpreted.
- The four Cluster N=180 arm means (27.1852, 25.7963, 38.0000, 38.0000%) do not exactly equal any of the 12 PMC scenario-by-algorithm means computed from the 360 formal records.
- The data directories contain no byte-identical data files, as separately reported in the file-hash audit.

## Interpretation limits and action

This is a targeted exact-value comparison of the primary formal run-level satisfaction field and its unrounded arm/scenario means. It does not establish global numerical independence, inspect every sensitivity/onset/ablation output pair, or rule out transformed, aggregated, or manually transcribed reuse. The two papers share code and some synthetic profile inputs. Before submission, authors must confirm the provenance of every reported table/figure value against the source data for both manuscripts and disclose the companion manuscript and shared implementation to the editor. Do not state that no cross-paper result reuse exists solely on the basis of this check.
