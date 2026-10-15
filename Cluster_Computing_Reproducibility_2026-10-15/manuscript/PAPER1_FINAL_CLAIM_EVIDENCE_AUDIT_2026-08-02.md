# Paper 1 final claim--evidence audit (2026-08-02)

## Reviewer-driven revisions completed

| Reviewer risk | Revision made | Evidence boundary |
| --- | --- | --- |
| Static and replay numbers could be read as one pooled experiment. | Static, replay, held-out v9, and independent transfer tiers are explicitly separated in the Introduction and Experimental Evaluation. | No cross-tier pooled estimate is reported. |
| Recoverable congestion and overload boundary were not operationally defined. | The Introduction defines recoverable congestion, transition regime, and immediate-overload boundary using backlog-cap behavior. | Definitions apply to the fixed-capacity replay only. |
| Repair-aware algorithm order was underspecified. | Algorithm section now states genotype construction, temporary repaired phenotype scoring, non-Lamarckian preservation, guarded ALM child acceptance, and elite-only final repair. | Scope is the deterministic Safe Harbor repair operator. |
| Learned baseline split could be mistaken for leakage. | Train runs 51--55, selection runs 61--63, and official test runs 1--30 are stated as disjoint; test environments never update parameters. | OfflineGNN remains one internally trained comparator, not a published or universal learned comparison. |
| Repair-transfer claim was too broad. | Discussion limits transfer to the two tested evolutionary families under the tested Safe Harbor repair operator. | No claim for arbitrary optimizers or repair operators. |

## Final claim--evidence map

| Claim | Evidence | Status |
| --- | --- | --- |
| Repair-aware ranking improves the deployed outcome in recoverable static congestion. | 30 paired seeds at each congested scale; factorial ablation and Holm-corrected paired tests. | Supported within the frozen five-node simulator. |
| The effect transfers beyond ALM. | Independent runs 31--50 comparing raw and repair-aware GA-Hybrid with identical streams and final repair. | Supported for the tested GA family and repair operator. |
| The method persists better under dynamic replay at N=180. | Separate 20-pair, 500-slot state-preserving replay. | Supported only at N=180 and the specified replay. |
| Immediate saturation is a negative boundary. | N=300 replay and independent v9 runs 31--50. | Supported as an operating boundary, not as a universal impossibility result. |
| OfflineGNN is a leakage-free learned comparator. | Disjoint training/selection/test run partitions and frozen parameters. | Supported as one internal comparator policy; no literature claim is made. |

## Remaining author actions

- Replace author metadata, declarations, and repository placeholder before upload.
- Regenerate the package checksum and submission archive after the final PDF is compiled.

## Canonical static source

The static satisfaction and additional-baseline tables are taken from
`data/BASELINEFORMAL_FIXED5/Static_Summary_Official.csv` and its paired
analysis files. The mechanism-ablation, repair-transfer, and learned-comparator
tables use their correspondingly named frozen packages. The similarly named
`data/FORMAL_FIXED5/` directory is a historical selector-pipeline diagnostic
with different ALM means; it is not a source for the manuscript's main static
claims. This mapping prevents an otherwise reproducible-data ambiguity.
