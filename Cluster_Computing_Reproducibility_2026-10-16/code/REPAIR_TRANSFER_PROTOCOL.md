# Frozen Repair-Transfer Protocol

## Question

Does ranking the phenotype produced by the existing Safe Harbor repair improve
outcomes within a second optimizer family, without changing the repair operator,
search budget, environment, or deployed post-processing pipeline?

This is a validation of the existing repair-aware ranking claim. It is not a new
repair method, capacity study, admission policy, or infrastructure study.

## Arms

The four frozen arms are `GAHybridRaw`, `GAHybridRepairAware`, `ALMRaw`, and
`ALMRepairAware`. Raw and repair-aware arms retain the same unrepaired genotype
for variation. Only the fitness/ranking evaluation changes: the repair-aware arm
scores the temporary phenotype produced by `Perform_Safe_Harbor_Repair`.

All four returned solutions receive the same final Safe Harbor repair and global
post-optimization before evaluation. Post-repair resource violation must be zero.

## Environments and randomization

- Fixed five-node trace-driven benchmark.
- Scales: `N = {120, 150, 180, 200, 250, 300}`.
- Formal independent runs: `31:50`; these do not overlap the original 30 runs.
- Smoke mode: `N = 120`, runs `1:2`, reduced optimizer budgets.
- Each scale/run pair uses one generated environment shared by all four arms.
- GA raw/repair-aware arms reset to `seed + 2000`.
- ALM raw/repair-aware arms reset to `seed + 3000`.
- Formal budgets remain GA `100 x 100` and ALM `50 x 50` with the existing local
  search settings.

The runner checkpoints after every environment and writes a SHA-256 code manifest.

## Confirmatory analysis

The primary unit is an independent run. Within each run and optimizer family,
the repair-aware minus raw satisfaction difference is averaged equally across the
six frozen scales. The family-level report includes the mean paired difference,
95% paired percentile-bootstrap interval, paired Cohen's dz, win/tie/loss counts,
an exact sign-flip test, and Holm correction across the two family tests.

The transfer claim passes only if the independent GA-family effect has:

1. positive mean difference;
2. 95% interval lower bound above zero; and
3. Holm-adjusted sign-flip `p < 0.05`.

Scale-wise effects are secondary and Holm-corrected across all family-scale tests.
If the GA gate fails, the manuscript must not claim cross-algorithm portability,
even if the ALM internal effect remains positive.

## Commands

```matlab
Run_MCA_Repair_Transfer('repairtransfersmoke');
Analyze_MCA_Repair_Transfer('repairtransfersmoke');

Run_MCA_Repair_Transfer('repairtransferformal');
Analyze_MCA_Repair_Transfer('repairtransferformal');
```
