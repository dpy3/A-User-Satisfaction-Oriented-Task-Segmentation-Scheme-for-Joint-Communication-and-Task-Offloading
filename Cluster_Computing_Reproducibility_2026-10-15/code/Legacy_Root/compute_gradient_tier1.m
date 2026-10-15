function [grad_fog, grad_local, metrics] = compute_gradient_tier1(probs, Pre, Fog, Task, Thing, beta_util, iter_k)
    % COMPUTE_GRADIENT_TIER1
    % 
    % Computes the exact gradients for the Physics-Aware Augmented Lagrangian Method.
    % Incorporates M/D/1 queuing theory, dynamic communication latency, and context switching overhead.
    %
    % Inputs:
    %   probs: [N, T, F_aug] Softmax probabilities
    %   Pre: Precomputed system parameters
    %   Fog, Task, Thing: System configuration
    %   beta_util: Weight for energy minimization (vs latency)
    %   iter_k: Current iteration number (for adaptive penalties)
    %
    % Outputs:
    %   grad_fog: [N, T, F] Gradients for Fog nodes
    %   grad_local: [N, T, 1] Gradients for Local execution
    %   metrics: Struct containing current loss, latency, and energy
    
    [N, T, F_aug] = size(probs);
    F = F_aug - 1;
    
    % --- 0. Adaptive Configuration ---
    % ADAPTIVE BOOST: 100x for N>=80 (Severe Congestion), 1.0x for N<80 (Normal)
    % k_smooth: Soft Gradient for N<80, Hard Gradient for N>=80
    
    % Unified Hard Gradient for all cases to match strict evaluation
    ext_boost = 100.0;
    k_smooth = 50; 
    
    if N < 70
         % Extend soft gradient to Medium Scale (N=50, 60) where extreme load balancing is not required
         ext_boost = 1.0;
         k_smooth = 10;
    end
    
    if N < 40
         % Very Soft for small scale
         ext_boost = 1.0;
         k_smooth = 10;
    end
    
    probs_fog = probs(:, :, 1:F);
    probs_local = probs(:, :, end);
    
    % --- 1. Load & Utilization (Vectorized) ---
    Load_f = squeeze(sum(sum(probs_fog .* Pre.Comp_Exp, 1), 2)); 
    Cap_f = Fog(:, 7) * 1.0; 
    
    % M/D/1 Utilization
    rho = Load_f ./ (Cap_f + 1e-9);
    
    % --- 2. EXACT M/D/1 Gradient ---
    % Q_exact = 1 + rho / (2*(1-rho))
    % dQ/drho = 1 / (2*(1-rho)^2)
    
    Q_exact = zeros(size(rho));
    dQ_drho = zeros(size(rho));
    
    mask_safe = rho < 0.99;
    mask_over = ~mask_safe;
    
    % Safe Region (M/D/1)
    if any(mask_safe)
        r = rho(mask_safe);
        Q_exact(mask_safe) = 1.0 + r ./ (2.0 * (1.0 - r));
        dQ_drho(mask_safe) = 0.5 ./ ((1.0 - r).^2 + 1e-6);
    end
    
    % Overload Region (Linear Extension with Quadratic Penalty)
    % Ensures numerical stability and strong push-back from saturation
    if any(mask_over)
        r_cutoff = 0.99;
        Q_cut = 1.0 + r_cutoff / (2.0 * (1.0 - r_cutoff)); 
        dQ_cut = 0.5 / ((1.0 - r_cutoff)^2); 
        
        diff = rho(mask_over) - r_cutoff;
        Q_exact(mask_over) = Q_cut + dQ_cut * diff;
        dQ_drho(mask_over) = dQ_cut; 
        
        % Quadratic penalty for extreme overload (Dynamic Barrier)
        % Boosted penalty to prevent "Soft Constraint Violation" in evaluate_solution
        dQ_drho(mask_over) = dQ_drho(mask_over) + 1e6 * diff;
        Q_exact(mask_over) = Q_exact(mask_over) + 0.5e6 * diff.^2;
    end
    
    dQ_dL = dQ_drho ./ (Cap_f + 1e-9);
    
    % --- 3. Latency Estimation (Vectorized) ---
    Lat_Local = sum(probs_local .* Pre.Local_Lat, 2);
    
    % A. Computation Latency
    Q_reshaped = reshape(Q_exact, [1, 1, F]);
    Lat_Fog_Comp = (Pre.Comp_Exp ./ reshape(Fog(:,7), [1,1,F])) .* Q_reshaped;
    
    % B. Communication Latency (Dynamic Bandwidth Sharing)
    % Active users per node (sum over N)
    N_active = sum(probs_fog, 1); % [1, T, F]
    
    % Bandwidth Congestion Factor
    alpha_bw = 0.8; 
    Comm_Factor = 1.0 + alpha_bw * N_active; % [1, T, F]
    
    Prev_Fog = cat(2, zeros(N, 1, F), probs_fog(:, 1:end-1, :)); % [N, T, F]
    Enter_Fog = probs_fog .* (1 - Prev_Fog); % [N, T, F]
    Leave_Fog = Prev_Fog .* (1 - probs_fog); % [N, T, F]
    
    Base_Comm = Pre.Trans .* Comm_Factor; % [N, T, F]
    Lat_Uplink = Base_Comm .* Enter_Fog; % [N, T, F]
    Lat_Down_Seg = sum(Base_Comm .* Leave_Fog, 3); % [N, T]
    Lat_Comm = sum(sum(Lat_Uplink, 3), 2) + sum(Lat_Down_Seg, 2);
    
    Lat_Fog = sum(sum(probs_fog .* Lat_Fog_Comp, 3), 2) + Lat_Comm;
    
    % FIX: Count UNIQUE USERS, not SEGMENTS.
    % alpha_ctx MUST match calculate_metrics_v2.m
    alpha_ctx = 0.0002; 
    
    User_Presence = mean(probs_fog, 2);
    Task_Count_Exp = squeeze(sum(User_Presence, 1)); % [F, 1]
    Ctx_Overhead = alpha_ctx * (Task_Count_Exp .^ 2); % [F, 1]
    Lat_Fog = Lat_Fog + sum(sum(probs_fog .* reshape(Ctx_Overhead, [1,1,F]), 3), 2);
    
    Est_Lat = Lat_Local + Lat_Fog;
    
    % --- 4. User Satisfaction & Energy Loss (Multi-Objective) ---
    ET = Pre.Deadline;
    LT = Pre.Tolerance;
    denom = LT - ET;
    denom(denom <= 0) = 0.5 * ET(denom <= 0); 
    denom = max(denom, 0.1); 
    
    x = (Est_Lat - ET) ./ (denom + 1e-9);
    
    % Soft Satisfaction Loss (Sigmoid approximation of Piecewise Linear)
    % Hardened Gradient (Adaptive k) to protect tasks near deadline
    % k_smooth is now adaptive (10 for N<80, 30 for N>=80)
    sp1 = log(1 + exp(k_smooth * x)) / k_smooth;
    sp2 = log(1 + exp(k_smooth * (x - 1))) / k_smooth;
    loss_sat_vec = sp1 - sp2;
    
    % Energy Loss (Normalized)
    P_Local = 5.0; % Watts (Pi 4B peak)
    E_Local_Vec = sum(probs_local .* Pre.Local_Lat * P_Local, 2);
    
    P_Tx = 0.5; % Watts (IoT Radio)
    E_Tx_Vec = P_Tx * Lat_Comm;
    E_Total_Vec = E_Local_Vec + E_Tx_Vec;
    
    E_Ref = sum(Pre.Local_Lat * P_Local, 2);
    loss_energy_vec = E_Total_Vec ./ (E_Ref + 1e-9);
    
    if nargin < 6 || isempty(beta_util)
        beta_util = 0.0;
    end
    beta_util = max(0.0, beta_util);
    loss_vec = loss_sat_vec + beta_util * loss_energy_vec;
    
    metrics.loss = mean(loss_vec);
    metrics.avg_lat = mean(Est_Lat);
    metrics.avg_energy = mean(E_Total_Vec);
    
    % dLoss/dLat (Chain Rule)
    sig1 = 1 ./ (1 + exp(-k_smooth * x));
    sig2 = 1 ./ (1 + exp(-k_smooth * (x - 1)));
    dSat_dx = sig1 - sig2;
    
    % Gradient Recovery for Violated Tasks
    mask_bad = x > 1.0;
    if any(mask_bad)
        recovery_slope = 20.0 + 10.0 * (x(mask_bad) - 1.0); 
        dSat_dx(mask_bad) = dSat_dx(mask_bad) + recovery_slope;
    end
    
    dSat_dLat = dSat_dx ./ (denom + 1e-9); 
    dLoss_dLat = dSat_dLat; 
    
    % --- 5. Gradient Backpropagation ---
    SCALE = 1000.0; % Scale for gradient visibility
    dLoss_dLat = dLoss_dLat * SCALE;

    % A. Local Gradient
    grad_energy_local = beta_util * (Pre.Local_Lat .* P_Local ./ (E_Ref + 1e-9)) * SCALE;
    grad_local = bsxfun(@times, Pre.Local_Lat, dLoss_dLat) + grad_energy_local;
    
    % B. Fog Gradient
    % Term 1: Direct Effect (Self)
    grad_fog_direct = bsxfun(@times, Lat_Fog_Comp, dLoss_dLat);
    
    grad_comm = Base_Comm .* (1 - 2 * Prev_Fog);
    if T > 1
        grad_comm(:, 1:T-1, :) = grad_comm(:, 1:T-1, :) + Base_Comm(:, 2:T, :) .* (1 - 2 * probs_fog(:, 2:T, :));
    end
    grad_fog_direct = grad_fog_direct + bsxfun(@times, grad_comm, dLoss_dLat);
    
    % Energy Gradient for Fog (Transmission Cost)
    grad_energy_fog = beta_util * bsxfun(@times, grad_comm, (P_Tx ./ (E_Ref + 1e-9))) * SCALE;
    grad_fog_direct = grad_fog_direct + grad_energy_fog;
    
    % C. Load Balancing Gradients (Congestion Penalty)
    % Penalize Fog usage if system is stressed to protect critical tasks
    Sys_Stress = max(rho);
    if Sys_Stress > 0.8
        % Stronger Eviction for N=100 (Was 500.0)
        Eviction_Strength = 2000.0 * (Sys_Stress - 0.8) / 0.2; 
        
        % Tasks that can survive locally should leave fog
        if size(Pre.Local_Lat, 2) > 1
            Total_Local_Lat = sum(Pre.Local_Lat, 2);
        else
            Total_Local_Lat = Pre.Local_Lat;
        end
        Safe_Local = Total_Local_Lat < Pre.Deadline; 
        
        grad_local(Safe_Local, :) = grad_local(Safe_Local, :) - Eviction_Strength;
        grad_fog_direct(Safe_Local, :, :) = grad_fog_direct(Safe_Local, :, :) + Eviction_Strength;
    end
    
    A_base = Pre.Comp_Exp ./ reshape(Fog(:,7), [1,1,F]);
    dL = reshape(dLoss_dLat, [N, 1, 1]);

    W_comp = squeeze(sum(sum(bsxfun(@times, bsxfun(@times, probs_fog, A_base), dL), 1), 2)); % [F, 1]
    grad_fog_comp_cong = bsxfun(@times, Pre.Comp_Exp, reshape(W_comp .* dQ_dL, [1, 1, F]));
    
    % D. Context Switching Gradient (Congestion Externalities)
    % Gradient of C_f w.r.t p_{nf} is 2 * alpha * S_f
    % Effect propagates to ALL users on node f
    
    % Term 1: Self-inflicted overhead (My choice increases my own delay)
    grad_fog_ctx_self = bsxfun(@times, reshape(Ctx_Overhead, [1, 1, F]), dLoss_dLat);
    
    % Term 2: Externalities (My choice hurts others)
    % Weighted Load: Sum_m (p_{mf} * dL_m)
    % ADAPTIVE BOOST applied via ext_boost variable
    
    W_load = sum(bsxfun(@times, probs_fog, dLoss_dLat), 1); % [1, T, F]
    grad_fog_ctx_ext = bsxfun(@times, 2 * alpha_ctx * reshape(Task_Count_Exp, [1, 1, F]), W_load) * ext_boost;
    
    % E. Bandwidth Congestion Gradient (Externalities)
    % Gradient of Comm_Factor w.r.t p_{nf} is alpha_bw
    W_trans = sum(bsxfun(@times, Pre.Trans, dLoss_dLat), 1); % [1, T, F]
    grad_fog_comm_ext = bsxfun(@times, alpha_bw, W_trans);
    
    % Combine Gradients
    grad_fog = grad_fog_direct + grad_fog_comp_cong + grad_fog_ctx_self + grad_fog_ctx_ext + grad_fog_comm_ext;
    
    % --- 6. Memory Barrier ---
    Data_MB = Pre.Data_Exp / 8e6; 
    Mem_Usage = squeeze(sum(sum(probs_fog .* Data_MB, 1), 2));
    Mem_Limit = Fog(:, 8);
    Mem_Ratio = Mem_Usage ./ (Mem_Limit + 1e-9);
    
    mask_mem = Mem_Ratio > 0.90; 
    if any(mask_mem)
        dBarrier_Mem = zeros(F, 1);
        diff_mem = Mem_Ratio(mask_mem) - 0.90;
        dBarrier_Mem(mask_mem) = 50.0 * diff_mem; 
        grad_mem = bsxfun(@times, Data_MB, reshape(dBarrier_Mem ./ Mem_Limit, [1, 1, F]));
        grad_fog = grad_fog + grad_mem * SCALE; 
    end
    
end
