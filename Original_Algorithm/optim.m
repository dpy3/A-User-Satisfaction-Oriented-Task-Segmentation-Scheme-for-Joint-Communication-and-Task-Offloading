
% theta_all = [];
loss_his_all = [];
theta_all = [];
lanb1_all = [];lanb2_all = [];lanb3_all = [];lanb4_all = [];loss_real_all = [];
p1_all = [];p2_all = [];p3_all = [];p4_all = [];
max_iter = 100;
k = 200;
while k>0
    if k~=200
        theta = theta_initial();
        theta = Bound(theta, Fog, Task);
    end
    %%[theta, loss_history] = amsgrad(max_iter,theta,alpha1, alpha2, Beta,gamm,lanb1,lanb2,lanb3,lanb4,p1,p2,p3,p4,Fog,Task,Thing);
    [theta, loss_history] = AdamX(max_iter,theta,alpha1, alpha2, Beta,gamm,lanb1,lanb2,lanb3,lanb4,p1,p2,p3,p4,Fog,Task,Thing);
    %%%更新两个alpha
    alpha1 = min(1,max(0,theta+lanb1/p1));%%aerfa1更新
    center = 1/2 * ones(1,length(alpha2));
    a_ = theta+lanb2/p2 - 1/2;
    alpha2 = length(alpha2)^(1/2)/2 * a_/sum(a_.*a_)^(1/2) + center;
    %%%更新gamm
    sum_theta = zeros(1,task_num*T);
    for i = 1:task_num*T%%任务只能卸载到一个fog上
        for ii = 1:fog_num
            sum_theta(i) = sum_theta(i) + theta((i-1)*fog_num+ii);
        end
        gamm(i) = min(1,max(0,1-sum_theta(i) - lanb4(i)/p4(i)));
    end
    %%%更新beta
    fog_memory = zeros(1,fog_num);
    for i = 1:task_num%%每个任务
        for ii = 1:T%%任务的每个时间段
            for iii = 1:fog_num%%每个雾节点
                p_sign = theta((i-1)*T*fog_num+(ii-1)*fog_num+iii);
                memory = Task(i,1)* Task(i,2)^(ii-1) * p_sign;%%任务所需存储
                fog_memory(iii) = fog_memory(iii)+memory;%%累加看是否越界
            end
        end
    end
    for i = 1:fog_num
        Beta(i) = min(Fog(i,7),max(0,Fog(i,7)-fog_memory(i)-lanb3(i)/p3(i)));
    end
    %%%更新四个lanb
    lanb1 = lanb1 + p1.*(theta-alpha1);
    lanb2 = lanb2 + p2.*(theta-alpha2);
    for i = 1:fog_num
        lanb3(i) = lanb3(i) + p3(i)*(fog_memory(i)-Fog(i,7)+Beta(i));
    end
    for i = 1:task_num*T
        sum_theta = 0;
        for ii = 1:fog_num
            sum_theta = sum_theta + theta((i-1)*fog_num+ii);%%子任务只能卸载到一个fog上
        end
        lanb4(i) = lanb4(i) + p4(i)*(sum_theta + gamm(i) - 1);
    end
    

    loss_his_all = [loss_his_all;loss_history];%%记录拉格朗日函数值的变化曲线
%     theta_round = round(theta);
    loss_real_now = loss_real(theta, Task, Fog, Thing);
    loss_real_all = [loss_real_all,loss_real_now];%%记录真实的四舍五入的结果
    theta_all = [theta_all; theta];
    lanb1_all = [lanb1_all; lanb1];
    lanb2_all = [lanb2_all; lanb2];
    lanb3_all = [lanb3_all; lanb3];
    lanb4_all = [lanb4_all; lanb4];
    
    %%%更新四个p
    p1 = miu * p1;
    p2 = miu * p2;
    p3 = miu * p3;
    p4 = miu * p4;
    p1_all = [p1_all; p1];
    p2_all = [p2_all; p2];
    p3_all = [p3_all; p3];
    p4_all = [p4_all; p4];
    
    k = k-1;
end
