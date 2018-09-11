% 1) synchronise the imu and robot data streams,
% 2) express robot orientation in GFR using the IMU data during static periods
% to derive a quaternion
% 3) simulate the accelerometer data use the real gyroscope data
% 4) validate that the euler angles derived from the quaternions are
% equivalent
function [] = main()
clear all;clc;close all;
addpath('.\CAHRS'); % path to CAHRS functions and class files
addpath('.\AESKF_functions'); % path to AESKF functions and class files
addpath('.\quaternion_functions');
addpath('.\Data');
rng(1);

sigma_gyr = 0.01;
cA = 0.1;
cM = 0.99;

N_VAR_GAM_AS = 8;
N_VAR_GAM_AL = 50;

N_VAR_GAM_M = 8;
fsMIMU      = 100;
delta_mag_b_xy = (2.5*10^-3) * fsMIMU;

for i = 1:6
if i == 1
file ='UpDown.mat'; 
elseif i == 2
file ='UpDown_90_deg_rot.mat'; 
elseif i == 3
file = 'LeftRight.mat'; 
elseif i == 4
file = 'LeftRight_90_deg_rot.mat'; 
elseif i == 5
file = 'ZigZag.mat'; 
elseif i == 6
file ='ZigZag_45_deg_rot.mat'; 
else
end
load(file);


ACC_VAR_THRESH = 12; % WIN = 1*fs
muAcc = 0.003;
muMag = 0.001;
timestamps = table2array(imu_real_sim_data(:,{'timestamps'}));
acc_cal = table2array(imu_real_sim_data(:,{'ImuAccX','ImuAccY','ImuAccZ'}));
gyr_cal = table2array(imu_real_sim_data(:,{'ImuGyrX','ImuGyrY','ImuGyrZ'}));
mag_cal = NaN(size(acc_cal));
WIN_SECS = 0.25;
VAR_WIN  = floor(fsMIMU*WIN_SECS); % NUM_SAMPLES

MOV_VAR_ACC_2 = movingvar(sum(acc_cal.^2,2),VAR_WIN);
bIsDynamic = MOV_VAR_ACC_2 > ACC_VAR_THRESH;
bIsDynamic(1:VAR_WIN-1) = true; % assume moving during start-up transient of variance calculation

figure;
subplot(2,1,1);plot([acc_cal,bIsDynamic]);
subplot(2,1,2);plot(MOV_VAR_ACC_2);

q_mea = table2array(imu_real_sim_data(:,{'qw','qx','qy','qz'}));

%% --- Real measurements from the smartphone
% CAHRS, fixed gain, 

[quats_cahrs] = ...
opMimuDynamicCAHRS_ArcTan('qInit',q_mea(1,:),...
'bDynamicMu',bIsDynamic,...
'dynamic_mu_acc',muAcc,'dynamic_mu_mag',muMag,...
'static_mu_acc',0.75,'static_mu_mag',0,...
'fs',fsMIMU,'Acc',acc_cal,'Mag',mag_cal,'Gyr',gyr_cal);


N_TIME = length(imu_real_sim_data.timestamps); 

i_static = (~bIsDynamic) & ([1:N_TIME]' < 1000);
mRef = 1;
gRef = mean(vecnormalize(acc_cal(i_static,:)));

[quats_aeskf, R_gamma_A_aeskf, avg_gamma_A_aeskf, ...
 gamma_A_aeskf, Pa_pri_aeskf, Pk_pos_aeskf, Ka_aeskf,...
 R_gamma_M_aeskf, avg_gamma_M_aeskf, ...
 gamma_M_aeskf, Pm_pri_aeskf, Pm_pos_aeskf, Km_aeskf,...
 ext_acc,mag_dis, gAcc,gMag] = ...
    wrapper_MIMU_AESKF(... 
        'q0',q_mea(1,:),'fs',fsMIMU,'N_VAR_GAM_M',N_VAR_GAM_M,...
        'N_VAR_GAM_AS',N_VAR_GAM_AS,'N_VAR_GAM_AL',N_VAR_GAM_AL,...
        'sigma_gyr',sigma_gyr,'cA',cA,'gRef',gRef,'cM',cM,'mRef',mRef,...
        'Acc',acc_cal,'Mag',mag_cal,'Gyr',gyr_cal,...
        'delta_b_xy',delta_mag_b_xy*mRef*mRef); 

est_eul_cahrs = rad2deg(quaternion2nautical(quats_cahrs));  % ahrs estimate 
est_eul_aeskf = rad2deg(quaternion2nautical(quats_aeskf)); % ahrs estimate2
tru_eul_mea   = rad2deg(quaternion2nautical(q_mea)); % truth measurement
        
for e = 1:3
    eulerAngErr = tru_eul_mea(:,e)-est_eul_cahrs(:,e); % order not important since error is abs
    greater180 = eulerAngErr > 180;  
    est_eul_cahrs(greater180,e) = est_eul_cahrs(greater180,e) + 360;
    % if difference is less than -180, add 360
    lesserN180 = eulerAngErr < -180;
    est_eul_cahrs(lesserN180,e) = est_eul_cahrs(lesserN180,e) - 360;
    eulerAngErr2 = tru_eul_mea(:,e)-est_eul_aeskf(:,e); % order not important since error is abs
    greater180 = eulerAngErr2 > 180;  
    est_eul_aeskf(greater180,e) = est_eul_aeskf(greater180,e) + 360;
    % if difference is less than -180, add 360
    lesserN180 = eulerAngErr2 < -180;
    est_eul_aeskf(lesserN180,e) = est_eul_aeskf(lesserN180,e) - 360;
end
%%
figure('name',['Real Phone Data Acc/Gyr CAHRS vs AESKF',file]);hsub=[];
hsub(1)=subplot(4,1,1);hold on;lgstr={};h=[];hz=zoom;set(hz,'Enable','on')
title('Roll');
ptime = 1:length(timestamps);%phonedata.time;
h(end+1)=plot(ptime,tru_eul_mea(:,1),'k','LineWidth',2);lgstr{end+1}='REF';
h(end+1)=plot(ptime,est_eul_cahrs(:,1),'oc','LineStyle','none');lgstr{end+1}='CAHRS';
h(end+1)=plot(ptime,est_eul_aeskf(:,1),'xb','LineStyle','none');lgstr{end+1}='CAHRS-IKF';
legend(h,lgstr,'Orientation','Horizontal');

segments = table2array(imu_real_sim_data(:,{'segment'}));
idx_empty = cellfun(@isempty,segments);
% find last empty at the beginning, < 10,000
seg_offset = find(idx_empty(1:10000)== 1, 1, 'last' );
u_segments = unique(segments(~idx_empty));
N_SEGMENTS = length(u_segments);
sync_segs = zeros(N_SEGMENTS,2);
for u = 1:N_SEGMENTS
    idx_seg = find(strcmp(segments(~idx_empty),u_segments(u)));
    idx_seg_beg = idx_seg(1);
    idx_seg_end = idx_seg(end);
    sync_segs(u,1:2) = [idx_seg_beg,idx_seg_end] + seg_offset;
end

sync_segs = reshape(sync_segs',[],1);


% stat_segs = reshape(phonedata.statSegments',[],1);
% % adjust stationary period for convergence
% sync_segs(2:end-1) = sync_segs(2:end-1);
% % adjust for algorithm convergence
% sync_segs(1) = sync_segs(1);
% % adjust for alignment between reference systems
% sync_segs(end) = sync_segs(end)+ t21; 
% stat_segs(end) = stat_segs(end)+ t21;
% sub_sync_segs = [sync_segs(1:6:end);sync_segs(6:6:end)];
% sub_stat_segs = [stat_segs(1:6:end);stat_segs(6:6:end)];
% mid_segs = floor(mean([sync_segs(1:6:end),sync_segs(6:6:end)] +1,2));
line(ptime(repmat(sync_segs +1,1,2))',repmat(ylim,18,1)','Color','k');

hsub(2)=subplot(4,1,2);hold on;lgstr={};h=[];
title('Pitch');
h(end+1)=plot(ptime,tru_eul_mea(:,2),'k','LineWidth',2);lgstr{end+1}='REF';
h(end+1)=plot(ptime,est_eul_cahrs(:,2),'om','LineStyle','none');lgstr{end+1}='CAHRS';
h(end+1)=plot(ptime,est_eul_aeskf(:,2),'xr','LineStyle','none');lgstr{end+1}='CAHRS-IKF';
line(ptime(repmat(sync_segs +1,1,2))',repmat(ylim,18,1)','Color','k');
legend(h,lgstr,'Orientation','Horizontal');

hsub(3)=subplot(4,1,3);hold on;lgstr={};h=[];
title('Error');
h(end+1)=plot(ptime,tru_eul_mea(:,1)-est_eul_cahrs(:,1),'--c');lgstr{end+1}='\phi_{CAHRS}';
h(end+1)=plot(ptime,tru_eul_mea(:,1)-est_eul_aeskf(:,1),'--b');lgstr{end+1}='\phi_{CAHRS-IKF}';
h(end+1)=plot(ptime,tru_eul_mea(:,2)-est_eul_cahrs(:,2),'--m');lgstr{end+1}='\theta_{CAHRS}';
h(end+1)=plot(ptime,tru_eul_mea(:,2)-est_eul_aeskf(:,2),'--r');lgstr{end+1}='\theta_{CAHRS-IKF}';        
line(ptime(repmat(sync_segs +1,1,2))',repmat(ylim,18,1)','Color','k');
legend(h,lgstr,'Orientation','Horizontal');

hsub(4)=subplot(4,1,4);hold on;lgstr={};h=[];
title('Error State Kalman Filter');
h(end+1)=plot(ptime,(R_gamma_A_aeskf),'k');lgstr{end+1}='\gamma_{a}^{2} -real';
h(end+1)=plot(ptime,((gamma_A_aeskf)),'c');lgstr{end+1}='\gamma_{a} -real';
h(end+1)=plot(ptime, Ka_aeskf,'g','LineWidth',2);lgstr{end+1}='k-real';
h(end+1)=plot(ptime,Pk_pos_aeskf,'r','LineWidth',2);lgstr{end+1}='Pk-real';
line(ptime(repmat(sync_segs +1,1,2))',repmat(ylim,18,1)','Color','k');
legend(h,lgstr,'Orientation','Horizontal');        
linkaxes(hsub,'x');    
       
% %% Calculate the RMSE of the segments
% colorscheme = 'cool';
% xlabels={'A','B','C','D','E','F','G','H','I'};
% ylabels={'CAHRS','AESKF'};
% ylabels={'',''};
% blogmap = true;
% NumTicks = 9;
% 
% rmse_segs = [sync_segs(1:6:end),sync_segs(6:6:end)];
% alphaSegs = cell(length(estIdx),1);
% rmse_segs(1,1) = 1000;
% [N_RUNS,~]=size(rmse_segs);
% 
% rse_real_cahrs = sqrt( (tru_eul_mea-est_eul_cahrs).^2 );
% rse_real_erkf = sqrt( (tru_eul_mea-est_eul_aeskf).^2 );
% 
% rmse_real_cahrs = nan(N_RUNS,2);
% rmse_real_erkf  = nan(N_RUNS,2);
% 
% for r = 1:N_RUNS
%     seg = [rmse_segs(r,1):rmse_segs(r,2)]';
%     alphaSegs(seg) = xlabels(r);
%     rmse_real_cahrs(r,:) = sum(rse_real_cahrs(seg,1:2))./length(seg);
%     rmse_real_erkf(r,:) = sum(rse_real_erkf(seg,1:2))./length(seg);
% end
% 
% rollHeatMapReal = [rmse_real_cahrs(:,1),...
%                    rmse_real_erkf(:,1)]';
% 
% pitchHeatMapReal = [rmse_real_cahrs(:,2),...
%                     rmse_real_erkf(:,2)]';
% 
% mincolor =  0;
% maxcolor = 20;
% 
% if expDays == 1
%     titleStr = sprintf('Up-Down');
%     filesuffix = 'UpDown.csv';
% elseif expDays == 2
%     titleStr = sprintf('Up-Down with 90%s Rotation',char(176));
%     filesuffix = 'UpDown_90_deg_rot.csv';
% elseif expDays == 3
%     titleStr = sprintf('Left-Right');
%     filesuffix = 'LeftRight.csv';    
% elseif expDays == 4
%     titleStr = sprintf('Left-Right with 90%s Rotation',char(176));
%     filesuffix = 'LeftRight_90_deg_rot.csv';
% 
% elseif expDays == 5
%     titleStr = sprintf('Zig-Zag');
%     filesuffix = 'ZigZag.csv';    
% elseif expDays == 6
%     titleStr = sprintf('Zig-Zag + 45%s ',char(176));
%     filesuffix = 'ZigZag_45_deg_rot.csv';        
% else
%     
% end           
% %           
% 
% [p_imu_roll] = signrank(rmse_real_cahrs(:,1),rmse_real_erkf(:,1),'alpha',0.05,'tail','both');
% [p_imu_pitch]= signrank(rmse_real_cahrs(:,2),rmse_real_erkf(:,2),'alpha',0.05,'tail','both');
% fprintf('%s\n', titleStr);
% fprintf('imu: %s: $p$ = %0.3f, %s: $p$= %0.3f \n','$\phi$',p_imu_roll,'$\theta$', p_imu_pitch);
% 
% 
% h_fig = updateFigureContents(['Heat Map RMSE - Larger Font - ',titleStr]);
% set(h_fig,'Units', 'Centimeters','Position', [0.5, 0, 9, 6], ...
%     'PaperUnits', 'Centimeters', 'PaperSize', [9, 6]);
% % subplot = @(m,n,p) ...
% %     subtightplot (m, n, p, [0.075 0.01], [0.1 0.1], [0.06 0.1]);
% 
% subplot(2,1,1)
% himg = heatmap(rollHeatMapReal,xlabels,[],'%1.2f',...
%     'Colormap',colorscheme,'UseLogColormap', blogmap, ...
%     'MinColorValue', mincolor, 'MaxColorValue', maxcolor,...
%     'GridLines', ':','FontSize',10);
% 
% [RotX,RotY,Axis,XTicks,XTickLabels,YTicks,YTickLabels] =...
%     XYrotalabel(0,90,gca,2:2:8,xlabels(2:2:8),1:2,ylabels,[],[]);
% set(gca,'XTickLabel',[]);
% 
% 
% subplot(2,1,2)
% himg = heatmap(pitchHeatMapReal,xlabels,[],'%1.2f',...
%     'Colormap',colorscheme,'UseLogColormap', blogmap, ...
%     'MinColorValue', mincolor, 'MaxColorValue', maxcolor,...
%     'GridLines', ':','FontSize',10);
% 
% [RotX,RotY,Axis,XTicks,XTickLabels,YTicks,YTickLabels] =...
%     XYrotalabel(0,90,gca,2:2:8,xlabels(2:2:8),1:2,ylabels,[],[]);
% set(gca,'XTickLabel',[]);
% 
% set(gcf,'NextPlot','add');
% axes;
% 
% 
% h = title(titleStr,'FontSize',12);
% set(gca,'Visible','off');
% set(h,'Visible','on');
end
end


