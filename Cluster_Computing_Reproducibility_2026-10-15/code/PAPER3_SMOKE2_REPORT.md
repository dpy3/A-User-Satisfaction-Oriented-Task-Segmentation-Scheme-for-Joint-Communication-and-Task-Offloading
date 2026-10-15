# Paper 3 Multi-Resource Controller Diagnostic Report

## Status

The first smoke run failed the controller-discriminability test in all three
profiles. It is retained under `Results/MULTIRESOURCE_SMOKE` and is not evidence
for a manuscript claim.

The failure exposed two objective-contract defects:

1. admission rejection reduced forecast pressure without charging its direct
   loss in the offered-task satisfaction metric; and
2. the virtual cost queue used the per-slot maximum action budget as its average
   target, so it could never grow, while the action score penalized only cost
   above the same unreachable maximum.

The corrected controller adds a direct rejection penalty, uses an average cost
target of 0.125 below the 0.25 per-slot cap, and charges the virtual cost queue
for actual intervention cost. The revised diagnostic is stored separately under
`Results/MULTIRESOURCE_SMOKE2`.

## Smoke2 Results

| Profile | Lyapunov - NoAction sat. (pp) | Lyapunov - MPC sat. (pp) | Lyapunov - Fixed sat. (pp) | Lyapunov cost | Pilot signal |
|---|---:|---:|---:|---:|---:|
| Compute-bound | +2.75 | -0.06 | +1.58 | 4.44 | Yes |
| Memory-bound | +16.55 | +0.09 | +13.08 | 4.38 | Yes |
| Latency-filtered | +0.37 | +1.96 | +0.43 | 2.94 | Yes |

All post-repair resource-violation and matched per-slot budget assertions pass.
LyapunovMR now exceeds NoAction and FixedMatched in all three diagnostic
profiles. Its difference from MPC is nearly zero in compute- and memory-bound
profiles, so superiority over MPC is not established and must not be claimed.

## Decision

The implementation is sufficiently discriminative to proceed to the frozen
five-run, 100-slot pilot. Smoke2 is diagnostic only. A pilot or formal claim
requires paired seeds, action/cost reporting, and explicit acknowledgement that
MPC remains competitive in two profiles.

## Claim-Evidence Boundary

- Supported as implementation evidence: the revised stateful controller selects
  feasible matched-budget actions and no longer systematically over-rejects.
- Not supported: statistical superiority, long-run stability, cross-load
  generalization, or a Lyapunov performance guarantee.
- Required next: five-run 100-slot pilot, followed by the pre-specified
  multi-load formal design only if the pilot remains positive.
