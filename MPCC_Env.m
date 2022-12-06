classdef MPCC_Env < rl.env.MATLABEnvironment
    %MPCC_ENV: Template for defining custom environment in MATLAB.    
    
    %% Properties (set properties' attributes accordingly)
    properties
        % Specify and initialize environment's necessary properties    
        CarModel = 'ORCA'

        MPC_vars
        ModelParams

        % Simulation lenght and plotting
        simN = 20
        N = 40
        %0=no plots, 1=plot predictions
        plotOn = 1
        %0=real time iteration, 1=fixed number of QP iterations, 2=fixed number of damped QP iterations
        QP_iter = 2
        % number of cars 
        % there are two examples one with no other cars and one with 4 other cars
        % (inspired by the set up shown in the paper)
        % n_cars = 1; % no other car
        n_cars = 5 % 4 other cars
        Y

        % track, traj and border
        track
        track2
        trackWidth
        traj
        borders
        tl
        TrackMPC

        % log
        X_log
        U_log
        B_log
        qpTime_log
        % used to further cauculate the mean and max value along one step
        obs_log = zeros(1, 20)

        last_closestIdx
        
        % Angle at which to fail the episode (radians)
        AngleThreshold = 12 * pi/180
        
        % Distance at which to fail the episode
        DisplacementThreshold = 2.4
        
        % Reward each time step the cart-pole is balanced
        RewardForNotFalling = 1
        
        % Penalty when the cart-pole fails to balance
        PenaltyForFalling = -10 
    end
    
    properties
        % Initialize system state [x,y,phi,vx,vy,omega,theta]'
        State = zeros(7,41)
        x0 = zeros(7,1)
        x = zeros(7,41)
        u = zeros(3,40)
        uprev = zeros(3,1)
        b
    end
    
    properties(Access = protected)
        % Initialize internal flag to indicate episode termination
        IsDone = false        
    end

    %% Necessary Methods
    methods              
        % Contructor method creates an instance of the environment
        % Change class name and constructor name accordingly
        function this = MPCC_Env()
            % Initialize Observation settings
            ObservationInfo = rlNumericSpec([5 1]);
            ObservationInfo.Name = 'Vehicle States';
%             ObservationInfo.Description = 'x_phy, y_phy, x_virt, y_virt, eC, eL';
            ObservationInfo.Description = 'eC_error_mean, eC_error_max, driving_length, curvature_x, curvature_y';
            
            % Initialize Action settings   
            ActionInfo = rlNumericSpec([1 1]);
            ActionInfo.Name = 'Cost Weights';
            ActionInfo.Description = 'qC';
            ActionInfo.LowerLimit = 0.001;
            ActionInfo.UpperLimit = 100;
            
            % The following line implements built-in functions of RL env
            this = this@rl.env.MATLABEnvironment(ObservationInfo,ActionInfo);

            % Load Parameters
            this.MPC_vars = getMPC_vars(this.CarModel);
            this.ModelParams = getModelParams(this.MPC_vars.ModelNo);
            % choose optimization interface options: 'Yalmip','CVX','hpipm','quadprog'
            this.MPC_vars.interface = 'hpipm';
            
            % import an plot track
            load MPCC_Solver/MPCC/Tracks/track2.mat track2
            % shrink track by half of the car widht plus safety margin
            % TODO implement orientation depending shrinking in the MPC constraints
            safteyScaling = 1.5;
            [this.track,this.track2] = borderAdjustment(track2,this.ModelParams,safteyScaling);
            
            this.trackWidth = norm(this.track.inner(:,1)-this.track.outer(:,1));
            % plot shrinked and not shrinked track 
            figure(1);
            plot(this.track.outer(1,:),this.track.outer(2,:),'r')
            hold on
            plot(this.track.inner(1,:),this.track.inner(2,:),'r')
            plot(this.track2.outer(1,:),this.track2.outer(2,:),'k')
            plot(this.track2.inner(1,:),this.track2.inner(2,:),'k')

            % Fit spline to track
            % TODO spline function only works with regular spaced points.
            % Fix add function which given any center line and bound generates equlally
            % space tracks.
            [this.traj, this.borders] =splinify(this.track);
            this.tl = this.traj.ppy.breaks(end);

            
            
            % store all data in one struct
            this.TrackMPC = struct('traj',this.traj,'borders',this.borders,'track_center',this.track.center,'tl',this.tl);

            % Initialize logging arrays
            this.X_log = zeros(this.ModelParams.nx*(this.MPC_vars.N+1),this.simN);
            this.U_log = zeros(3*this.MPC_vars.N,this.simN);
            this.B_log = zeros(4*this.MPC_vars.N,this.simN);
            this.qpTime_log = zeros(1,this.simN);
            
            % Initialize property values and pre-compute necessary values
%             updateActionInfo(this);
        end
        
        % Apply system dynamics and simulates the environment with the 
        % given action for one step.
        function [Observation,Reward,IsDone,LoggedSignals] = step(this,Action)
            qC = Action;
            this.MPC_vars.qC = qC;

            % Simulation
            for i = 1: this.simN
                
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %%%% MPCC-Call %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
                % augment state and inputs by shifting previus optimal solution
                [this.x,this.u] = augState(this.x,this.u,this.x0,this.MPC_vars,this.ModelParams,this.tl);
                %  formulate MPCC problem and solve it
                if this.QP_iter == 0
                    [this.x, this.u, this.b, ~,info] = optimizer_mpcc(this.TrackMPC,this.MPC_vars,this.ModelParams, this.n_cars, this.Y, this.x, this.u, this.x0, this.uprev);
                    this.qpTime_log(i) = info.QPtime;
                elseif this.QP_iter == 1
                    % doing multiple "SQP" steps
                    for k = 1:2
                        [this.x, this.u, this.b, ~,info] = optimizer_mpcc(this.TrackMPC,this.MPC_vars,this.ModelParams, this.n_cars, this.Y, this.x, this.u, this.x0, this.uprev);
                        this.qpTime_log(i) = this.qpTime_log(i) + info.QPtime;
                    end
                elseif this.QP_iter == 2
                    % doing multiple damped "SQP" steps
                    for k = 1:2
                        Iter_damping = 0.75; % 0 no damping
                        [x_up, u_up, this.b, ~,info] = optimizer_mpcc(this.TrackMPC,this.MPC_vars,this.ModelParams, this.n_cars, this.Y, this.x, this.u, this.x0, this.uprev);
                        this.x = Iter_damping*this.x + (1-Iter_damping)*x_up;
                        this.u = Iter_damping*this.u + (1-Iter_damping)*u_up;
                        this.qpTime_log(i) = this.qpTime_log(i) + info.QPtime;
                    end
                else
                    error('invalid QP_iter value')
                end
            
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %%%% simulate system %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
                this.x0 = SimTimeStep(this.x(:,1),this.u(:,1),this.MPC_vars.Ts,this.ModelParams)';
                this.x0 = unWrapX0(this.x0);
                [ theta, this.last_closestIdx] = findTheta(this.x0,this.track.center,this.traj.ppx.breaks,this.trackWidth,this.last_closestIdx);
                this.x0(this.ModelParams.stateindex_theta) = theta;
                this.uprev = this.u(:,1);
                
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %%%% plotting and logging %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            
                if this.plotOn == 1
                    PlotPrediction(this.x,this.u,this.b,this.Y,this.track,this.track2,this.traj,this.MPC_vars,this.ModelParams)
                end
                
                % log predictions and time
                this.X_log(:,i) = reshape(this.x,(this.N+1)*7,1);
                this.U_log(:,i) = reshape(this.u,(this.N)*3,1);
                this.B_log(:,i) = reshape(this.b,this.N*4,1);
                
                % store the necesseary info in each sampling step used for later observation calculation
                Xk = this.x(:,1);
                x_phys = Xk(1);
                y_phys = Xk(2);
                theta_virt=mod(Xk(end),this.traj.ppx.breaks(end));
%                 x_virt=ppval(this.traj.ppx,theta_virt);
%                 y_virt=ppval(this.traj.ppy,theta_virt);
                [eC, eL] = this.getErrors(this.traj, theta_virt,x_phys,y_phys);
                if i == 1
                    first_theta = mod(Xk(end),this.traj.ppx.breaks(end));
                end

                if i == this.simN
                    last_theta = mod(Xk(end),this.traj.ppx.breaks(end));
                end
                this.obs_log(:, i) = eC;

            end
            
            i = this.MPC_vars.N+1; % observation from N
            Xk = this.x(:,1);
            x_phys = Xk(1);
            y_phys = Xk(2);
            theta_virt=mod(Xk(end),this.traj.ppx.breaks(end));
            x_virt=ppval(this.traj.ppx,theta_virt);
            y_virt=ppval(this.traj.ppy,theta_virt);
%             [eC, eL] = this.getErrors(this.traj, theta_virt,x_phys,y_phys);
% 
%             Observation = [x_phys;y_phys;x_virt;y_virt;eC;eL];
%             this.State = this.x;
            this.obs_log = abs(this.obs_log); 
            if last_theta < first_theta
                driving_length = (last_theta + this.tl - first_theta) / this.tl;
            else
                driving_length = (last_theta - first_theta) / this.tl;
            end
            curvature_x = ppval(this.traj.ddppx,theta_virt);
            curvature_y = ppval(this.traj.ddppy,theta_virt);
            Observation = [mean(this.obs_log); max(this.obs_log); driving_length; curvature_x; curvature_y];
            this.State = this.x;

            LoggedSignals = [];
            
            
            % Check terminal condition
            IsDone = false;
            this.IsDone = IsDone;
            
            % Get reward
            Reward = getReward(this, this.obs_log, driving_length);
            
            % (optional) use notifyEnvUpdated to signal that the 
            % environment has been updated (e.g. to update visualization)
            notifyEnvUpdated(this);
        end
        
        % Reset environment to initial state and output initial observation
        function InitialObservation = reset(this)
            %% Define starting position
            startIdx = 1; %point (in terms of track centerline array) allong the track 
            % where the car starts, on the center line, aligned with the track, driving
            % straight with vx0
            %since the used bicycle model is not well defined for slow velocities use vx0 > 0.5
            this.N = this.MPC_vars.N;
            Ts = this.MPC_vars.Ts;
            if this.CarModel == "ORCA"
                vx0 = 1;
            elseif this.CarModel == "FullSize"
                vx0 = 15;
            end
            
            % find theta that coresponds to the 10th point on the centerline
            [theta, ~] = findTheta([this.track.center(1,startIdx),this.track.center(2,startIdx)],this.track.center,this.traj.ppx.breaks,this.trackWidth,startIdx);
            
            this.x0 = [this.track.center(1,startIdx),this.track.center(2,startIdx),... % point on centerline
                  atan2(ppval(this.traj.dppy,theta),ppval(this.traj.dppx,theta)),... % aligned with centerline
                  vx0 ,0,0,theta]'; %driving straight with vx0, and correct theta progress

            % the find theta function performs a local search to find the projection of
            % the position onto the centerline, therefore, we use the start index as an
            % starting point for this local search
            this.last_closestIdx = startIdx;

            % First initial guess
            this.x = repmat(this.x0,1,this.N+1); % all points identical to current measurment
            % first inital guess, all points on centerline aligned with centerline
            % spaced as the car would drive with vx0
            for i = 2:this.N+1
                theta_next = this.x(this.ModelParams.stateindex_theta,i-1)+Ts*vx0;
                phi_next = atan2(ppval(this.traj.dppy,theta_next),ppval(this.traj.dppx,theta_next));
                % phi_next can jump by two pi, make sure there are no jumps in the
                % initial guess
                if (this.x(this.ModelParams.stateindex_phi,i-1)-phi_next) < -pi
                    phi_next = phi_next-2*pi;
                end
                if (this.x(this.ModelParams.stateindex_phi,i-1)-phi_next) > pi
                    phi_next = phi_next+2*pi;
                end
                this.x(:,i) = [ppval(this.traj.ppx,theta_next),ppval(this.traj.ppy,theta_next),... % point on centerline
                          phi_next,... % aligned with centerline
                          vx0 ,0,0,theta_next]'; %driving straight with vx0, and correct theta progress
            end
            
            this.u = zeros(3,this.N); % zero inputs
            this.uprev = zeros(3,1); % last input is zero

            
            % Ohter cars
            this.Y = ObstacelsState(this.track,this.traj,this.trackWidth,this.n_cars);
            
            if size(this.Y,2) ~= this.n_cars-1
                error('n_cars and the number of obstacles in "Y" does not match')
            end

            

            % initializtion
            % solve problem 5 times without applying input
            % inspiered by sequential quadratic programming (SQP)
            for i = 1:5
                % formulate MPCC problem and solve it
                Iter_damping = 0.5; % 0 no damping
                [x_up, u_up, this.b, ~,~] = optimizer_mpcc(this.TrackMPC,this.MPC_vars,this.ModelParams, this.n_cars, this.Y, this.x, this.u, this.x0, this.uprev);
                this.x = Iter_damping*this.x + (1-Iter_damping)*x_up;
                this.u = Iter_damping*this.u + (1-Iter_damping)*u_up;
            
                if this.plotOn == 1
                    % plot predictions
                    PlotPrediction(this.x,this.u,this.b,this.Y,this.track,this.track2,this.traj,this.MPC_vars,this.ModelParams)
                end
            end
            
            % TODO: sum all steps
            % TODO: experience choose the observation from x0 or xN
            i = this.MPC_vars.N+1; % observation from N
            Xk = this.x(:,1); % observation from 1 or N
            x_phys = Xk(1);
            y_phys = Xk(2);
            theta_virt=mod(Xk(end),this.traj.ppx.breaks(end));
            x_virt=ppval(this.traj.ppx,theta_virt);
            y_virt=ppval(this.traj.ppy,theta_virt);
            [eC, eL] = this.getErrors(this.traj, theta_virt,x_phys,y_phys);

%             InitialObservation = [x_phys;y_phys;x_virt;y_virt;eC;eL];
            curvature_x = ppval(this.traj.ddppx,theta_virt);
            curvature_y = ppval(this.traj.ddppy,theta_virt);
            InitialObservation = [eC; eC; 0; curvature_x; curvature_y];
            this.State = this.x;
            
            % (optional) use notifyEnvUpdated to signal that the 
            % environment has been updated (e.g. to update visualization)
            notifyEnvUpdated(this);
        end
    end
    %% Optional Methods (set methods' attributes accordingly)
    methods               
        % Helper methods to create the environment
        function [eC, eL] = getErrors(~, pathinfo, theta_virt,x_phys,y_phys)
            dxdth=ppval(pathinfo.dppx,theta_virt); % d x / d theta
            dydth=ppval(pathinfo.dppy,theta_virt); % d y / d theta
        
            % virtual positions
            x_virt=ppval(pathinfo.ppx,theta_virt);
            y_virt=ppval(pathinfo.ppy,theta_virt);
            
            phi_virt=atan2(dydth,dxdth);
            
            % define these to reduce calls to trig functions
            sin_phi_virt = sin(phi_virt);
            cos_phi_virt = cos(phi_virt);
        
            % contouring and lag error estimates
            eC = -sin_phi_virt*(x_virt - x_phys) + cos_phi_virt*(y_virt - y_phys);
            eL =  cos_phi_virt*(x_virt - x_phys) + sin_phi_virt*(y_virt - y_phys);
           
        end

        % Discrete force 1 or 2
        function force = getForce(this,action)
            if ~ismember(action,this.ActionInfo.Elements)
                error('Action must be %g for going left and %g for going right.',-this.MaxForce,this.MaxForce);
            end
            force = action;           
        end
        % update the action info based on max force
        function updateActionInfo(this)
            this.ActionInfo.Elements = this.MaxForce*[-1 1];
        end
        
        % Reward function
        function Reward = getReward(this, obs_log, driving_length)
%             Xk = this.x(:,1); % observation from 1
%             x_phys = Xk(1);
%             y_phys = Xk(2);
%             theta_virt=mod(Xk(end),this.traj.ppx.breaks(end));
% %             x_virt=ppval(this.traj.ppx,theta_virt);
% %             y_virt=ppval(this.traj.ppy,theta_virt);
%             [eC, eL] = this.getErrors(this.traj, theta_virt,x_phys,y_phys);
% %             Reward = exp(-((eC * eC) / 0.001 + (eL * eL) / 0.00001));
            
            Reward = driving_length * 25;
%             mean_eC = mean(obs_log);
%             shifted_length = driving_length * 25 - 1; % [0,1] to [-1, 0]
%             error_reward = exp(-(mean_eC * mean_eC) / 0.001);
%             length_reward = exp(shifted_length);
%             Reward = length_reward;
%             Reward = 0.5 * error_reward + 0.5 * length_reward;
%             Reward = 10* Reward;
        
        end
        
        % (optional) Visualization method
        function plot(this)
            % Initiate the visualization
            
            % Update the visualization
            envUpdatedCallback(this)
        end
        
%         % (optional) Properties validation through set methods
%         function set.State(this,state)
%             validateattributes(state,{'numeric'},{'finite','real','vector','numel',4},'','State');
%             this.State = double(state(:));
%             notifyEnvUpdated(this);
%         end
%         function set.HalfPoleLength(this,val)
%             validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','HalfPoleLength');
%             this.HalfPoleLength = val;
%             notifyEnvUpdated(this);
%         end
%         function set.Gravity(this,val)
%             validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','Gravity');
%             this.Gravity = val;
%         end
%         function set.CartMass(this,val)
%             validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','CartMass');
%             this.CartMass = val;
%         end
%         function set.PoleMass(this,val)
%             validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','PoleMass');
%             this.PoleMass = val;
%         end
%         function set.MaxForce(this,val)
%             validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','MaxForce');
%             this.MaxForce = val;
%             updateActionInfo(this);
%         end
%         function set.Ts(this,val)
%             validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','Ts');
%             this.Ts = val;
%         end
%         function set.AngleThreshold(this,val)
%             validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','AngleThreshold');
%             this.AngleThreshold = val;
%         end
%         function set.DisplacementThreshold(this,val)
%             validateattributes(val,{'numeric'},{'finite','real','positive','scalar'},'','DisplacementThreshold');
%             this.DisplacementThreshold = val;
%         end
%         function set.RewardForNotFalling(this,val)
%             validateattributes(val,{'numeric'},{'real','finite','scalar'},'','RewardForNotFalling');
%             this.RewardForNotFalling = val;
%         end
%         function set.PenaltyForFalling(this,val)
%             validateattributes(val,{'numeric'},{'real','finite','scalar'},'','PenaltyForFalling');
%             this.PenaltyForFalling = val;
%         end
    end
    
    methods (Access = protected)
        % (optional) update visualization everytime the environment is updated 
        % (notifyEnvUpdated is called)
        function envUpdatedCallback(this)
        end
    end
end