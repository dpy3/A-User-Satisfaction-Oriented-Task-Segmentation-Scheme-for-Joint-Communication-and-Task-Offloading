# Paper 1 Freeze Scope

## Canonical source

The canonical Paper 1 source is this IEEEtran `official_v11` package. The title
and research identity are `Outcome-Aligned Memetic Optimization for Feasible DNN
Offloading in Heterogeneous Fog Networks` and M-CA-ALM, respectively.

## Supported claims

- Repair-aware phenotype ranking aligns evolutionary selection with the repaired
  schedule that is actually evaluated and deployed.
- In the frozen five-node benchmark, the supported benefit is bounded to
  recoverable congestion and the reported transition-overload setting.
- Static, factorial-ablation, replay, held-out v9, and independent replication
  claims are limited to their stated seeds, scales, and simulator.
- Bottleneck counts are diagnostic outcome partitions, not causal evidence for a
  physical intervention.

## Forbidden additions during freeze

- HIVE or another paper identity.
- Capacity normalization, capacity scaling, autoscaling, or capacity co-design.
- A new admission-control method.
- A second repair operator or a new optimization objective.
- Cross-infrastructure, online-stability, or deployment claims.

## Completed evidence gates

1. Cross-algorithm repair-transfer validation passed its independent GA-family gate.
2. A split-isolated OfflineGNN was added as a baseline, not a contribution.

The only remaining gate is the final terminology, number, citation, reference, and
LaTeX consistency audit.

Failure of a remaining gate weakens or removes the corresponding claim; it does
not authorize expansion of the research question.
