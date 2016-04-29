% mlrAnatDBPlugin
%
%        $Id:$ 
%      usage: mlrAnatDBPlugin(action,<v>)
%         by: justin gardner
%       date: 12/28/2014
%    purpose: Plugin function for mercurial based anatomy database
%
function retval = mlrAnatDBPlugin(action,v)

% check arguments
if ~any(nargin == [1 2])
  help DefaultPlugin
  return
end

switch action
 case {'install','i'}
  % check for a valid view
  if (nargin ~= 2) || ~isview(v)
     disp(sprintf('(mlrAnatDBPlugin) Need a valid view to install plugin'));
  else
    % add the Add for mlrAnatDB menu
    mlrAdjustGUI(v,'add','menu','Anat DB','/File/ROI','Callback',@mlrAnatDB,'Separator','on');
    mlrAdjustGUI(v,'add','menu','Anat DB Preferences','/File/Anat DB/','Callback',@mlrAnatDBPreferences);
    mlrAdjustGUI(v,'add','menu','Load ROIs from Anat DB','/File/Anat DB/Anat DB Preferences','Callback',@mlrAnatDBLoadROIs,'Separator','on');
    mlrAdjustGUI(v,'add','menu','Load Base Anatomies from Anat DB','/File/Anat DB/Load ROIs from Anat DB','Callback',@mlrAnatDBLoadBaseAnatomies);
    mlrAdjustGUI(v,'add','menu','Import Surface from Anat DB','/File/Anat DB/Load Base Anatomies from Anat DB','Callback',@mlrAnatDBImportSurface,'Separator','on');
    mlrAdjustGUI(v,'add','menu','Add Session to Anat DB','/File/Anat DB/Import Surface from Anat DB','Callback',@mlrAnatDBAddSession,'Separator','on');
    mlrAdjustGUI(v,'add','menu','Add ROIs to Anat DB','/File/Anat DB/Add Session to Anat DB','Callback',@mlrAnatDBAddROIs);
    mlrAdjustGUI(v,'add','menu','Add Base Anatomies to Anat DB','/File/Anat DB/Add ROIs to Anat DB','Callback',@mlrAnatDBAddBaseAnatomies);
    mlrAdjustGUI(v,'add','menu','Examine ROI in Anat DB','/File/Anat DB/Add Base Anatomies to Anat DB','Callback',@mlrAnatDBExamineROI,'Separator','on');
    mlrAdjustGUI(v,'add','menu','Merge and Check ROIs for Anat DB','/File/Anat DB/Examine ROI in Anat DB','Callback',@mlrAnatDBMergeCheck);

    % add the callback that will tell mlrAnatDB that a base has been added
    % this is so that we can update the fields that point to the 
    % surfaces from which the anatomy was built (so that flatViewer and
    % makeFlat work)
    v = viewSet(v,'callback','newBase',@mlrAnatDBBaseChange);
    % return true to indicate successful plugin
    retval = true;
   end
 % return a help string
 case {'help','h','?'}
   retval = 'This plugin support exporting sessions and ROIs to a git managed repository';
 otherwise
   disp(sprintf('(mlrAnatDBPlugin) Unknown command %s',action));
end

%%%%%%%%%%%%%%%%%%%
%    mlrAnatDB    %
%%%%%%%%%%%%%%%%%%%
function mlrAnatDB(hObject,eventdata)

% code-snippet to get the view from the hObject variable.
v = viewGet(getfield(guidata(hObject),'viewNum'),'view');

% get repo locations
centralRepo = mrGetPref('mlrAnatDBCentralRepo');
localRepoTop = mrGetPref('mlrAnatDBLocalRepo');

% see if the preference is set
if isempty(centralRepo) || isempty(localRepoTop) 
  % do not enable any thing, because we don't have correct
  % preferences set
  mlrAdjustGUI(v,'set','Load ROIs from Anat DB','Enable','off');
  mlrAdjustGUI(v,'set','Load Base Anatomies from Anat DB','Enable','off');
  mlrAdjustGUI(v,'set','Import Surface from Anat DB','Enable','off');
  mlrAdjustGUI(v,'set','Add Session to Anat DB','Enable','off');
  mlrAdjustGUI(v,'set','Add ROIs to Anat DB','Enable','off');
  mlrAdjustGUI(v,'set','Add Base Anatomies to Anat DB','Enable','off');
  mlrAdjustGUI(v,'set','Examine ROI in Anat DB','Enable','off');
  return
end

% see if we are in an Anat DB session
if ~mlrAnatDBInLocalRepo(v)
  % if not, then only allow add session and examine ROI
  mlrAdjustGUI(v,'set','Load ROIs from Anat DB','Enable','on');
  mlrAdjustGUI(v,'set','Load Base Anatomies from Anat DB','Enable','on');
  mlrAdjustGUI(v,'set','Import Surface from Anat DB','Enable','on');
  mlrAdjustGUI(v,'set','Add Session to Anat DB','Enable','on');
  mlrAdjustGUI(v,'set','Add ROIs to Anat DB','Enable','off');
  mlrAdjustGUI(v,'set','Add Base Anatomies to Anat DB','Enable','on');
  if viewGet(v,'nROIs')
    mlrAdjustGUI(v,'set','Examine ROI in Anat DB','Enable','on');
  else
    mlrAdjustGUI(v,'set','Examine ROI in Anat DB','Enable','off');
  end
else
  % otherwise don't offer add seesion, but add everything else
  % contingent on whether there are ROIs loaded and so forth
  mlrAdjustGUI(v,'set','Load ROIs from Anat DB','Enable','on');
  mlrAdjustGUI(v,'set','Load Base Anatomies from Anat DB','Enable','on');
  mlrAdjustGUI(v,'set','Import Surface from Anat DB','Enable','on');
  mlrAdjustGUI(v,'set','Add Session to Anat DB','Enable','off');

  % see if any bases are loaded
  if viewGet(v,'numBase')
    mlrAdjustGUI(v,'set','Add Base Anatomies to Anat DB','Enable','on');
  else
    mlrAdjustGUI(v,'set','Add Base Anatomies to Anat DB','Enable','off');
  end    
  
  % see if we have any rois loaded, and gray out Add/AnatDB/ROIs menu accordingly
  if viewGet(v,'nROIs')
    mlrAdjustGUI(v,'set','Add ROIs to Anat DB','Enable','on');
    mlrAdjustGUI(v,'set','Examine ROI in Anat DB','Enable','on');
  else
    mlrAdjustGUI(v,'set','Add ROIs to Anat DB','Enable','off');
    mlrAdjustGUI(v,'set','Examine ROI in Anat DB','Enable','off');
  end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    mlrAnatDBAddSession    %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mlrAnatDBAddSession(hObject,eventdata)

% code-snippet to get the view from the hObject variable.
v = viewGet(getfield(guidata(hObject),'viewNum'),'view');

% remember what directory we started in
curpwd = pwd;

% Warn user that we are about to close session and will need to open it up again
% in the mlrAnatDB
if strcmp(questdlg(sprintf('(mlrAnatDBPlugin) Will now copy (using hard links) your current session into mlrAnatDB. To do so, will need to temporarily close the current session and then reopen in the mlrAnatDB session. Your current work will be saved as usual through the mrLastView mechanism which stores all your current settings. Also, this will not take any more hard disk space, since the files will be copied as hard links. Click OK to continue, or cancel to cancel this operation. If you hit cancel, you will be able to run File/Anat DB/Add Session at a later time.'),'mlrAnatDBPlugin','Ok','Cancel','Cancel'),'Cancel')
  cd(curpwd);
  return
end
  
% get subjectID
subjectID = mlrAnatDBSubjectID(v);

% get home directory
homeDir = viewGet(v,'homeDir');

% user said we could close, so do it
mrQuit;

% put the session into the repo
if ~mlrAnatDBPut(subjectID,homeDir,'localizer')
  % failure, so go back to the other directory
  cd(homeDir);
  mrLoadRet;
  cd(curpwd);
  return
end

% everything went ok, switch directories and start up over there
[localRepo localRepoLargeFiles] = mlrAnatDBGetRepo(subjectID);
cd(fullfile(localRepoLargeFiles,'localizers',getLastDir(homeDir)));
mrLoadRet;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    mlrAnatDBAddROIs    %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mlrAnatDBAddROIs(hObject,eventdata)

% code-snippet to get the view from the hObject variable.
v = viewGet(getfield(guidata(hObject),'viewNum'),'view');

% put base anatomies into repo
mlrAnatDBPut(v,v,'rois');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    mlrAnatDBAddBaseAnatomies    %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mlrAnatDBAddBaseAnatomies(hObject,eventdata)

% code-snippet to get the view from the hObject variable.
v = viewGet(getfield(guidata(hObject),'viewNum'),'view');

% put base anatomies into repo
mlrAnatDBPut(v,v,'mlrBaseAnat');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    mlrAnatDBMergeCheck    %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mlrAnatDBMergeCheck(hObject,eventdata)

% code-snippet to get the view from the hObject variable. 
v = viewGet(getfield(guidata(hObject),'viewNum'),'view');

disp(sprintf('\n\n\n\n\n\n\n\n(mlrAnatDBMergeCheck) Searching for ROIs that fit standards'));
pfxs = {'l','r'};
standards = {'V1','V2','V3','V4','V3a','V3b','V7','LO1','LO2','MT'};
% alternates = {'hV4','hMT+'};

% Check for all l/r ROIs and ask to rename
roiNames = viewGet(v,'roiNames');
if isempty(roiNames)
    disp('(mlrAnatDBMergeCheck) No ROIs to check'); return
end

nofind = {};
for pi = 1:length(pfxs)
    for si = 1:length(standards)
        searchfor = sprintf('%s%s',pfxs{pi},standards{si});
        [found, idx] = checkROIs(roiNames,searchfor,pfxs{pi},standards{si});
        if found==0
            disp(sprintf('(mlrAnatDBMergeCheck) You have no ROI: %s',searchfor));
            nofind{end+1} = searchfor;
        elseif found==2
            disp(sprintf('(mlrAnatDBMergeCheck) ROI %s appears to be mislabeled as %s.',searchfor,roiNames{idx}));
                        nofind{end+1} = searchfor;

        elseif found==3               
            disp(sprintf('(mlrAnatDBMergeCheck) You have no ROI: %s, you have %s which is similar...',searchfor,roiNames{idx}));
                        nofind{end+1} = searchfor;

        end
    end
end

if ~isempty(nofind)
    disp(sprintf('\n(mlrAnatDBMergeCheck) Please define the missing ROIs.\n\t\t\tYour ROIs may be mis-named.'));
    return
end
disp(sprintf('(mlrAnatDBMergeCheck) Found all standards'));


% Merge lV1+rV1 into V1, etc...
for si = 1:length(standards)
    cur = standards{si};
    curL = sprintf('%s%s',pfxs{1},standards{si});
    curR = sprintf('%s%s',pfxs{2},standards{si});
    [found, ~] = checkROIs(roiNames,cur,'','');
    [foundL, ~] = checkROIs(roiNames,curL,'','');
    [foundR, ~] = checkROIs(roiNames,curR,'','');
    if ~(found==1)
        if foundL&&foundR
            disp(sprintf('(mlrAnatDBMergeCheck) No ROI %s found. Computing the union of %s and %s',cur,curL,curR));
            v = combineROIs(v,curL,curR,'Union',cur);
        else
            disp('Something went wrong...');
            keyboard
        end
    else
        disp(sprintf('(mlrAnatDBMergeCheck) ROI %s already exists, skipping',cur));
    end
end
%%%%%
% HELPER FUNCTION TO CHECK FOR ROIS
%%%%%

function [found, idx] = checkROIs(rois,searchfor,prefix,suffix)
found = 0;
idx = -1;
for ri = 1:length(rois)
    if strcmp(rois{ri},searchfor)
        idx = ri; found = 1; return
    end
end
for ri = 1:length(rois)
    rois{ri} = lower(rois{ri});
end
suffix = lower(suffix);
% didn't find, try to find one that is similar?
for ri = 1:length(rois)
    if strcmp(rois{ri},searchfor)
        found = 3; idx = ri;
        return
    end
    if ~isempty(strfind(rois{ri},suffix))
        idx = ri; found = 2; 
        if isempty(strfind(rois{ri},prefix)) || length(rois{ri})~=(length(prefix)+length(suffix))
            found = 3;
        end
        return
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    mlrAnatDBExamineROI    %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mlrAnatDBExamineROI(hObject,eventdata)

% code-snippet to get the view from the hObject variable. 
v = viewGet(getfield(guidata(hObject),'viewNum'),'view');

% select an ROI to examine
roiNames = viewGet(v,'roiNames');
curROI = viewGet(v,'curROI');
if (curROI >1) && (length(roiNames)>=curROI)
  roiNames = putOnTopOfList(roiNames{curROI},roiNames);
end
paramsInfo = {{'roiToExamine',roiNames,'Choose which ROI to examine in its original localizer session'}};
params = mrParamsDialog(paramsInfo,'Choose ROI');
if isempty(params),return,end

% get the original session that the ROI was defined in and make
% sure we have it in the repo
roi = viewGet(v,'roi',params.roiToExamine);

% check for createdFromSession
if isempty(roi.createdFromSession)
  mrWarnDlg(sprintf('(mlrAnatDBPlugin:mlrAnatDBExamineROI) The ROI %s does not have the field createdFromSession set. Not sure which session it was created from',roi.name));
  return
end

% Check that we have mercurial installed correctly
if ~mlrAnatDBCheckHg,return,end

% get subject ID
subjectID = mlrAnatDBSubjectID(v);
if isempty(subjectID),return,end

% get the local repos
[localRepoSubject localRepoSubjectLargeFiles] = mlrAnatDBGetRepo(subjectID);
if isempty(localRepoSubject) || isempty(localRepoSubjectLargeFiles),return,end

% check to see if session exists in repo
createdFromSession = fullfile(localRepoSubjectLargeFiles,roi.createdFromSession);
if ~isdir(createdFromSession)
  mrWarnDlg(sprintf('(mlrAnatDBPlugin:mlrAnatDBExamineROI) Could not find session %s in mlrAnatDB',createdFromSession));
  return
end
  
% now confirm that this is what the user really wants to do
if strcmp(questdlg(sprintf('(mlrAnatDBPlugin:mlrAnatDBExamineROI) Will now close this current session (saving work as always) and will load up the localizer session where ROI: %s was defined',params.roiToExamine),'Switch to Localizer session','Ok','Cancel','Cancel'),'Cancel')
  return
end

% ok, user said we could close, so do it
mrQuit;
cd(createdFromSession);
mrLoadRet
v = getMLRView;

% check to see if ROI is loaded
if ~any(strcmp(viewGet(v,'roiNames'),params.roiToExamine))
  % then load it
  v = loadROI(v,params.roiToExamine,0,fullfile(localRepoSubject,'mlrROIs'));
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    mlrAnatDBLoadROIs    %
%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mlrAnatDBLoadROIs(hObject,eventdata)

% code-snippet to get the view from the hObject variable.
v = viewGet(getfield(guidata(hObject),'viewNum'),'view');

% Check that we have mercurial installed correctly
if ~mlrAnatDBCheckHg,return,end

% get subject ID
subjectID = mlrAnatDBSubjectID(v);
if isempty(subjectID),return,end

% get the local repos
localRepoSubject = mlrAnatDBGetRepo(subjectID);
if isempty(localRepoSubject),return,end

% load the rois
v = loadROI(v,[],[],fullfile(localRepoSubject,'mlrROIs'));

% and refresh
refreshMLRDisplay(v);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    mlrAnatDBLoadBaseAnatomies    %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mlrAnatDBLoadBaseAnatomies(hObject,eventdata)

% code-snippet to get the view from the hObject variable. 
v = viewGet(getfield(guidata(hObject),'viewNum'),'view');

% Check that we have mercurial installed correctly
if ~mlrAnatDBCheckHg,return,end

% get subject ID
subjectID = mlrAnatDBSubjectID(v);
if isempty(subjectID),return,end

% get the local repos
localRepoSubject = mlrAnatDBGetRepo(subjectID);
if isempty(localRepoSubject),return,end

% load the rois
v = loadAnat(v,[],fullfile(localRepoSubject,'mlrBaseAnatomies'));

% and refresh
refreshMLRDisplay(v);



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%    mlrAnatDBImportSurface    %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function mlrAnatDBImportSurface(hObject,eventdata)

% code-snippet to get the view from the hObject variable. 
v = viewGet(getfield(guidata(hObject),'viewNum'),'view');

% Check that we have mercurial installed correctly
if ~mlrAnatDBCheckHg,return,end

% get subject ID
subjectID = mlrAnatDBSubjectID(v);
if isempty(subjectID),return,end

% get the local repos
localRepoSubject = mlrAnatDBGetRepo(subjectID);
if isempty(localRepoSubject),return,end

% get the surface
filterspec = {'*.off','Off Surface file (*.off)'};
title = 'Choose outer surface file';
pathStr = mlrGetPathStrDialog(fullfile(localRepoSubject,'surfaces'),title,filterspec,'off');

% open the path up
if ~isempty(pathStr)
  base = importSurfaceOFF(pathStr);
  if ~isempty(base)
    v = viewSet(v, 'newbase', base);
    refreshMLRDisplay(v);
  end
end



%%%%%%%%%%%%%%%%%%
%    mysystem    %
%%%%%%%%%%%%%%%%%%
function [status,result] = mysystem(command)

disp(sprintf('(mlrAnatDBPlugin): %s',command));
[status,result] = system(command,'-echo');


%%%%%%%%%%%%%%%%%%%%
%    baseChange    %
%%%%%%%%%%%%%%%%%%%%
function v = mlrAnatDBBaseChange(v)

% get the base coord map for the new base
baseCoordMap = viewGet(v,'baseCoordMap');
% if not empty, we will check to see if its file
% pointers point to mlrAnatDB correctly
if ~isempty(baseCoordMap)
  % check path
  subjectID = getLastDir(fileparts(baseCoordMap.path));
  % update the path if it was already pointing to a subjectID directory
  if ~isempty(subjectID) && (subjectID(1) == 's')
    % change the path to point to the local mlrAnatDB
    baseCoordMap.path = mlrReplaceTilde(fullfile(mrGetPref('mlrAnatDBLocalRepo'),subjectID,getLastDir(baseCoordMap.path)));
    % and update
    v = viewSet(v,'baseCoordMap',baseCoordMap);
    % and see if the repo exists
    if isempty(mlrAnatDBGetRepo(subjectID,'noPull=1'))
      mlrAnatDBGetRepo(subjectID);
    end
  end
end
