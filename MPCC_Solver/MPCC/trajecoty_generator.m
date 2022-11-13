% this file is adapted from MPCC
% https://github.com/alexliniger/MPCC

%% Path Generation Script
clear
close all
clc

%% add spline library
addpath('splines');

%% load Parameters
CarModel = 'ORCA';
% CarModel = 'FullSize';

MPC_vars = getMPC_vars(CarModel);
ModelParams=getModelParams(MPC_vars.ModelNo);
% choose optimization interface options: 'Yalmip','CVX','hpipm','quadprog'
MPC_vars.interface = 'hpipm';

nx = ModelParams.nx;
nu = ModelParams.nu;
N = MPC_vars.N;
Ts = MPC_vars.Ts;
%% import an plot track
% use normal ORCA Track
load Tracks/track2.mat

safteyScaling = 1.5;
[track,track2] = borderAdjustment(track2,ModelParams,safteyScaling);

trackWidth = norm(track.inner(:,1)-track.outer(:,1));
% plot shrinked and not shrinked track 
figure(1);
plot(track.outer(1,:),track.outer(2,:),'r')
hold on
plot(track.inner(1,:),track.inner(2,:),'r')
plot(track2.outer(1,:),track2.outer(2,:),'k')
plot(track2.inner(1,:),track2.inner(2,:),'k')

%% Simulation length and plotting
simN = 500;
%0=no plots, 1=plot predictions
plotOn = 1;
%0=real time iteration, 1=fixed number of QP iterations, 2=fixed number of damped QP iterations
QP_iter = 2;
% number of cars 
% there are two examples one with no other cars and one with 4 other cars
% (inspired by the set up shown in the paper)
% n_cars = 1; % no other car
n_cars = 5; % 4 other cars
