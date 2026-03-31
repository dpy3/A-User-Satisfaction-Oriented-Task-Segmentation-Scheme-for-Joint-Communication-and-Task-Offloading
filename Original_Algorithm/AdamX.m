function [theta, loss_history] = AdamX(max_iter,theta,alpha1, alpha2, Beta,gamm,lanb1,lanb2,lanb3,lanb4,p1,p2,p3,p4,Fog,Task,Thing)
    % 参数初始化
    alpha = 0.01;
    beta1 = 0.9;
    lanbta = 0.99;
    beta2 = 0.999;
    epsilon = 10^(-8);
%     theta = theta_initial();
%     theta = Bound(theta, Fog, Task);
    m_t = zeros(size(theta));
    v_t = zeros(size(theta));
    v_hat_t = zeros(size(theta));
    loss_history = zeros(1, max_iter);
    t = 1;
%     flag=1;
%     sign = 0;
    theta_history = [];
    loss_history(t) = loss_function(theta, lanb1, lanb2, lanb3,lanb4, Beta, gamm, alpha1, alpha2, p1, p2, p3, p4, Task, Fog, Thing); % 用你的损失函数替代 your_loss_function
    while(t<max_iter)%%&&flag==1
        % 计算梯度
        t = t + 1;
        g_t = computeGradient(theta, alpha1, alpha2, Beta,gamm,lanb1,lanb2,lanb3,lanb4,p1,p2,p3,p4,Fog,Task,Thing);
        % 更新一阶动量和二阶动量
        m_t = beta1 * m_t + (1 - beta1) * g_t;
        v_t = beta2 * v_t + (1 - beta2) * g_t.^2;
        % 更新历史最大的二阶动量
        v_hat_t = max((1 - beta1*lanbta^t)^2/(1 - beta1*lanbta^(t-1))^2 * v_hat_t, v_t);
        % 更新参数
        theta_history = [theta_history;theta];
        theta = theta - alpha*sqrt(t) * m_t ./ (sqrt(v_hat_t) + epsilon);
        % 记录损失
        loss_history(t) = loss_function(theta, lanb1, lanb2, lanb3,lanb4, Beta, gamm, alpha1, alpha2, p1, p2, p3, p4, Task, Fog, Thing); % 用你的损失函数替代 your_loss_function
%         if (loss_history(t)>=loss_history(t-1))
%             sign = sign + 1;
%         else
%             sign = 0;
%         end
%         if sign==100%%连续十代没有下降，优化停止
%             flag = 0;
%         end
    end

end
