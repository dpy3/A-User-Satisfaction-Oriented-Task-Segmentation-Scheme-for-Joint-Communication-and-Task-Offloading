function [grad_con, raw_cap, raw_mem] = compute_gradient_constraints(probs, Pre, Fog, lambda_cap, lambda_mem, mu)
    % COMPUTE_GRADIENT_CONSTRAINTS
    % 
    % Calculates the gradient of the Augmented Lagrangian penalty terms
    % for Fog Node Capacity and Memory.
    
    [N, T, F] = size(probs);
    
    % 1. Load Calculation
    % Pre.Comp_Exp: [N, T, F]
    Load = squeeze(sum(sum(probs .* Pre.Comp_Exp, 1), 2)); % [F, 1]
    Cap = Fog(:, 7); % [F, 1]
    raw_cap = Load - Cap;
    
    % 2. Memory Calculation
    % Pre.Data_Exp: [N, T, F] (Bits) -> Convert to MB
    Data_MB = Pre.Data_Exp / 8e6; 
    Mem_Usage = squeeze(sum(sum(probs .* Data_MB, 1), 2)); % [F, 1]
    Mem_Limit = Fog(:, 8); % [F, 1]
    raw_mem = Mem_Usage - Mem_Limit;
    
    % 3. Penalty Gradient
    % L_penalty = lambda * g(x) + (mu/2) * g(x)^2
    % dL/dx = (lambda + mu * g(x)) * dg/dx
    
    % For Capacity: dg/dProb = Comp
    mult_cap = lambda_cap + mu * raw_cap;
    grad_cap = bsxfun(@times, Pre.Comp_Exp, reshape(mult_cap, [1, 1, F]));
    
    % For Memory: dg/dProb = Data_MB
    mult_mem = lambda_mem + mu * raw_mem;
    grad_mem = bsxfun(@times, Data_MB, reshape(mult_mem, [1, 1, F]));
    
    grad_con = grad_cap + grad_mem;
end
