function [  ] = PlotAction( Action, MPC_vars, simN )
    
%     N = MPC_vars.N;
    Ts = MPC_vars.Ts;
    figure(4)
    n = length(Action);
    subplot(n,1,1)
    Action_remap = repmat(Action,1,simN+1);
    plot([0:simN]*Ts,Action_remap(1,:))
    xlabel('time [s]')
    ylabel('qC [-]')
    subplot(n,1,2)
    plot([0:simN]*Ts,Action_remap(2,:))
    xlabel('time [s]')
    ylabel('qL [-]')
    subplot(n,1,3)
    plot([0:simN]*Ts,Action_remap(3,:))
    xlabel('time [s]')
    ylabel('qOmega [-]')
    subplot(n,1,4)
    plot([0:simN]*Ts,Action_remap(4,:))
    xlabel('time [s]')
    ylabel('rVtheta [-]')

end