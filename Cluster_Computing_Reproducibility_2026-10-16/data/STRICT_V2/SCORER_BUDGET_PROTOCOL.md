# Candidate scorer-call budget protocol

The corrected primary static comparison matches the main search budget by candidate-scoring calls (the shared admission-aware selector evaluations), then reports full solver wall time separately.

- GA-Hybrid: population 100, 100 generations, one batch score for each individual per generation: 100 x 100 = 10,000 candidate score calls.
- M-CA-ALM: population 100. Initial population evaluation contributes 100 calls. Across 79 generations each individual is scored once if no local search is invoked; when invoked it is scored once before and once after the proposal, so each invocation adds exactly one extra call. Total = 100 + 100 x 79 + L, where L is the observed number of local-search invocations. With probability 0.25, expected L = 1,975 and expected total = 9,975 calls.

The expected budget gap is 25 calls (0.25% of 10,000). It is an expected-call match, not an exact deterministic cap; the realized invocation count is seed-dependent. The comparison also records RuntimeSec, which includes common final repair and randomized polishing. The shared repair/evaluator can cost more for repair-aware candidates, so equal score-call counts do not imply equal wall time. A strict real-time deadline remains outside the simulator.

The ALM/GA transfer design also pairs raw and repair-aware ranking within each optimizer using identical family-specific budgets and random streams. These within-family contrasts isolate ranking semantics; cross-family absolute performance is not interpreted as a compute-matched superiority claim unless separately analyzed under the primary budget protocol.
