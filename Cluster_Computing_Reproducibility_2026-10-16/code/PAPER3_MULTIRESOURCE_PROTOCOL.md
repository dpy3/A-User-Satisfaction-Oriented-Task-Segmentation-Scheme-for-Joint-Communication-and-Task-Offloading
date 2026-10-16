# Paper 3 Multi-Resource Matched-Control Protocol

The control state has four observable pressures: compute, memory, communication,
and backlog. Every adaptive policy receives the same arrivals, pending work,
resource profile, repair, and evaluation.

The per-slot intervention budget is 0.25 normalized cost units. Available actions
are no action, reject at most 25% of new arrivals, boost only the currently most
pressured resource by 25%, or split the budget between a 12.5% targeted boost and
at most 12.5% admission rejection. This prevents a hybrid policy from receiving
more intervention than a single-action comparator.

The Lyapunov cost queue uses an average target of 0.125 cost units per slot,
strictly below the 0.25 per-slot action cap. Candidate scores also include the
direct service loss from admission rejection; rejection cannot be treated only
as a pressure reduction because rejected arrivals remain unsatisfied demand in
the reported service metric.

`LyapunovMR` is the proposed stateful controller. It uses SLA and intervention-cost
virtual queues. The feasible SLA target for each profile/load cell is read from
the frozen capacity-phase ALMv9 result on calibration runs 56--60; a single
cross-profile target is prohibited because it may lie outside a profile's
feasibility region. `MPCMR` uses the same action set and a three-step pressure forecast.
`FixedMatched` uses the same budget but a fixed pressure trigger. `NoAction` is the
frozen scheduler without system intervention.

Smoke and pilot modes establish only implementation validity and action
discriminability. They cannot support superiority or stability claims. Formal
experiments require new seeds, pre-transition/transition/extreme cells for every
profile, paired statistics, explicit resource-cost reporting, and a separate
Lyapunov drift-bound statement whose assumptions match the implemented queues.

The frozen pilot is exactly five runs and 100 slots for each of the three
profiles. It may be executed as one checkpointed shard per profile to reduce wall
time. Sharding must preserve the global profile identifier in the seed formula;
the merger rejects duplicate keys, missing runs, and any row whose slot count is
not 100.

The first five-run pilot uses runs 1--5. If it exposes an invalid queue
assumption, a revised controller must be checked on fresh pilot-validation runs
6--10 (`PILOT2`), never by overwriting or reusing runs 1--5. Formal experiments
remain prohibited unless every profile in the fresh validation meets both the
service gate (Lyapunov no worse than NoAction and FixedMatched) and the matched
cost gate (Lyapunov cost no greater than FixedMatched).

`PILOT2` on runs 6--10 failed the latency-filtered service gate and is frozen.
The original `LyapunovMR` source path must remain available for its reproduction.
The only admissible next controller is a versioned `LyapunovMRv2` that replaces
cross-resource raw-pressure ranking with action-specific rescue/relief estimates.
It must assign direct loss to rejected demand, select no action when no candidate
has positive drift-plus-penalty value, and record action/resource counts. Parameter
search on runs 6--10 is prohibited. After code-level smoke checks, a new gate uses
runs 11--15 (`PILOT3`) and the same 100-slot, four-policy, matched-budget protocol.
Formal work remains locked unless all three `PILOT3` profile gates pass.

The v2 smoke action gate subsequently failed: the existing `latency_filtered`
cell did not produce a discriminable bandwidth action, and `PILOT3` was not
launched. The third profile must now be versioned and independently recalibrated
before runs 11--15 are used. Controller-weight tuning against any of the smoke
or pilot runs is prohibited.

The versioned `latency_comm_isolated_v3` profile passed independent capacity,
resource-discriminability, load, and SLA calibration. After a fresh smoke5 hard
gate, `PILOT3` was executed on runs 11--15 and failed the strict gate in all
three profiles (`PilotGate=false`). The v2 protocol is therefore stopped. Formal
experiments, drift-bound work, and Paper 3 manuscript claims remain prohibited;
runs 11--15 must not be used for controller or baseline tuning.

A separately pre-registered service-safe `LyapunovMRv3` was then checked on
fresh smoke6 runs 205--206 and PILOT4 runs 16--20. PILOT4 completed 60/60 rows
without resource, budget, admission, or resource-action violations, but passed
only the memory profile. Compute missed FixedMatchedV2 by 0.0136 percentage
points and latency-communication-v3 by 1.1458 percentage points on mean
satisfaction; the overall gate was 1/3 (`PilotGate=false`). V3 is therefore
stopped. Formal experiments and manuscript work remain locked, and runs 16--20
must not be used for further controller tuning.
