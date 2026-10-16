# M-CA-ALM Official Evidence Pipeline

This directory is the only 2026 evidence track intended for future manuscript claims.
Historical result folders remain untouched and are not accepted as evidence here.

## Evidence classes

- AUDIT: deterministic metric and feasibility checks only.
- SMOKE: runner integration checks only; never cite or export to manuscript macros.
- PILOT: congestion and discriminability checks only; never cite as final evidence.
- BUDGETPILOT: equal population/generation diagnostic; never cite as final evidence.
- GUARDPILOT: monotone local-search acceptance diagnostic; never cite as final evidence.
- SELECTORPILOT: repair-aware, diversity-preserving elite selection diagnostic.
- SELECTOREFFICIENTPILOT: lower-budget repair-aware selector diagnostic.
- SELECTORFORMAL: frozen MCA-OFFICIAL-1.1 repair-aware selector evidence.
- ABLATIONFORMAL: paired 2x2 mechanism ablation over guard and repair-aware ranking.
- BASELINEFORMAL: matched static comparison with LP relaxation, DPP, and MPC.
- FORMAL: frozen configuration, run-level observations, and SHA-256 manifest.

## Metric semantics

- Satisfaction: admitted, deadline-timely, and free of resource violation.
- Admission: exactly one positive assignment in a task row.
- Resource violation: assigned node exceeds memory capacity or queue load rho >= 0.99.
- Deadline violation: dropped task or admitted task whose modeled latency exceeds its deadline.
- Composite violation: resource OR deadline violation. Under these binary definitions,
  composite_violation = 100 - satisfaction; it is not an independent safety claim.

## Commands

    cd('.../Reproducibility_Package_2026-10-15/code')
    Run_MCA_Metric_Audit
    Run_MCA_Official_Static('smoke')
    Run_MCA_Official_Replay('smoke')
    Run_MCA_Official_Static('pilot')
    Run_MCA_Official_Ablation('ablationsmoke')
    Run_MCA_Official_Ablation('ablationformal')
    Analyze_MCA_Official_Ablation('ablationformal')
    Run_MCA_Official_Static('baselineformal')
    Analyze_MCA_Official_Static('baselineformal')
    Analyze_MCA_Official_Baselines('baselineformal')

Formal static experiments use 30 paired seeds at
N=[80,100,120,150,180,200,250,300]. Formal replay uses 500 slots,
20 run-level replicates, and N=[180,300]; it supports run sharding, e.g.
Run_MCA_Official_Replay('formal',1:2,180).
The primary load-scaling experiment keeps the five-node infrastructure fixed;
capacity scaling must be reported as a separate sensitivity study.

The replay carries unresolved task and user rows into the next slot. This replaces
the historical count-only backlog approximation, which regenerated different tasks
and could not support a claim about task-level queue evolution.

Replay shard names include both scale and run range. Checkpoints persist backlog
state and can resume a partial run without regenerating completed slots.

    Run_MCA_Official_Replay('selectorformal', 1:2, 180)
    Merge_MCA_Official_Replay('selectorformal', false) % partial audit only
    Merge_MCA_Official_Replay('selectorformal', true)  % requires all 40 runs
    Analyze_MCA_Official_Replay('selectorformal')      % refuses partial evidence
    Check_MCA_Replay_Status('selectorformal')
    Finalize_MCA_Official_Replay('selectorformal')     % merge + validate + analyze

No script in this directory writes LaTeX macros. Manuscript claims may be revised
only after all formal shards are merged and independently validated.

The ablation is a paired 2x2 design. All four variants use identical environments,
solver random streams, final repair, and post-optimization. Formal ablation results
are citable only after all 30 runs at every congested scale pass validation.
The common solver stream is the same `seed+3000` stream used by ALM in
SELECTORFORMAL, so the ALMFull rows must reproduce the main-table ALM rows exactly.
The environment seed uses the fixed eight-scale reference index even when an
auxiliary experiment runs only congested scales.
