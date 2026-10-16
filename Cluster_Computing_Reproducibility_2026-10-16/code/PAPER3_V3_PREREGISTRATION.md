# Paper 3 V3 Pre-registration

## Motivation and frozen boundary

PILOT3 failed because LyapunovMRv2 used less intervention than FixedMatchedV2
but delivered lower mean satisfaction in all three profiles. Runs 11--15 are
failure evidence only and are prohibited for parameter fitting, threshold
selection, or repeated validation. V1, v2, PILOT, PILOT2, and PILOT3 artifacts
remain unchanged.

## V3 hypothesis

`LyapunovMRv3` is a service-safe drift-plus-penalty controller. At every slot it
constructs the same action-specific gains and full-capacity anchor used by the
frozen `FixedMatchedV2` comparator.

1. If no full-capacity action has positive modeled gain, select no action.
2. If the SLA virtual queue is positive, select the best full-capacity anchor.
3. If the SLA virtual queue is zero, consider only no-rejection actions whose
   modeled gain is machine-equivalent to or greater than the anchor, then select
   the lowest drift-plus-penalty cost action.

Machine equivalence is `16*eps(max(1,abs(anchor_gain)))`; it is a numerical
precision rule, not a calibrated scientific threshold. No new controller weight
or empirical tolerance is introduced.

## Frozen validation

- Profiles and loads: compute-bound 0.55, memory-bound 1.00,
  latency-communication-isolated-v3 0.05
- Capacity and SLA references: unchanged from PILOT3
- Policies: NoAction, FixedMatchedV2, MPCMRV2, LyapunovMRv3
- Smoke6: runs 205--206, 20 slots
- Pilot4: runs 16--20, 100 slots
- Per-slot intervention cap: 0.25
- Strict profile gate: Lyapunov satisfaction no worse than NoAction and
  FixedMatchedV2, and Lyapunov cost no greater than FixedMatchedV2
- Overall gate: all three profiles must pass

Smoke6 is limited to static checks, zero violations, budget compliance, no
Lyapunov admission, intended resource actions, and evidence that both the full
anchor and service-equivalent lower-cost branch are executable. Smoke6 effect
sizes cannot change the controller. Pilot4 starts only after the hard smoke gate.
If PILOT4 is not 3/3, formal experiments, drift-bound work, and manuscript writing
remain locked and v3 stops without tuning on runs 16--20.
