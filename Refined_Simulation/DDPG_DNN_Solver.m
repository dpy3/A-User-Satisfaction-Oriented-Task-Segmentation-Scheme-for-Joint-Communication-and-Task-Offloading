function [theta_bin, total_reward, training_stats] = DDPG_DNN_Solver(Task, Fog, Thing, DNN_Data, options)
    % DDPG_DNN_SOLVER
    % Deep Deterministic Policy Gradient for DNN Offloading
    % 
    % This implements a state-of-the-art Deep Reinforcement Learning approach
    % for the task offloading problem.
    %
    % Architecture:
    % - Actor Network: Outputs continuous offloading probabilities
    % - Critic Network: Estimates Q-value for state-action pairs
    % - Experience Replay + Target Networks for stability
    %
    % References:
    % - Lillicrap et al., "DDPG", ICLR 2016
    % - Chen et al., "Deep RL for Computation Offloading", TWC 2019
    
    global task_num fog_num T;
    
    if nargin < 5
        options = struct();
    end
    
    % Hyperparameters
    num_episodes = getfield_default(options, 'num_episodes', 500);
    max_steps = getfield_default(options, 'max_steps', 100);
    gamma = getfield_default(options, 'gamma', 0.99);
    tau = getfield_default(options, 'tau', 0.005);  % Soft update rate
    actor_lr = getfield_default(options, 'actor_lr', 1e-4);
    critic_lr = getfield_default(options, 'critic_lr', 1e-3);
    buffer_size = getfield_default(options, 'buffer_size', 10000);
    batch_size = getfield_default(options, 'batch_size', 64);
    noise_std = getfield_default(options, 'noise_std', 0.1);
    
    Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
    
    % State dimension: [Load per node (F), Queue length (F), Remaining tasks (1)]
    state_dim = 2 * fog_num + 1;
    
    % Action dimension: Offloading probability for each (task, layer, node)
    action_dim = task_num * T * fog_num;
    
    % Neural Network Initialization (Simple 2-layer MLP)
    % Actor: state -> action (tanh activation for bounded output)
    hidden_actor = 128;
    W_actor_1 = randn(hidden_actor, state_dim) * sqrt(2/state_dim);
    b_actor_1 = zeros(hidden_actor, 1);
    W_actor_2 = randn(action_dim, hidden_actor) * sqrt(2/hidden_actor);
    b_actor_2 = zeros(action_dim, 1);
    
    % Critic: (state, action) -> Q-value
    hidden_critic = 128;
    W_critic_1 = randn(hidden_critic, state_dim + action_dim) * sqrt(2/(state_dim + action_dim));
    b_critic_1 = zeros(hidden_critic, 1);
    W_critic_2 = randn(1, hidden_critic) * sqrt(2/hidden_critic);
    b_critic_2 = 0;
    
    % Target Networks (Copy)
    W_actor_1_target = W_actor_1;
    b_actor_1_target = b_actor_1;
    W_actor_2_target = W_actor_2;
    b_actor_2_target = b_actor_2;
    W_critic_1_target = W_critic_1;
    b_critic_1_target = b_critic_1;
    W_critic_2_target = W_critic_2;
    b_critic_2_target = b_critic_2;
    
    % Experience Replay Buffer
    replay_buffer = struct();
    replay_buffer.states = zeros(buffer_size, state_dim);
    replay_buffer.actions = zeros(buffer_size, action_dim);
    replay_buffer.rewards = zeros(buffer_size, 1);
    replay_buffer.next_states = zeros(buffer_size, state_dim);
    replay_buffer.dones = zeros(buffer_size, 1);
    replay_buffer.ptr = 1;
    replay_buffer.size = 0;
    
    % Adam Optimizer States
    m_actor = struct('W1', zeros(size(W_actor_1)), 'b1', zeros(size(b_actor_1)), ...
                     'W2', zeros(size(W_actor_2)), 'b2', zeros(size(b_actor_2)));
    v_actor = m_actor;
    m_critic = struct('W1', zeros(size(W_critic_1)), 'b1', zeros(size(b_critic_1)), ...
                      'W2', zeros(size(W_critic_2)), 'b2', zeros(size(b_critic_2)));
    v_critic = m_critic;
    
    training_stats = struct();
    training_stats.episode_rewards = zeros(num_episodes, 1);
    training_stats.actor_loss = zeros(num_episodes, 1);
    training_stats.critic_loss = zeros(num_episodes, 1);
    
    best_reward = -inf;
    best_theta = [];
    
    fprintf('  [DDPG] Training for %d episodes...\n', num_episodes);
    
    for ep = 1:num_episodes
        % Reset environment
        state = get_initial_state(Pre, Fog);
        episode_reward = 0;
        
        for step = 1:max_steps
            % Actor forward pass with exploration noise
            h_actor = max(0, W_actor_1 * state + b_actor_1);  % ReLU
            action_raw = tanh(W_actor_2 * h_actor + b_actor_2);  % Bounded [-1, 1]
            
            % Add Gaussian noise for exploration
            noise = randn(action_dim, 1) * noise_std * (1 - ep/num_episodes);  % Decay noise
            action = max(-1, min(1, action_raw + noise));
            
            % Convert action to offloading decision
            action_probs = (action + 1) / 2;  % Map to [0, 1]
            theta_cont = reshape(action_probs, [task_num, T, fog_num]);
            
            % Get reward from environment
            [reward, next_state, done] = step_environment(theta_cont, Pre, Fog, Task, state);
            
            % Store in replay buffer
            idx = replay_buffer.ptr;
            replay_buffer.states(idx, :) = state';
            replay_buffer.actions(idx, :) = action';
            replay_buffer.rewards(idx) = reward;
            replay_buffer.next_states(idx, :) = next_state';
            replay_buffer.dones(idx) = done;
            replay_buffer.ptr = mod(replay_buffer.ptr, buffer_size) + 1;
            replay_buffer.size = min(replay_buffer.size + 1, buffer_size);
            
            episode_reward = episode_reward + reward;
            state = next_state;
            
            % Training step (if enough samples)
            if replay_buffer.size >= batch_size
                % Sample batch
                batch_idx = randperm(replay_buffer.size, batch_size);
                batch_s = replay_buffer.states(batch_idx, :)';
                batch_a = replay_buffer.actions(batch_idx, :)';
                batch_r = replay_buffer.rewards(batch_idx);
                batch_ns = replay_buffer.next_states(batch_idx, :)';
                batch_d = replay_buffer.dones(batch_idx);
                
                % Critic update
                % Target Q = r + gamma * Q_target(s', a')
                h_target = max(0, W_actor_1_target * batch_ns + b_actor_1_target);
                a_target = tanh(W_actor_2_target * h_target + b_actor_2_target);
                
                sa_target = [batch_ns; a_target];
                h_critic_target = max(0, W_critic_1_target * sa_target + b_critic_1_target);
                Q_target = W_critic_2_target * h_critic_target + b_critic_2_target;
                
                target = batch_r' + gamma * Q_target .* (1 - batch_d');
                
                % Current Q
                sa_current = [batch_s; batch_a];
                h_critic = max(0, W_critic_1 * sa_current + b_critic_1);
                Q_current = W_critic_2 * h_critic + b_critic_2;
                
                % Critic loss (MSE)
                critic_loss = mean((Q_current - target).^2);
                
                % Critic gradients
                dL_dQ = 2 * (Q_current - target) / batch_size;
                dQ_dW2 = h_critic;
                dQ_db2 = 1;
                grad_W_critic_2 = dL_dQ * dQ_dW2';
                grad_b_critic_2 = sum(dL_dQ);
                
                dQ_dh = W_critic_2' * dL_dQ;
                dh_dz = double(h_critic > 0);  % ReLU derivative
                dz_dW1 = sa_current;
                grad_W_critic_1 = (dQ_dh .* dh_dz) * dz_dW1';
                grad_b_critic_1 = sum(dQ_dh .* dh_dz, 2);
                
                % Update critic with Adam
                [W_critic_1, m_critic.W1, v_critic.W1] = adam_update(W_critic_1, grad_W_critic_1, m_critic.W1, v_critic.W1, critic_lr, ep);
                [b_critic_1, m_critic.b1, v_critic.b1] = adam_update(b_critic_1, grad_b_critic_1, m_critic.b1, v_critic.b1, critic_lr, ep);
                [W_critic_2, m_critic.W2, v_critic.W2] = adam_update(W_critic_2, grad_W_critic_2, m_critic.W2, v_critic.W2, critic_lr, ep);
                [b_critic_2, m_critic.b2, v_critic.b2] = adam_update(b_critic_2, grad_b_critic_2, m_critic.b2, v_critic.b2, critic_lr, ep);
                
                % Actor update (Policy Gradient)
                h_actor_batch = max(0, W_actor_1 * batch_s + b_actor_1);
                a_actor_batch = tanh(W_actor_2 * h_actor_batch + b_actor_2);
                
                sa_actor = [batch_s; a_actor_batch];
                h_critic_for_actor = max(0, W_critic_1 * sa_actor + b_critic_1);
                Q_for_actor = W_critic_2 * h_critic_for_actor + b_critic_2;
                
                actor_loss = -mean(Q_for_actor);  % Maximize Q
                
                % Backprop through critic to get dQ/da
                dQ_da = W_critic_1(:, state_dim+1:end)' * (W_critic_2' .* double(h_critic_for_actor > 0));
                dQ_da = mean(dQ_da, 2);  % Average over batch
                
                % Backprop through actor: da/dW2, da/dW1
                dtanh = 1 - a_actor_batch.^2;
                dL_da = -dQ_da / batch_size;  % Negative because we maximize
                
                grad_W_actor_2 = mean((dL_da .* dtanh) * h_actor_batch', 3);
                grad_b_actor_2 = mean(sum(dL_da .* dtanh, 2), 3);
                
                dL_dh_actor = W_actor_2' * (dL_da .* dtanh);
                dh_actor_dz = double(h_actor_batch > 0);
                grad_W_actor_1 = mean((dL_dh_actor .* dh_actor_dz) * batch_s', 3);
                grad_b_actor_1 = mean(sum(dL_dh_actor .* dh_actor_dz, 2), 3);
                
                % Update actor with Adam
                [W_actor_1, m_actor.W1, v_actor.W1] = adam_update(W_actor_1, grad_W_actor_1, m_actor.W1, v_actor.W1, actor_lr, ep);
                [b_actor_1, m_actor.b1, v_actor.b1] = adam_update(b_actor_1, grad_b_actor_1, m_actor.b1, v_actor.b1, actor_lr, ep);
                [W_actor_2, m_actor.W2, v_actor.W2] = adam_update(W_actor_2, grad_W_actor_2, m_actor.W2, v_actor.W2, actor_lr, ep);
                [b_actor_2, m_actor.b2, v_actor.b2] = adam_update(b_actor_2, grad_b_actor_2, m_actor.b2, v_actor.b2, actor_lr, ep);
                
                % Soft update target networks
                W_actor_1_target = tau * W_actor_1 + (1-tau) * W_actor_1_target;
                b_actor_1_target = tau * b_actor_1 + (1-tau) * b_actor_1_target;
                W_actor_2_target = tau * W_actor_2 + (1-tau) * W_actor_2_target;
                b_actor_2_target = tau * b_actor_2 + (1-tau) * b_actor_2_target;
                W_critic_1_target = tau * W_critic_1 + (1-tau) * W_critic_1_target;
                b_critic_1_target = tau * b_critic_1 + (1-tau) * b_critic_1_target;
                W_critic_2_target = tau * W_critic_2 + (1-tau) * W_critic_2_target;
                b_critic_2_target = tau * b_critic_2 + (1-tau) * b_critic_2_target;
                
                training_stats.critic_loss(ep) = critic_loss;
                training_stats.actor_loss(ep) = actor_loss;
            end
            
            if done, break; end
        end
        
        training_stats.episode_rewards(ep) = episode_reward;
        
        % Track best
        if episode_reward > best_reward
            best_reward = episode_reward;
            % Get best action
            h_actor = max(0, W_actor_1 * state + b_actor_1);
            action_best = (tanh(W_actor_2 * h_actor + b_actor_2) + 1) / 2;
            best_theta = action_best;
        end
        
        if mod(ep, 100) == 0
            fprintf('    Episode %d: Reward=%.2f, Best=%.2f\n', ep, episode_reward, best_reward);
        end
    end
    
    % Final evaluation: Use learned policy
    state = get_initial_state(Pre, Fog);
    h_actor = max(0, W_actor_1 * state + b_actor_1);
    action_final = (tanh(W_actor_2 * h_actor + b_actor_2) + 1) / 2;
    
    % Discretize
    theta_cont = reshape(action_final, [task_num, T, fog_num]);
    theta_bin = discretize_theta(theta_cont);
    theta_bin = theta_bin(:);
    
    total_reward = best_reward;
    
    fprintf('  [DDPG] Training Complete. Best Reward: %.2f\n', best_reward);
end

function state = get_initial_state(Pre, Fog)
    global task_num fog_num;
    % State: [Load (F), Queue (F), Remaining (1)]
    load = zeros(fog_num, 1);
    queue = zeros(fog_num, 1);
    remaining = task_num;
    state = [load; queue; remaining];
end

function [reward, next_state, done] = step_environment(theta_cont, Pre, Fog, Task, current_state)
    global task_num fog_num T;
    
    % Calculate metrics
    theta_bin = discretize_theta(theta_cont);
    [avg_sat, viol_rate, ~] = calculate_metrics_v2(theta_bin(:), Task, Fog, [], []);
    
    % Reward = Satisfaction - Violation Penalty
    reward = avg_sat - 100 * viol_rate;
    
    % Update state based on assignment
    Load_new = squeeze(sum(sum(theta_bin .* Pre.Comp_Exp, 1), 2));
    Queue_new = Load_new ./ (Fog(:, 7) + 1e-9);
    
    next_state = [Load_new; Queue_new; 0];
    done = true;  % Single-step environment for simplicity
end

function theta_bin = discretize_theta(theta_cont)
    global task_num fog_num T;
    
    theta_bin = zeros(task_num, T, fog_num);
    
    for n = 1:task_num
        for t = 1:T
            probs = squeeze(theta_cont(n, t, :));
            probs(probs < 0) = 0;
            
            % Add "local" option
            local_prob = max(0, 1 - sum(probs));
            all_probs = [probs(:); local_prob];
            
            [~, best_idx] = max(all_probs);
            if best_idx <= fog_num
                theta_bin(n, t, best_idx) = 1;
            end
            % else: local (all zeros)
        end
    end
end

function [param, m, v] = adam_update(param, grad, m, v, lr, t)
    beta1 = 0.9; beta2 = 0.999; eps = 1e-8;
    m = beta1 * m + (1-beta1) * grad;
    v = beta2 * v + (1-beta2) * (grad.^2);
    m_hat = m / (1 - beta1^t);
    v_hat = v / (1 - beta2^t);
    param = param - lr * m_hat ./ (sqrt(v_hat) + eps);
end

function val = getfield_default(s, field, default)
    if isfield(s, field)
        val = s.(field);
    else
        val = default;
    end
end
