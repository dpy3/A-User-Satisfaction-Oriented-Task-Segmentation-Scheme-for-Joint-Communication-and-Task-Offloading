# Leakage-Free Offline GNN Baseline

The learned comparator is trained only on runs 51-55, selected only on runs
61-63, and evaluated on the official paired test environments from runs 1-30.
The formal scales are `N={120,150,180,200,250,300}`. Test environments never
update network parameters, collect labels, or alter hyperparameters.

Two frozen learning-rate candidates share the same 24-unit message-passing
architecture. Training uses four separate environment passes, one imitation
rollout per environment, and no test-time DAgger. The validation mean satisfaction
selects one model before the test package is generated. All test schedules receive
the same Safe Harbor repair, global post-optimization, metrics, and environment
seeds as the official baseline experiment.

Smoke mode shortens each split and is not manuscript evidence. The model file,
configuration, run-level test rows, official ALM pairing, and SHA-256 manifest are
stored together. The paper may call this method an offline learned comparator; it
must not describe it as reinforcement learning or as a new contribution.
