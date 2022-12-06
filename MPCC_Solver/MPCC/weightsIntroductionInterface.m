function [qC, qL, rD, rDelta] = weightsIntroductionInterface(action, currentN)
% action: interface from RL
% currentN: current simulation step

% initialisation
qC = 0.1000;
qL = 1000;
rD = 1e-4;
rDelta = 1e-4;

% update each Tsw
n = floor(Tsw / Ts);
if mod(currentN, n) == 0
    qC = action.qC;
    qL = action.qL;
    rD = action.rD;
    rDelta = action.rDelta;
end

% % TODO: update each Tsw
% for i = 1:Tep/Tsw % TODO: control with time
%     qC = action.qC;
%     qL = action.qL;
%     rD = action.rD;
%     rDelta = action.rDelta;
% end

end