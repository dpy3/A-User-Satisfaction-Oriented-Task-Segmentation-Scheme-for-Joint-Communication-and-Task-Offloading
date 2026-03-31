function [theta_bin, loss_hist] = Pure_ALM_Solver(Task, Fog, Thing, DNN_Data, max_iter)
    % PURE_ALM_SOLVER
    % A clean, no-cheating implementation of P-ALM for Ablation Study.
    % No "Safety Net", no "Straggler Killing", no "GA Warm Start" (Random Init).
    % This serves as the "ALM Only" baseline.
    
    global task_num fog_num T;
    
    % --- Init ---
    task_num = size(Task, 1);
    fog_num = size(Fog, 1);
    if iscell(DNN_Data), T = length(DNN_Data{1}.comp); else, T = length(DNN_Data.comp); end
    F_aug = fog_num + 1;
    Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
    
    % Random Init (Standard for comparison)
    theta_logits = randn(task_num, T, F_aug) * 0.01;
    
    lambda_cap = zeros(fog_num, 1);
    lambda_mem = zeros(fog_num, 1);
    mu = 1.0;
    lr = 0.05;
    
    if nargin < 5
        max_iter = 100;
    end
    
    loss_hist = zeros(max_iter, 1);
    
    for k = 1:max_iter
        probs = softmax(theta_logits);
        probs_fog = probs(:, :, 1:fog_num);
        
        % Gradients
        % Using the same rigorous gradient computation as Memetic-ALM
        [grad_obj_fog, grad_obj_local, metrics] = compute_gradient_tier1(probs, Pre, Fog, Task, Thing, 0.5, k);
        [grad_con_fog, raw_cap, raw_mem] = compute_gradient_constraints(probs_fog, Pre, Fog, lambda_cap, lambda_mem, mu);
        
        grad_total = zeros(size(probs));
        grad_total(:, :, 1:fog_num) = grad_obj_fog + grad_con_fog;
        grad_total(:, :, end) = grad_obj_local;
        
        % Update
        theta_logits = theta_logits - lr * grad_total;
        
        % Dual Update
        lambda_cap = max(0, lambda_cap + mu * raw_cap);
        lambda_mem = max(0, lambda_mem + mu * raw_mem);
        mu = min(mu * 1.02, 100.0);
        
        loss_hist(k) = metrics.loss;
    end
    
    % Discretize
    probs = softmax(theta_logits);
    [~, idx] = max(probs, [], 3);
    theta_bin = zeros(task_num, T, fog_num);
    for n=1:task_num
        for t=1:T
            if idx(n,t) <= fog_num
                theta_bin(n,t,idx(n,t)) = 1;
            end
        end
    end
    
    % Polish (Allowed, as it's just local search)
    % theta_bin = polish_solution_tabu(theta_bin, Pre, Fog, Thing);
end

function p = softmax(x)
    max_x = max(x, [], 3);
    ex = exp(x - max_x);
    p = ex ./ sum(ex, 3);
end
