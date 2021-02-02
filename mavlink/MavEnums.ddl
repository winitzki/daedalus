import MavNumerics

def MavFrame = Choose1 {
  mavFrameGlobal = @(Match1 0);
  mavFrameLocalNed = @(Match1 1);
  mavFrameMission = @(Match1 2);
  mavFrameGlobalRelativeAlt = @(Match1 3);
  mavFrameLocalEnu = @(Match1 4);
  mavFrameGlobalInt = @(Match1 5);
  mavFrameGlobalRelativeAltInt = @(Match1 6);
  mavFrameLocalOffsetNed = @(Match1 7);
  mavFrameBodyNed = @(Match1 8);
  mavFrameBodyOffsetNed = @(Match1 9);
  mavFrameGlobalTerrainAlt = @(Match1 10);
  mavFrameGlobalTerrainAltInt = @(Match1 11);
  mavFrameBodyFrd = @(Match1 12);
  mavFrameReserved13 = @(Match1 13);
  mavFrameReserved14 = @(Match1 14);
  mavFrameReserved14 = @(Match1 15);
  mavFrameReserved14 = @(Match1 16);
  mavFrameReserved14 = @(Match1 17);
  mavFrameReserved14 = @(Match1 18);
  mavFrameReserved14 = @(Match1 19);
  mavFrameLocalFrd = @(Match1 20);
  mavFrameLocalFlu = @(Match1 21);
}

-- MAVLink Commands (MAV_CMD)
-- TODO: fix to always parse two bytes
def MavCmd = Choose1 {
  mavCmdNavWaypoint = @(Match1 16);
  mavCmdNavLoiterUnlim = @(Match1 17);
  mavCmdNavLoiterTurns = @(Match1 18);
  mavCmdNavLoiterTime = @(Match1 19);
  mavCmdNavReturnToLaunch = @(Match1 20);
  -- mavCmdSome can be further refined into cases for more precise value checking:
  mavCmdSome = UInt16;
}

-- CmdParams: parameters of a command, uninterpreted
def CmdParams = {
  param1 = Float;
  param2 = Float;
  param3 = Float;
  param4 = Float;
  x = Int32;
  y = Int32;
  z = Float;
} 

-- MAV_CMD_NAV_WAYPOINT (16)
-- TODO: refine all of these definitions
def CmdNavWaypoint = CmdParams

-- MAV_CMD_NAV_LOITER_UNLIM (17)
def CmdNavLoiterUnlim = CmdParams

-- MAV_CMD_NAV_LOITER_TURNS (18)
def CmdNavLoiterTurns = CmdParams

-- MAV_CMD_NAV_LOITER_TIME (19)
def CmdNavLoiterTime = CmdParams

-- MAV_CMD_NAV_RETURN_TO_LAUNCH (20)
def CmdNavReturnToLaunch = CmdParams

-- definition sketch, using case:
def MavCmdParams cmd = Choose1 {
  mavCmdNavWaypointParams = {
    cmd is mavCmdNavWaypoint;
    CmdNavWaypoint;
  };
  mavCmdNavLoiterUnlimParams = {
    cmd is mavCmdNavLoiterUnlim;
    CmdNavLoiterUnlim 
  } ;
  mavCmdNavLoiterTurnsParams = {
    cmd is mavCmdNavLoiterTurns;
    CmdNavLoiterTurns
  };
  mavCmdNavLoiterTimeParams = {
    cmd is mavCmdNavLoiterTime;
    CmdNavLoiterTime
  };
  mavCmdNavReturnToLaunchParams = {
    cmd is mavCmdNavReturnToLaunch;
    CmdNavReturnToLaunch 
  };
  mavCmdSomeParams = {
    opc = cmd is mavCmdSome;
    ps = CmdParams;
  }
}

def MavMissionType = Choose1 {
  mavMissionTypeMission = @(Match1 0);
  mavMissionTypeFence = @(Match1 1);
  mavMissionTypeRally = @(Match1 2);
  mavMissionTypeAll = @(Match1 255);
}

def MavMissionResult = Choose1 { 
  mavMissionAccepted = @0; 
  mavMissionError = @1; 
  mavMissionUnsupportedFrame = @2; 
  mavMissionUnsupported = @3;
  mavMissionNoSpace = @4; 
  mavMissionInvalid = @5; 
  mavMissionInvalidParam1 = @6;
  mavMissionInvalidParam2 = @7;
  mavMissionInvalidParam3 = @8;
  mavMissionInvalidParam4 = @9;
  mavMissionInvalidParam5X = @10;
  mavMissionInvalidParam6Y = @11;
  mavMissionInvalidParam7 = @12;
  mavMissionInvalidSequence = @13; 
  mavMissionDenied = @14; 
  mavMissionOperationCancelled = @15;   
}
