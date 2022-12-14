clear
close all
clc

addpath('MPCC_Solver/');

simN = 500;
% simN = 40;
isTrain = 1;

env = MPCC_Env;
% validateEnvironment(env)

obsInfo = env.getObservationInfo();
actInfo = env.getActionInfo();

rng(0);

if isTrain

    agent = rlTD3Agent(obsInfo, actInfo);
    
    opt = rlTrainingOptions( ...
        "MaxEpisodes",20000, ...
        "MaxStepsPerEpisode",3, ...
        "SaveAgentCriteria","EpisodeCount", ...
        "SaveAgentValue",5000, ...
        "SaveAgentDirectory",pwd + "/runs_4_params_qC_qL_qOmega_qV_reward_curvature_obs_pre_band/Agents");
    
    trainResults = train(agent, env, opt);
else
    load(pwd + "/runs_4_params_qC_qL_qOmega_qV_reward_curvature_obs_pre_band/Agents/Agent500.mat", "saved_agent");
    agent = saved_agent;
    Observation = env.reset();
    simOpts = rlSimulationOptions(...
        'MaxSteps',25);
    
    %     Action = getAction(agent, Observation);
    %     [Observation,Reward,IsDone,LoggedSignals] = env.step(Action);
    experience = sim(env,agent,simOpts);
    load Info_log.mat out;
    eC_log = out(1:2, :);
    v_log = out(3:4, :);
%     actions = experience.Action;
%     action = actions.CostWeights.Data;
    PlotInfo(eC_log, v_log, simN, 0.02, "other");
    simulation_interface;
end
