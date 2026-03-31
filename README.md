# MEC ALM-AdamX Source Code

This repository contains the source code for the paper: **[Paper Title]**, implementing the Augmented Lagrangian Method (ALM) coupled with the AdamX algorithm for Joint Task Segmentation and Offloading in Mobile Edge Computing (MEC).

## Directory Structure

- **`Original_Algorithm/`**: Contains the core implementation of the AdamX algorithm and the optimization loop.
  - `AdamX.m`: The AdamX optimizer implementation combining Adam's adaptive learning rate with gradient constraints specific to the MEC offloading scenario.
  - `optim.m`: The main optimization loop utilizing the AdamX solver.

- **`Refined_Simulation/`**: Contains the rigorous, trace-driven simulation environment and the updated ALM solvers (e.g., Memetic ALM, Pure ALM) used for generating the manuscript's experimental results.
  - `run_manuscript_experiments_final.m`: The main script to execute the simulation and generate performance metrics (Satisfaction, Violation, Latency, etc.).
  - `evaluate_solution.m`: The rigorous evaluation metric source using M/D/1 queuing models.
  - `Memetic_ALM_Solver.m` / `Pure_ALM_Solver.m`: The refined ALM solvers.
  - `generate_tier1_env_hetero.m`: Environment generation script for heterogeneous task profiles.
  - `*_Profile.csv`: Trace-driven hardware profiles (MobileNet, ResNet, VGG16) used to model realistic computational workloads.
  - Baseline Solvers: Includes `GA_Hybrid_Solver.m`, `Greedy_Solver_DNN.m`, and `DDPG_DNN_Solver.m` for comparative analysis.

## Usage

1. **Running the Main Simulation:**
   Navigate to the `Refined_Simulation` folder in MATLAB and execute `run_manuscript_experiments_final.m`. This script will automatically generate the environment, run the proposed ALM solvers alongside baselines, and save the results.

2. **Algorithm Implementation:**
   The fundamental AdamX logic can be explored in `Original_Algorithm/AdamX.m`.

## Requirements
- MATLAB R2021a or newer.
- Deep Learning Toolbox (if running DDPG/DNN baselines).
- Optimization Toolbox.
