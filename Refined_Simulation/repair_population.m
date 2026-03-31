function pop_fixed = repair_population(pop, N, T, F)
    % REPAIR_POPULATION
    % Ensures that every task segment is assigned to exactly one node.
    %
    % Inputs:
    %   pop: Binary population matrix [pop_size, N*T*F]
    %   N: Number of tasks
    %   T: Number of segments
    %   F: Number of Fog nodes
    %
    % Output:
    %   pop_fixed: Repaired binary population
    
    [M, L] = size(pop);
    
    % Reshape to [M * N * T, F] to handle each segment assignment independently
    Z = reshape(pop, [M * N * T, F]);
    
    % Check row sums (should be 1)
    s = sum(Z, 2);
    
    % Add random noise to break ties or zero-rows
    R = rand(size(Z));
    Y = Z + R .* Z; % Bias towards existing 1s, but random if all 0s? 
    % Actually if Z is all 0, Y is 0. Need pure random if s==0.
    
    % Handle rows with no assignment (s==0)
    % If s==0, Z is all zeros. Y is all zeros. max(Y) is index 1. 
    % This defaults to Node 1. We might want random.
    
    % Better approach:
    % 1. For each row, find the max value. Set that to 1, others to 0.
    % 2. If all 0, pick random.
    
    % Let's use the logic from GA_Solver_Base but slightly more robust
    
    % If a row is all zeros, add random noise to make it selectable
    zero_rows = (s == 0);
    if any(zero_rows)
        Z(zero_rows, :) = rand(sum(zero_rows), F);
    end
    
    % Add small noise to everything to break ties
    Y = Z + rand(size(Z)) * 0.01;
    
    [~, arg] = max(Y, [], 2);
    
    % Reconstruct Valid Binary Matrix
    Z_new = zeros(size(Z));
    
    % Linear indices for the 1s
    % (row_index - 1) * num_cols + col_index
    idx = sub2ind(size(Z_new), (1:size(Z_new,1))', arg);
    Z_new(idx) = 1;
    
    pop_fixed = reshape(Z_new, [M, L]);
end
