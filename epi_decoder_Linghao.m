function [data_packets_csv,err_packet_idxs,err_all_idxs]=epi_decoder(path,plot_signal,param_names)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
%   ephi_auioprocess: A function that decodes the audio data in         % 
%   an .avi file recorded by epiphan into a .csv spreadsheet.           %      
%   input arguments:                                                    %
%   path: path directory of the input .avi file                         %
%   plot_signal: should the raw signal be plotted (true/false)          %
%   param_names: the header used for the output .csv file               %
%   outputs:                                                            %
%   data_packets_csv:an array of recieved datapackets as csv strings    %
%   err_packet_idxs: indexes of the corrupt packets                     %
%   err_all_idxs:indexes of all data flow errors                        %
%   written by :                                                        %
%               Soheil Hor                                              %
%               July 2017                                               %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% This file is modified for gaze tracker
% Irene Tong, July 2018
%%
%%%%%%%%%%%%%%%%% reading data
raw_signal=audioread(path);
conditioned_signal=round(raw_signal/range(raw_signal)*256);%%%% normalise for the the effect of sound volume

edges_signal=diff(conditioned_signal>127);%%%% detect the starting and ending squences

l2h_edges_pos=find(edges_signal==1);%%%% rising edges
h2l_edges_pos=find(edges_signal==-1);%%%% falling edges

pulse_width=h2l_edges_pos(1:min(length(h2l_edges_pos),length(l2h_edges_pos)))-l2h_edges_pos(1:min(length(h2l_edges_pos),length(l2h_edges_pos)));%%%% width of each control pulse in the raw signal

pulse_start=find(pulse_width==19);%%%% start pulse sequence
pulse_end=find(pulse_width==9);%%%% end pulse sequence
if(min(length(pulse_start),length(pulse_end))<1)%%%% if there are no packets
   disp('Error: No data found in file!'); 
   return; 
end

%%
%%%%%%%%%%%%%% find and fix errors

if(pulse_end(1)<pulse_start(1))%%%% if there is an extra end pulse at the start of the file
    pulse_end=pulse_end(1+(1:(size(pulse_end,1)-1)));%%%% remove the extra end pulse
else
    pulse_end=pulse_end(1:min(length(pulse_start),length(pulse_end)));%%%% remove the extra end pulse
end

if(size(pulse_start,1)~=size(pulse_end,1))%%%% force the size of the two arrays to be the same by removing the extra pulses from the end
    pulse_start=pulse_start(1:min(size(pulse_start,1),size(pulse_end,1)));
    pulse_end=pulse_end(1:(size(pulse_start,1)));
end   

s2s=(pulse_start(2:end)-pulse_start(1:(end-1)));%%%% start to start distance
e2e=(pulse_end(2:end)-pulse_end(1:(end-1)));%%%% end to end distance

err_start=diff(diff(s2s)~=0)>0;%%%% error in start to start distance
err_end=diff(diff(e2e)~=0)>0;%%%% error in end to end distance
err_all_idxs=l2h_edges_pos((err_start|err_end));%%%% all of errors

err_packet=s2s~=e2e;%%%% an error in a packet
err_packet_idxs=zeros(length(err_all_idxs),1);

pulse_end_tmp=pulse_end;
pulse_start_tmp=pulse_start;
%%%%%%%%%%%%%%%%%% removing corrupted packets one by one starting from
%%%%%%%%%%%%%%%%%% begining of the file:
idx=1;
while(sum(err_packet>0))%%%% while there are still corrupted packets
    err_packet_idx=find(err_packet,1);%%%% find the first one
    err_packet_idxs(idx)=l2h_edges_pos(err_packet_idx-1);%%%% save the index
    idx=idx+1;
    if(e2e(err_packet_idx)<s2s(err_packet_idx)) %%%% depending on the part of the packet that is corrupted (end or start)
       pulse_end_tmp=pulse_end_tmp((1:end)~=(err_packet_idx+1));%%%% remove the extra end pulse
    else
       pulse_start_tmp=pulse_start_tmp((1:end)~=(err_packet_idx+1));%%%% remove the extra start pulse        
    end
    
    if(size(pulse_start_tmp,1)~=size(pulse_end_tmp,1))%%%% make the arrays the same size by cutting from the end
        pulse_start_tmp=pulse_start_tmp(1:min(size(pulse_start_tmp,1),size(pulse_end_tmp,1)));
        pulse_end_tmp=pulse_end_tmp(1:(size(pulse_start_tmp,1)));
    end 
    
    s2s=(pulse_start_tmp(2:end)-pulse_start_tmp(1:(end-1)));%%%% calculate the new start to start distance
    e2e=(pulse_end_tmp(2:end)-pulse_end_tmp(1:(end-1)));%%%% calculate the new end to end distance
    err_packet=s2s~=e2e;%%%% calculate the new error    
end
err_packet_idxs=err_packet_idxs(err_packet_idxs>0);%%%% remove the extra zeros in the vector

if(size(err_packet_idxs,1)>0)%%%% if there were any corrupted packets:
    disp('Warning: Corrupt packets detected!');
    disp('Number of corrupted data packets:'+string(size(err_packet_idxs,1)));
    disp('Index of corrupted packets:');
    disp((err_packet_idxs));
end

%%

%%%%%%%%%%%%%%%%%%%%% save data to file

pulse_end=pulse_end_tmp;
pulse_start=pulse_start_tmp;
starts=l2h_edges_pos(pulse_start);%%%% index of start of each packet
ends=l2h_edges_pos(pulse_end);%%%% index of end of each packet

packet_pos=[starts+19+10,ends-10];%%%% remove the start and end pulse sequences from each packet
data_packet_pos=packet_pos(packet_pos(:,2)~=packet_pos(:,1),:);%%%% index of the actual data in each packet
data_packets_retrieved=cell(length(data_packet_pos),1);
for i1=1:size(data_packet_pos,1)
    packet_data_org=(conditioned_signal((data_packet_pos(i1,1)+1):(data_packet_pos(i1,2)))');%%%% retrieve data
    data_packets_retrieved(i1)= {uint16(typecast(int8(round(packet_data_org)),'uint8'))};%%%% convert the 16 bit signal value to the actual data
end

no_of_packets=length(data_packet_pos);%%%% number of recieved packets

%%%% Generate an estimate of the corresponding frame number and time point
%%%% in the video: starting position on the audio signal, starting position
%%%% in the video, and corresponding hour, minute, second and milisecond in the video
des=[data_packet_pos(:,1),floor(data_packet_pos(:,1)/48000*30),floor(data_packet_pos(:,1)/48000/3600),floor(mod(data_packet_pos(:,1)/48000,3600)/60),floor(mod(data_packet_pos(:,1)/48000,60)),floor(mod(data_packet_pos(:,1)/48,1000))];

data_packets_csv=cell(no_of_packets,1);
for i1=2:no_of_packets %%%% add the time and video frame data to the data packet
    strtmp=sprintf('%d,%d,%2d:%2d:%2d:%3d,\n',des(i1,:));
    data_packets_csv(i1)={[strtmp,cell2mat(data_packets_retrieved(i1))]'};
end

if(~exist('param_names','var'))%%%% The header for the csv file
    %%param_names_robot= sprintf('Time_stamp,');%;,Davinci_tip_px,Davinci_tip_py,Davinci_tip_pz,Davinci_cam_px,Davinci_cam_py,Davinci_cam_pz,Davinci_cam_o0,Davinci_cam_o1,Davinci_cam_o2,Davinci_cam_o3,Davinci_cam_o4,Davinci_cam_o5,Davinci_cam_o6,Davinci_cam_o7,Davinci_cam_o8,Motor_axial_p,Motor_rot_ang,');
    %param_names_robot= sprintf('Time_stamp,api_cnt,manipulatorIndex,Davinci_tip_px,Davinci_tip_py,Davinci_tip_pz,Davinci_tip_o0,Davinci_tip_o1,Davinci_tip_o2,Davinci_tip_o3,Davinci_tip_o4,Davinci_tip_o5,Davinci_tip_o6,Davinci_tip_o7,Davinci_tip_o8,Davinci_cam_px,Davinci_cam_py,Davinci_cam_pz,Davinci_cam_o0,Davinci_cam_o1,Davinci_cam_o2,Davinci_cam_o3,Davinci_cam_o4,Davinci_cam_o5,Davinci_cam_o6,Davinci_cam_o7,Davinci_cam_o8,');
    %param_names_gaze = sprintf('gaze_cnt,gaze_time,gaze_time_tick,fpogx,fpogy,fpogs,fpogd,fpogid,fpogv,lpogx,lpogy,lpogv,rpogx,rpogy,rpogv,bpogx,bpogy,bpogv,lpcx,lpcy,lpd,lps,lpv,rpcx,rpcy,rpd,rps,rpv,cx,cy,cs,bkid,bkdur,bkpmin,calib_x,calib_y,calib_v');
    %param_names = strcat(param_names_robot,param_names_gaze);
    param_names = sprintf('Time_stamp,api_cnt,joint_cnt,gaze_cnt');
end

if((exist('plot_signal','var'))&&(plot_signal>0))
    plot(conditioned_signal,'*')    
end

fileID = fopen('data.csv','w+');
fprintf(fileID,'Sample_no,Frame_no,Time,%s\n',param_names);%%%% write the csv file header
for i1=2:size(data_packets_csv,1)
    fwrite(fileID,cell2mat(data_packets_csv(i1))');%%%% write the data
end
fclose(fileID);%%% the end

end 


