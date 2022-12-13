clear
close all
clc

addpath('MPCC_Solver/');

isTrain = 1;

env = MPCC_Env;
% validateEnvironment(env)

obsInfo = env.getObservationInfo();
actInfo = env.getActionInfo();

rng(0);

if isTrain

    agent = rlTD3Agent(obsInfo, actInfo);
    
    opt = rlTrainingOptions( ...
        "MaxEpisodes",2000, ...
        "MaxStepsPerEpisode",25, ...
        "SaveAgentCriteria","EpisodeReward", ...
        "SaveAgentValue",3.1, ...
        "SaveAgentDirectory",pwd + "/runs_3_params_qC_qL_qOmega_reward_v_eC/Agents");
    
    trainResults = train(agent, env, opt);
else
    load("runs2/Agents/Agent5.mat", "saved_agent");
    agent = saved_agent;
    Observation = env.reset();
    simOpts = rlSimulationOptions(...
        'MaxSteps',25);
    
    %     Action = getAction(agent, Observation);
    %     [Observation,Reward,IsDone,LoggedSignals] = env.step(Action);
    experience = sim(env,agent,simOpts);
    actions = experience.Action;
    action = actions.CostWeights.Data;
end
