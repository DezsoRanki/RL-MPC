function [  ] = PlotInfo(eC_log,v_log, simN,Ts,type)

figure(5)
% subplot(1,1,1)
if type == "baseline"
%     plot([0:simN-1]*Ts,eC_log, 'r')
    plot(eC_log(1,:), eC_log(2,:), 'r')
    hold on
else
%     plot([0:simN-1]*Ts,eC_log, 'g')
    plot(eC_log(1,:), eC_log(2,:), 'g')
    hold on
end
% xlabel('time [s]')
xlabel('length [m]')
ylabel('eC [m]')

figure(6)
% subplot(1,1,1)
if type == "baseline"
%     plot([0:simN-1]*Ts,v_log, 'r')
    plot(v_log(1,:), v_log(2,:), 'r')
    hold on
else
%     plot([0:simN-1]*Ts,v_log, 'g')
    plot(v_log(1,:), v_log(2,:), 'g')
    hold on
end
xlabel('length [m]')
ylabel('v [m / s]')