# Capacity-normalized phase and co-design protocol

## Frozen algorithm boundary

Greedy, GA-Hybrid, M-CA-ALM, M-CA-ALM-v9, shared feasibility repair, and post-optimization retain their existing implementations and parameters. Infrastructure experiments alter only the `Fog` resource matrix before `build_pre_struct_tier1` is called. Code manifests and frozen MATLAB configs are written into every result package.

## Infrastructure profiles

- `balanced`: original two Nano, two Pi, and one cloud composition.
- `compute_bound`: compute resources scaled to 0.15 and memory scaled to 2.0; the calibration LP is compute-active on all five nodes.
- `memory_bound`: memory scaled to 0.35; the calibration LP is memory-active on all five nodes.
- `latency_filtered`: bandwidth scaled to 0.005; calibration excludes type-node paths whose mean intrinsic latency exceeds the type deadline.
- `edge_rich`: one Pi node is replaced by one Nano node, yielding three Nano, one Pi, and one cloud node.

## Capacity denominator

For each profile, a separate calibration sample estimates the largest composition-preserving batch `C_profile` under the simulator's compute-load, memory, and intrinsic-latency constraints. The LP fixes the expected task mix at 40% VGG16, 30% ResNet50, and 30% MobileNet. It is independent of all tested scheduling policies.

The replay load axis is

`lambda = N / C_profile`,

where the integer arrival count is frozen as `N = round(lambda * C_profile)`. The realized ratio is exported for every slot.

## Evidence separation

- Capacity calibration: runs 51--55, sample size 3000, used only to freeze `C_profile`.
- Phase discovery pilot: runs 56--60, 100 slots, `lambda={0.55,0.70,0.85,1.00,1.15}`.
- Smoke packages: implementation validation only; never pooled with pilot or formal evidence.
- Confirmatory runs: must use new run indices selected only after the pilot grid and co-design parameters are frozen.

## Admission/capacity factorial

The 2x2 system intervention keeps the M-CA-ALM-v9 search path frozen:

- `ALMv9`: no system intervention.
- `ALMv9Admission`: admits new arrivals up to `0.85*C_profile`; rejected arrivals remain in the offered-task denominator.
- `ALMv9Capacity`: evaluates the same base-profile schedule with a 1.25 deployment-resource multiplier.
- `ALMv9CoDesign`: applies both interventions; the admission limit remains `0.85*C_profile` and is not relaxed by the capacity multiplier.

Admission rejects, queue-cap drops, elastic resource slot-units, and bottleneck-resolved failures are exported separately. The accounting identity is

`offered = satisfied + admission rejects + memory blocks + intrinsic-latency blocks + spillover blocks + feasible misses`.

## Claim guardrails

- A profile name describes its calibrated constraint geometry; it is not a claim about every slot's causal failure.
- Bottleneck counts are diagnostic partitions, not physical causal identification.
- Pilot results locate transition cells and calibrate interventions; they are not confirmatory evidence.
- Capacity benefits must be reported with elastic-resource cost. Admission benefits must retain rejected tasks in the denominator.
