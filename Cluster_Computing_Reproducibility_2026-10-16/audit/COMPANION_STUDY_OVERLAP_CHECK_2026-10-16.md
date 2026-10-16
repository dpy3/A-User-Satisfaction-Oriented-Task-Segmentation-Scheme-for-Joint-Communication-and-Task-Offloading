# Companion-study artifact overlap check (2026-10-16)

A SHA-256 comparison was made between the Cluster Computing release code snapshot (128 files) and the local PMC code snapshot (44 files). It found 20 byte-identical files, including simulator/environment routines, hardware profiles, and implemented comparator code. These are shared implementation components; describe their reuse transparently in the related-work/editor disclosure as required by the journal.

A SHA-256 comparison of the Cluster data folder (30 files) and the PMC data folder (20 files) found 0 byte-identical file pairs. The two study records also have no overlapping random seeds. These are file/protocol checks only: they cannot exclude transformed, summarized, or otherwise derived numerical reuse. The Cluster manuscript has no embedded figures. Authors must complete a table/source-data cross-check and disclose the related manuscript to the editor before submission.

A targeted exact-value comparison of the two primary formal run-level satisfaction datasets is documented in `COMPANION_STUDY_NUMERIC_CROSSCHECK_2026-10-16.md`. It found no exact satisfaction-value match in the common N=180 subset, and one coincident scalar value across unmatched conditions (N=250 versus N=180). This narrow check does not prove independence and does not cover every onset, sensitivity, or ablation output.

## Identical code files

- `Algorithms/LP_Relaxed_Solver_Binary.m` = `Algorithms/LP_Relaxed_Solver_Binary.m` (SHA-256 `0713f2773950600a28c56f8a7305dd667c73150344dfbdd7bb240429f434094b`)
- `Algorithms/MPC_Rollout_Solver_Binary.m` = `Algorithms/MPC_Rollout_Solver_Binary.m` (SHA-256 `0ceb9190256e6403c15cd115a2d436e1fff1ff8694305fb73d635f20b2b3a066`)
- `Environment/build_pre_struct_tier1.m` = `Environment/build_pre_struct_tier1.m` (SHA-256 `18e2ac9f8c5dc4fb6d6f0ed003cfba95bcee3150da96d7ed144491f8ac044038`)
- `Utils/verify_trace_integrity.m` = `Utils/verify_trace_integrity.m` (SHA-256 `45370b0905f0072f45fe8eef05cb7219f3cd76618f033f7da0e394152a2ae4c8`)
- `Data/VGG16_Profile.csv` = `Data/VGG16_Profile.csv` (SHA-256 `5680eaaabf0431b14a1eb01a7ae69e205fbc03511b1764b9649a07bc6ed4dcbe`)
- `Algorithms/DPP_Solver_Binary.m` = `Algorithms/DPP_Solver_Binary.m` (SHA-256 `6c52281966fe28e9afc426c6563afdcee48af85e583bab44fa340612b9f2c11d`)
- `Data/ResNet_Profile.csv` = `Data/ResNet_Profile.csv` (SHA-256 `72b1f75b1ac135ab37e9ecadcaad8f83846162ac3c5dae308ca6434451789aeb`)
- `Algorithms/PPO_Lite_Solver_Binary.m` = `Algorithms/PPO_Lite_Solver_Binary.m` (SHA-256 `76e5c8e64a1f04d3052daff35ee9fd2dbecf5dcd9dc06cc9bbdac681f485e1dd`)
- `Algorithms/HIVE_Controller.m` = `Algorithms/HIVE_Controller.m` (SHA-256 `8aac9d4831da9e00e3712efed531660b463521af064ae8be783b086829156893`)
- `Algorithms/BigMEC_Greedy_Adapter_Binary.m` = `Algorithms/BigMEC_Greedy_Adapter_Binary.m` (SHA-256 `9240bd5c1be479d6920f858eab1c5a64bbf4c9f686a7c2c647ecfc3e4b8684f2`)
- `Algorithms/DRL_DQN_Solver_Binary.m` = `Algorithms/DRL_DQN_Solver_Binary.m` (SHA-256 `98e364fbc26bed422700ae5a4e3a78f37e66f0946e3294d2e3b22b15c0a6b6b8`)
- `Environment/Build_Pre_Struct.m` = `Environment/Build_Pre_Struct.m` (SHA-256 `ae9e5970ff9aaf2b3c1b3813daf4c073b71a226f9d73c4213848ef288bec6e56`)
- `Algorithms/Greedy_Solver_DNN.m` = `Algorithms/Greedy_Solver_DNN.m` (SHA-256 `b869cd35ad4db880307854056dba69926a669807389ad14a5ef72c2950e090f7`)
- `Algorithms/Bipartite_GNN_Solver_Binary.m` = `Algorithms/Bipartite_GNN_Solver_Binary.m` (SHA-256 `cdcdeb7caadd46eb826472eaf39321a75eb347d08c4b5cc2276d497daaccfd0b`)
- `Environment/Generate_Environment.m` = `Environment/Generate_Environment.m` (SHA-256 `d6d45cf6d1de89a61d5e8c11c587ce281eab57a741aa21f3081120ba00db56a3`)
- `Environment/generate_tier1_env_hetero.m` = `Environment/generate_tier1_env_hetero.m` (SHA-256 `dbe6c1df8174821ffa78567db24435e2e0e4474cef3f9a9fd701747dfeb37173`)
- `Algorithms/Budgeted_LNS_Solver_Binary.m` = `Algorithms/Budgeted_LNS_Solver_Binary.m` (SHA-256 `f0753659c942d09112899b30f9bd814c000cf780a9bce39cfec81481f416cc37`)
- `Environment/load_hardware_profile.m` = `Environment/load_hardware_profile.m` (SHA-256 `f2ccb3d7205314c6b0744e557f484d1e0826031206e251756e809f1713a410b3`)
- `Utils/Perform_Global_Optimization.m` = `Utils/Perform_Global_Optimization.m` (SHA-256 `f47ee5d4d8ab97094c880cf44fef18d950209e9ee2d57e69539ecf1b7d035b01`)
- `Data/MobileNet_Profile.csv` = `Data/MobileNet_Profile.csv` (SHA-256 `fd118ed6a6709d9ed5a32c4aa21ce8ac4e5ef2229871c84bd7f540efd4cede12`)
