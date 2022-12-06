clear
close all
clc

addpath('MPCC_Solver/');

env = MPCC_Env;
% validateEnvironment(env)

obsInfo = env.getObservationInfo();
actInfo = env.getActionInfo();

rng(1);

agent = rlTD3Agent(obsInfo, actInfo);

opt = rlTrainingOptions( ...
    "MaxEpisodes",1000, ...
    "MaxStepsPerEpisode",25, ...
    "StopTrainingCriteria","AverageReward", ...
    "StopTrainingValue",300, ...
    "SaveAgentCriteria","EpisodeReward", ...
    "SaveAgentValue",200, ...
    "SaveAgentDirectory",pwd + "/runs2/Agents");

trainResults = train(agent, env, opt);

