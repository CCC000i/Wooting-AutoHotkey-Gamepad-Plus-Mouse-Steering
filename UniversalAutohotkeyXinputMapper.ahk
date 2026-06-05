; Requires ViGEmBus to be installed, + bundled scripts and DLLs in \Lib
; If Interception is not installed, set EnableAHI=0 in \$MapperConfigs\.Settings.ini
Global DebugMode := true
Global ScriptStartTime := A_TickCount

#Requires AutoHotkey v1.1
#NoEnv
#SingleInstance Force
SetBatchLines, -1

; --- Directory Setup & Global Settings Load ---
settingsDir := A_ScriptDir . "\$MapperConfigs"
settingsFile := settingsDir . "\.Settings.ini"
sessionFile := settingsDir . "\.last_profile"

if !InStr(FileExist(settingsDir), "D")
    FileCreateDir, %settingsDir%

IniRead, aliasStr, %settingsFile%, GlobalSettings, configAliases, %A_Space%
IniRead, exeStr, %settingsFile%, GlobalSettings, exeMatches, %A_Space%

configAliases := ParseConfigAliases(aliasStr)
exeMatches := ParseExeMatches(exeStr)

; === Session & Profile Selection ===
matchedConfig := ""

; Delete session file if holding Ctrl+Shift
if ((DllCall("GetAsyncKeyState", "Int", 0x11) & 0x8000) && (DllCall("GetAsyncKeyState", "Int", 0x10) & 0x8000))
    FileDelete, %sessionFile%

if FileExist(sessionFile) {
    FileRead, matchedConfig, %sessionFile%
    matchedConfig := Trim(matchedConfig)
}

if (matchedConfig == "") {
    defaultProfile := ""
    
    ; 1. Primary check: Use explicit exeMatches from .Settings file
    For profileName, exeList in exeMatches {
        For _, exeName in exeList {
            Process, Exist, %exeName%
            if (ErrorLevel) { 
                defaultProfile := profileName
                break 2 
            }
        }
    }

    ; 2. Fallback check: Look for any config .ini matching a running process name
    if (defaultProfile == "") {
        Loop, Files, %settingsDir%\*.ini
        {
            if (SubStr(A_LoopFileName, 1, 1) == ".")
                continue
                
            SplitPath, A_LoopFileName,,,, fileNameNoExt
            Process, Exist, %fileNameNoExt%.exe
            if (ErrorLevel) { 
                defaultProfile := fileNameNoExt
                break
            }
        }
    }

    ; 3. Prompt User
    Loop {
        InputBox, userInput, Load Config, Enter config alias or file name (without .ini).`nHold Ctrl+Shift on script start or press Alt+Y`nto see this window again.,, 320, 160,,,,, %defaultProfile%
        if (ErrorLevel)
            ExitApp
        
        userInput := Trim(userInput)
        
        if configAliases.HasKey(userInput)
            matchedConfig := configAliases[userInput]
        else if FileExist(settingsDir . "\" . userInput . ".ini")
            matchedConfig := userInput
        
        if (matchedConfig != "") {
            FileDelete, %sessionFile%
            FileAppend, %matchedConfig%, %sessionFile%
            Break
        }
    }
}

; === Dynamic Config Load ===
configFile := settingsDir . "\" . matchedConfig . ".ini"
FileRead, FileContent, %configFile%
if (ErrorLevel) {
    MsgBox, 16, Error, Config INI could not be read.
    FileDelete, %sessionFile%
    ExitApp
}

RegExMatch(FileContent, "s)\[CustomAutoexecute\]\R*(.*?)(?=\[|$)", MatchAuto)
CustomAutoexecute := MatchAuto1

RegExMatch(FileContent, "s)\[CustomSubroutine\]\R*(.*?)(?=\[|$)", MatchSub)
CustomSubroutine := MatchSub1

; === Dynamic Script Compilation ===
IniRead, EnableAHI, %settingsFile%, GlobalSettings, EnableAHI, 1
IniRead, WootingEnabled, %settingsFile%, GlobalSettings, WootingEnabled, 1

IncludeDirectives := "#Include <AHK-ViGEm-Bus_v1>`n"
if (WootingEnabled)
    IncludeDirectives .= "#Include <SimpleWooting_v1>`n"
if (EnableAHI)
    IncludeDirectives := "#Include <AutoHotInterception_v1>`n" . IncludeDirectives

FileRead, selfCode, %A_ScriptFullPath%
if (ErrorLevel || selfCode == "") {
    MsgBox, 16, Error, Failed to read dynamically generated script.
    ExitApp
}
RegExMatch(selfCode, "s)\/\*\s*\[CORE_LOGIC_START\]\R(.*?)\R\[CORE_LOGIC_END\]\s*\*\/", coreMatch)
CoreLogic := coreMatch1

; Combine strings directly into memory
FullScriptString := IncludeDirectives . "`n" . CustomAutoexecute . "`n" . CoreLogic . "`n`n; === CUSTOM CODE ===`n" . CustomSubroutine . "`n`nreturn"
if (DebugMode) {
    ; Save the debug copy so you can open it to see why it crashed
    FileDelete, %A_ScriptDir%\$DEBUG_DUMP.ahk
    FileAppend, %FullScriptString%, %A_ScriptDir%\$DEBUG_DUMP.ahk
}

; Formulate argument string safely wrapped in quotes
ScriptArgs := """" . matchedConfig . """ """ . A_ScriptName . """"

; Launch the script in-memory via stdin stream pipeline
ExecScriptFromStr(FullScriptString, ScriptArgs)
ExitApp

; === Launcher Functions ===
ExecScriptFromStr(ScriptText, Args := "") {
    shell := ComObjCreate("WScript.Shell")
    ; /CP65001 forces AutoHotkey to interpret incoming stdin bytes as UTF-8
    exec := shell.Exec("""" . A_AhkPath . """ /CP65001 * " . Args)
    exec.StdIn.Write(ScriptText)
    exec.StdIn.Close()
    return exec.ProcessID
}

ParseConfigAliases(iniStr) {
    obj := {}
    Loop, Parse, iniStr, `,
    {
        parts := StrSplit(A_LoopField, ":")
        if (parts.Length() == 2)
            obj[Trim(parts[1])] := Trim(parts[2])
    }
    return obj
}

ParseExeMatches(iniStr) {
    obj := {}
    Pos := 1
    while (Pos := RegExMatch(iniStr, "O)(?:\[([^\]]+)\]|([^:,]+))\s*:\s*([^,]+)", M, Pos)) {
        exesStr := M.Value(1) ? M.Value(1) : M.Value(2)
        profile := Trim(M.Value(3))
        exeArr := []
        
        Loop, Parse, exesStr, `,
        {
            t := Trim(A_LoopField)
            if (t != "")
                exeArr.Push(t)
        }
        obj[profile] := exeArr
        Pos += M.Len(0)
    }
    return obj
}

; ==========================================
; CORE LOGIC SCRIPT RESOURCE STARTS HERE
; ==========================================

/*
[CORE_LOGIC_START]
#Requires AutoHotkey v1.1
#NoEnv
#Persistent
#SingleInstance Force
#UseHook
#HotkeyInterval 0
SetBatchLines, -1
CoordMode, Mouse, Screen

Menu, Tray, NoStandard
Menu, Tray, Add, Profile Folder, Profile_Folder
Menu, Tray, Add, Edit Launcher, Edit_Launcher
Menu, Tray, Add, Reload Launcher, Reload_Launcher
Menu, Tray, Add, Reload Launcher with Selection, Reload_Launcher_with_Selection
Menu, Tray, Add, Exit Script, Exit_Script

; Safety Hooks
OnExit("CleanUp")
OnMessage(0x11, "CleanUp") ; Catch logoffs/suspensions

DllCall("winmm\timeBeginPeriod", "UInt", 1) 

matchedConfig := A_Args[1]
launcherName := A_Args[2]

settingsFile := A_ScriptDir . "\$MapperConfigs\.Settings.ini"
configFile := A_ScriptDir . "\$MapperConfigs\" . matchedConfig . ".ini"

IniRead, WootingEnabled, %settingsFile%, GlobalSettings, WootingEnabled, 1
IniRead, ExternalXInputEnabled, %settingsFile%, GlobalSettings, ExternalXInputEnabled, 1
IniRead, EnableAHI, %settingsFile%, GlobalSettings, EnableAHI, 1

; --- AHI MOUSE TO JOYSTICK SETTINGS ---
IniRead, AHITranslateMouseToAxes, %configFile%, Settings, AHITranslateMouseToAxes, 0
IniRead, raw_AHIMX, %configFile%, Settings, AHIMouseAxisX, RX
IniRead, raw_AHIMY, %configFile%, Settings, AHIMouseAxisY, RY
IniRead, AHIMouseSensitivity, %configFile%, Settings, AHIMouseSensitivity, 15.0
IniRead, AHIMouseDecay, %configFile%, Settings, AHIMouseDecay, 0.75

AHIMX_Parsed := ParseAxisAndMult(raw_AHIMX)
Global AHIMouseAxisX := AHIMX_Parsed.Axis
Global AHIMouseAxisX_Mult := AHIMX_Parsed.Mult

AHIMY_Parsed := ParseAxisAndMult(raw_AHIMY)
Global AHIMouseAxisY := AHIMY_Parsed.Axis
Global AHIMouseAxisY_Mult := AHIMY_Parsed.Mult

Global AHIMouse := { DeltaX: 0, DeltaY: 0, StickX: 0, StickY: 0, RawDeltaX: 0, RawDeltaY: 0 }
Global AHIMouseIDs := []
Global AHIMouseSubscribed := false

; === Global State & Constants Object ===
Global ScriptStartTime := A_TickCount
Global lastChange := 0
Global CONST := { MULT_POS: 128.49803, MULT_NEG: 128.50196, READ_MULT: 0.00778198, DINPUT_MULT: 5.1 }
Global AppState := { IsGameActive: false, RunAlways: false, FocusPass: true }
Global WindowState := { Locked: false, X: 0, Y: 0, W: 0, H: 0 }
Global MouseState := { X: 0, Y: 0, LastX: 0, LastY: 0, SteeringActive: false }
Global Cursors := { Visible: false, ForceHide: false, EnforceCounter: 0, VertVisible: false }
Global SteerKey := { Down: false }
Global ScreenCenter := { x: A_ScreenWidth // 2, y: A_ScreenHeight // 2 }

Global hUser32 := DllCall("GetModuleHandle", "Str", "user32.dll", "Ptr")
Global pGetClipCursor := DllCall("GetProcAddress", "Ptr", hUser32, "AStr", "GetClipCursor", "Ptr")
Global pClipCursor := DllCall("GetProcAddress", "Ptr", hUser32, "AStr", "ClipCursor", "Ptr")
Global pSetSystemCursor := DllCall("GetProcAddress", "Ptr", hUser32, "AStr", "SetSystemCursor", "Ptr")
Global pCopyImage := DllCall("GetProcAddress", "Ptr", hUser32, "AStr", "CopyImage", "Ptr")
Global pSetWindowPos := DllCall("GetProcAddress", "Ptr", hUser32, "AStr", "SetWindowPos", "Ptr")
Global pSystemParametersInfo := DllCall("GetProcAddress", "Ptr", hUser32, "AStr", "SystemParametersInfoW", "Ptr")
Global pDestroyCursor := DllCall("GetProcAddress", "Ptr", hUser32, "AStr", "DestroyCursor", "Ptr")

Global MathVars := { MaxDist: 0, MousePressureMult: 0, WD_Mult: 1.0, ExtS_Mult: 1.0, ExtT_Mult: 1.0, MaxDist_Div255: 0 }
Global ADZ_Calc := {}

Global SysCursorsList := [32512, 32513, 32514, 32515, 32516, 32642, 32643, 32644, 32645, 32646, 32648, 32649, 32650]
VarSetCapacity(AndMask, 128, 0xFF)
VarSetCapacity(XorMask, 128, 0x00)
Global BlankCursor := DllCall("CreateCursor", "Ptr", 0, "Int", 0, "Int", 0, "Int", 32, "Int", 32, "Ptr", &AndMask, "Ptr", &XorMask, "Ptr")
VarSetCapacity(Rect, 16, 0)
VarSetCapacity(CurrentClip, 16, 0)

Global lastAxisState := {LX: 0, LY: 0, RX: 0, RY: 0, LT: 0, RT: 0}

; === Pre-ViGEm External Controller Detection ===
Global ExternalGamepads := []
Global ExtPadState := {LX: 0, LY: 0, RX: 0, RY: 0, LT: 0, RT: 0}
Global pXInputGetState := 0 

if (ExternalXInputEnabled) {
    hXInput := DllCall("LoadLibrary", "Str", "xinput1_4.dll", "Ptr")
    if (!hXInput)
        hXInput := DllCall("LoadLibrary", "Str", "xinput1_3.dll", "Ptr")
    
    if (hXInput) {
        pXInputGetState := DllCall("GetProcAddress", "Ptr", hXInput, "AStr", "XInputGetState", "Ptr")
        Loop, 4 {
            idx := A_Index - 1
            VarSetCapacity(XINPUT_STATE, 16, 0)
            if (DllCall(pXInputGetState, "UInt", idx, "Ptr", &XINPUT_STATE) == 0)
                ExternalGamepads.Push({Type: "XInput", ID: idx})
        }
    }
}

; === Libraries & Device Initialization ===
if (EnableAHI) {
    Global ahi := new AutoHotInterception()
    
    ; Define input groups to check for runtime user functions matching 'ahiSubscribed_KeyName'
    MouseButtons := { "LButton": 0, "RButton": 1, "MButton": 2, "XButton1": 3, "XButton2": 4 }
    KeysToScan := ["Space", "LAlt", "RAlt", "LCtrl", "RCtrl", "LShift", "RShift", "Enter", "Tab", "Esc"
                , "Backspace", "Delete", "Up", "Down", "Left", "Right", "Home", "End", "PgUp", "PgDn"
                , "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"
                , "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"
                , "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"
                , "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]

    for index, device in ahi.GetDeviceList() {
        if (device.isMouse) {
            mId := device.Id
            AHIMouseIDs.Push(mId)
            
            ; 1. Route Mouse Buttons
            for btnName, btnId in MouseButtons {
                if (Func("ahiSubscribed_" . btnName)) {
                    ahi.SubscribeMouseButton(mId, btnId, true, Func("Core_DynamicMouseBtnHandler").Bind(btnName, btnId, mId))
                }
            }
            
            ; 2. Route Scroll Wheel
            if (Func("ahiSubscribed_Wheel")) {
                ahi.SubscribeMouseButton(mId, 5, true, Func("Core_DynamicMouseWheelHandler").Bind(mId))
            }
        } else {
            kId := device.Id
            ; 3. Route Keyboard Keys
            for _, keyName in KeysToScan {
                if (Func("ahiSubscribed_" . keyName)) {
                    sc := GetKeySC(keyName)
                    if (sc) {
                        ahi.SubscribeKey(kId, sc, true, Func("Core_DynamicKeyHandler").Bind(keyName, sc, kId))
                    }
                }
            }
        }
    }
}

Global pad := new ViGEmXb360()
if (WootingEnabled) {
    Global sw := SimpleWooting_v1
    sw.Init()
}

; === Read Arrays and Settings ===
IniRead, val, %configFile%, Settings, exeName, ERROR
Global exeName := (val != "ERROR") ? ParseArray(val) : []

IniRead, raw_MSAX, %configFile%, Settings, MouseSteeringAxisX, LX
IniRead, raw_MSAY, %configFile%, Settings, MouseSteeringAxisY, None

MSAX_Parsed := ParseAxisAndMult(raw_MSAX)
Global MouseSteeringAxisX := MSAX_Parsed.Axis
Global MouseSteeringAxisX_Mult := MSAX_Parsed.Mult

MSAY_Parsed := ParseAxisAndMult(raw_MSAY)
Global MouseSteeringAxisY := MSAY_Parsed.Axis
Global MouseSteeringAxisY_Mult := MSAY_Parsed.Mult

IniRead, MouseSteerWidth, %configFile%, Settings, MouseSteerWidth, 1.0
IniRead, LX_D_MovesMouse, %configFile%, Settings, LX_D_MovesMouse, 0
IniRead, AnalogSupersedesMouse, %configFile%, Settings, AnalogSupersedesMouse, 0

IniRead, WootingDeadzone, %configFile%, Settings, WootingDeadzone, 8
IniRead, ExtStickDeadzone, %configFile%, Settings, ExtStickDeadzone, 8
IniRead, ExtTriggerDeadzone, %configFile%, Settings, ExtTriggerDeadzone, 8

IniRead, EnableCursorReplacement, %configFile%, Settings, EnableCursorReplacement, 0
IniRead, EnableMouseLock, %configFile%, Settings, EnableMouseLock, 0
IniRead, EnableVerticalLine, %configFile%, Settings, EnableVerticalLine, 0

MathVars.WD_Mult := (WootingDeadzone >= 255 || WootingDeadzone <= 0) ? 0 : (255.0 / (255 - WootingDeadzone))
MathVars.ExtS_Mult := (ExtStickDeadzone >= 255 || ExtStickDeadzone <= 0) ? 0 : (255.0 / (255 - ExtStickDeadzone))
MathVars.ExtT_Mult := (ExtTriggerDeadzone >= 255 || ExtTriggerDeadzone <= 0) ? 0 : (255.0 / (255 - ExtTriggerDeadzone))
MathVars.MaxDist := (A_ScreenHeight / 2) * MouseSteerWidth
MathVars.MousePressureMult := MathVars.MaxDist > 0 ? (255.0 / MathVars.MaxDist) : 0
MathVars.MaxDist_Div255 := MathVars.MaxDist / 255.0 

For _, ax in ["LX", "LY", "RX", "RY", "LT", "RT"] {
    IniRead, adzRaw, %configFile%, Settings, %ax%_Antideadzone, 0
    ADZ_Calc[ax] := { Raw: adzRaw * 2.55, Scale: (255 - (adzRaw * 2.55)) / 255.0 }
}

Global LX_A := ParseAnalog(ReadIni(configFile, "LX_A")), LX_D := ParseDigital(ReadIni(configFile, "LX_D", "DigitalBinds"))
Global LY_A := ParseAnalog(ReadIni(configFile, "LY_A")), LY_D := ParseDigital(ReadIni(configFile, "LY_D", "DigitalBinds"))
Global RX_A := ParseAnalog(ReadIni(configFile, "RX_A")), RX_D := ParseDigital(ReadIni(configFile, "RX_D", "DigitalBinds"))
Global RY_A := ParseAnalog(ReadIni(configFile, "RY_A")), RY_D := ParseDigital(ReadIni(configFile, "RY_D", "DigitalBinds"))
Global LT_A := ParseAnalog(ReadIni(configFile, "LT_A")), LT_D := ParseDigital(ReadIni(configFile, "LT_D", "DigitalBinds"))
Global RT_A := ParseAnalog(ReadIni(configFile, "RT_A")), RT_D := ParseDigital(ReadIni(configFile, "RT_D", "DigitalBinds"))

if (exeName.Length() == 0) {
    AppState.RunAlways := true
    EnableMouseLock := 0 
} else {
    For _, exe in exeName
        GroupAdd, ActiveGameGroup, ahk_exe %exe%
}

; === GUI Initialization ===
Gui, +LastFound +AlwaysOnTop -Caption +ToolWindow +E0x20
Gui, Color, White
Gui, Add, Picture, x0 y0 w16 h16, crosshair.png
WinSet, TransColor, White
Global CrosshairHwnd := WinExist()

Gui, 2:+LastFound +AlwaysOnTop -Caption +ToolWindow +E0x20
Gui, 2:Color, Red
Gui, 2:Add, Progress, x1 y0 w1 h10000 BackgroundWhite
WinSet, Transparent, 127          
Global LineHwnd := WinExist()

AppState.IsGameActive := AppState.RunAlways ? true : WinActive("ahk_group ActiveGameGroup")
if (AppState.IsGameActive)
    Gosub, WindowCheckLoop

Global CLTimer := 10
SetTimer, CoreLoop, %CLTimer%
SetTimer, WindowCheckLoop, 250
return

; ==========================================
; AUTO-EXECUTE ENDS HERE
; ==========================================

WindowCheckLoop:
    AppState.IsGameActive := AppState.RunAlways ? true : WinActive("ahk_group ActiveGameGroup")
    if (AppState.IsGameActive && (EnableMouseLock || EnableVerticalLine))
        UpdateActiveWindowBounds()
return

CoreLoop:
    if (!AppState.IsGameActive) {
        SteerKey.Down := false
        if (AppState.FocusPass) {
            FocusLost()
            AppState.FocusPass := false
        }
        return
    }

    ; --- Game Is Active Execution Flow ---
    AppState.FocusPass := true

    ManageAHISubscriptions()
    ReadExternalGamepads()
    
    MouseGetPos, currentX, currentY
    MouseState.X := currentX, MouseState.Y := currentY

    if (AHITranslateMouseToAxes)
        UpdateAHIMousePhysics()

    UpdateAllVirtualAxes()
    
    if (AHITranslateMouseToAxes)
        ApplyAHISpringReturn()

    EnforceMouseLockAndCursor()

    MouseState.SteeringActive := SteerKey.Down
return

; ==========================================
;                 FUNCTIONS
; ==========================================

UpdateActiveWindowBounds() {
    global AppState, WindowState, Rect, EnableVerticalLine, Cursors
    
    if (AppState.RunAlways) {
        nWx := 0, nWy := 0, nWw := A_ScreenWidth, nWh := A_ScreenHeight
    } else {
        WinGetPos, nWx, nWy, nWw, nWh, ahk_group ActiveGameGroup 
    }

    if (nWx != WindowState.X || nWy != WindowState.Y || nWw != WindowState.W || nWh != WindowState.H) {
        WindowState.X := nWx, WindowState.Y := nWy, WindowState.W := nWw, WindowState.H := nWh
        NumPut(nWx, Rect, 0, "Int"), NumPut(nWy, Rect, 4, "Int")
        NumPut(nWx + nWw, Rect, 8, "Int"), NumPut(nWy + nWh, Rect, 12, "Int")
        
        if (EnableVerticalLine && Cursors.VertVisible)
            Gui, 2:Show, % "x0 y0 w3 h" . nWh . " NoActivate", VertLine
    }
}

ManageAHISubscriptions() {
    global AHITranslateMouseToAxes, AHIMouseSubscribed, AHIMouseIDs, ahi
    
    if (AHITranslateMouseToAxes && !AHIMouseSubscribed) {
        for _, mId in AHIMouseIDs {
            ahi.SubscribeMouseMoveRelative(mId, true, Func("Core_ahiOnMouseMoveRelative"))
        }
        AHIMouseSubscribed := true
    }
}

UpdateAHIMousePhysics() {
    global AHIMouse, AHIMouseAxisX_Mult, AHIMouseAxisY_Mult, AHIMouseSensitivity, AHIMouseDecay, CLTimer
    
    ; 1. Prevent Dropped Inputs (Race Condition Fix)
    Critical, On
    rawDeltaX := AHIMouse.DeltaX
    rawDeltaY := AHIMouse.DeltaY
    AHIMouse.DeltaX := 0
    AHIMouse.DeltaY := 0
    Critical, Off

    ; 2. Calculate Time Delta (Frame-Rate Independence)
    currentTick := A_TickCount
    dt := currentTick - (AHIMouse.LastTick ? AHIMouse.LastTick : currentTick - CLTimer)
    AHIMouse.LastTick := currentTick
    if (dt <= 0)
        dt := 1

    ; Normalize deltas against the expected dynamic loop timer
    normFactor := CLTimer / dt
    velX := rawDeltaX * normFactor * AHIMouseAxisX_Mult
    velY := (rawDeltaY * -1) * normFactor * AHIMouseAxisY_Mult

    ; 3. Velocity-Targeting (Multiplied by 3.0 to keep existing config values similar)
    targetX := velX * AHIMouseSensitivity * 3.0
    targetY := velY * AHIMouseSensitivity * 3.0

    ; 4. Apply Decay (Weight/Return Speed)
    AHIMouse.StickX := (rawDeltaX != 0) ? targetX : AHIMouse.StickX * AHIMouseDecay
    AHIMouse.StickY := (rawDeltaY != 0) ? targetY : AHIMouse.StickY * AHIMouseDecay

    ; 5. Clamp to XInput limits
    AHIMouse.StickX := Max(-255, Min(255, AHIMouse.StickX))
    AHIMouse.StickY := Max(-255, Min(255, AHIMouse.StickY))
    
    ; Store state for Spring Return logic
    AHIMouse.RawDeltaX := rawDeltaX
    AHIMouse.RawDeltaY := rawDeltaY
}

UpdateAllVirtualAxes() {
    global LX_D, LX_A, LY_D, LY_A, RX_D, RX_A, RY_D, RY_A, LT_D, LT_A, RT_D, RT_A
    
    UpdateVirtualAxis("LX", true, LX_D, LX_A)
    UpdateVirtualAxis("LY", true, LY_D, LY_A)
    UpdateVirtualAxis("RX", true, RX_D, RX_A)
    UpdateVirtualAxis("RY", true, RY_D, RY_A)
    UpdateVirtualAxis("LT", false, LT_D, LT_A)
    UpdateVirtualAxis("RT", false, RT_D, RT_A)
}

ApplyAHISpringReturn() {
    global AHIMouse
    
    if (AHIMouse.RawDeltaX == 0 && Abs(AHIMouse.StickX) < 1.0)
        AHIMouse.StickX := 0
    if (AHIMouse.RawDeltaY == 0 && Abs(AHIMouse.StickY) < 1.0)
        AHIMouse.StickY := 0
}

EnforceMouseLockAndCursor() {
    global EnableMouseLock, EnableCursorReplacement, EnableVerticalLine
    global pGetClipCursor, pClipCursor, pSetSystemCursor, pCopyImage, pSetWindowPos, pSystemParametersInfo
    global WindowState, CurrentClip, Rect, Cursors, BlankCursor, SysCursorsList
    global MouseState, CrosshairHwnd, LineHwnd

    ; --- Mouse Lock ---
    if (EnableMouseLock) {
        DllCall(pGetClipCursor, "Ptr", &CurrentClip)
        if (NumGet(CurrentClip, 0, "Int") != WindowState.X || NumGet(CurrentClip, 4, "Int") != WindowState.Y || NumGet(CurrentClip, 8, "Int") != WindowState.X + WindowState.W || NumGet(CurrentClip, 12, "Int") != WindowState.Y + WindowState.H) {
            DllCall(pClipCursor, "Ptr", &Rect)
            if (EnableCursorReplacement)
                Cursors.ForceHide := True 
        }
        WindowState.Locked := true
    } else if (WindowState.Locked) {
        DllCall(pClipCursor, "Ptr", 0)
        WindowState.Locked := false
    }

    ; --- Cursor Replacement ---
    if (EnableCursorReplacement) {
        if (!Cursors.Visible || Cursors.ForceHide || ++Cursors.EnforceCounter >= 50) {
            if (!Cursors.Visible)
                Gui, Show, x0 y0 w16 h16 NoActivate, Crosshair
            Cursors.Visible := True, Cursors.EnforceCounter := 0, Cursors.ForceHide := False
            
            For _, cursorID in SysCursorsList
                DllCall(pSetSystemCursor, "Ptr", DllCall(pCopyImage, "Ptr", BlankCursor, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0), "UInt", cursorID)
        }
    } else if (Cursors.Visible) {
        Gui, Hide
        DllCall(pSystemParametersInfo, "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
        Cursors.Visible := False, Cursors.EnforceCounter := 0, Cursors.ForceHide := False
    }

    ; --- Vertical Line ---
    if (EnableVerticalLine) {
        if (!Cursors.VertVisible)
            Gui, 2:Show, % "x0 y0 w3 h" . WindowState.H . " NoActivate", VertLine
        Cursors.VertVisible := true
    } else if (Cursors.VertVisible) {
        Gui, 2:Hide
        Cursors.VertVisible := false
    }

    ; --- Sync GUI Elements to Mouse Position ---
    if (MouseState.X != MouseState.LastX || MouseState.Y != MouseState.LastY) {
        if (EnableCursorReplacement && Cursors.Visible)
            DllCall(pSetWindowPos, "Ptr", CrosshairHwnd, "Ptr", 0, "Int", MouseState.X-8, "Int", MouseState.Y-8, "Int", 0, "Int", 0, "UInt", 0x15)
        if (EnableVerticalLine && Cursors.VertVisible)
            DllCall(pSetWindowPos, "Ptr", LineHwnd, "Ptr", 0, "Int", MouseState.X, "Int", WindowState.Y, "Int", 0, "Int", 0, "UInt", 0x15)
        
        MouseState.LastX := MouseState.X, MouseState.LastY := MouseState.Y
    }
}

ActivateMouseSteering() {
    SteerKey.Down := true
}

DeactivateMouseSteering() {
    SteerKey.Down := false
}

; === DYNAMIC INTERCEPTION HANDLERS ===

Core_DynamicKeyHandler(keyName, sc, kId, state) {
    global AppState, ahi
    if (AppState.IsGameActive)
        Func("ahiSubscribed_" . keyName).Call(state)
    else
        ahi.SendKeyEvent(kId, sc, state)
}

Core_DynamicMouseBtnHandler(btnName, btnId, mId, state) {
    global AppState, ahi
    if (AppState.IsGameActive)
        Func("ahiSubscribed_" . btnName).Call(state)
    else
        ahi.SendMouseButtonEvent(mId, btnId, state)
}

Core_DynamicMouseWheelHandler(mId, direction) {
    global AppState, ahi
    if (AppState.IsGameActive)
        Func("ahiSubscribed_Wheel").Call(direction)
    else
        ahi.SendMouseButtonEvent(mId, 5, direction)
}

ReadExternalGamepads() {
    global ExternalGamepads, ExtPadState, pXInputGetState, CONST
    static XINPUT_STATE
    if !VarSetCapacity(XINPUT_STATE)
        VarSetCapacity(XINPUT_STATE, 16, 0)

    ExtPadState.LX := 0, ExtPadState.LY := 0, ExtPadState.RX := 0, ExtPadState.RY := 0, ExtPadState.LT := 0, ExtPadState.RT := 0

    for _, padObj in ExternalGamepads {
        if (padObj.Type == "XInput" && pXInputGetState) {
            if (DllCall(pXInputGetState, "UInt", padObj.ID, "Ptr", &XINPUT_STATE) == 0) {
                ExtPadState.LT := NumGet(XINPUT_STATE, 6, "UChar")
                ExtPadState.RT := NumGet(XINPUT_STATE, 7, "UChar")
                ExtPadState.LX := Round(NumGet(XINPUT_STATE, 8, "Short") * CONST.READ_MULT)
                ExtPadState.LY := Round(NumGet(XINPUT_STATE, 10, "Short") * CONST.READ_MULT)
                ExtPadState.RX := Round(NumGet(XINPUT_STATE, 12, "Short") * CONST.READ_MULT)
                ExtPadState.RY := Round(NumGet(XINPUT_STATE, 14, "Short") * CONST.READ_MULT)
                break 
            }
        }
    }
}

ReadIni(file, key, section := "AnalogBinds") {
    IniRead, out, %file%, %section%, %key%, ERROR
    return out
}

UpdateVirtualAxis(axis, isStick, ByRef dArray, ByRef aArray) {
    global lastAxisState, ScreenCenter, MouseState, CONST
    global MathVars, ADZ_Calc, LX_D_MovesMouse, WootingDeadzone, ExtStickDeadzone, ExtTriggerDeadzone
    global AnalogSupersedesMouse, ExtPadState, WootingEnabled
    global MouseSteeringAxisX, MouseSteeringAxisY
    global MouseSteeringAxisX_Mult, MouseSteeringAxisY_Mult
    
    pressure := 0, hasDigital := false
    
    for _, pair in dArray {
        if GetKeyState(pair[1], "P") {
            pressure := pair[2]
            if (isStick && axis == MouseSteeringAxisX && LX_D_MovesMouse) {
                signX := MouseSteeringAxisX_Mult < 0 ? -1 : 1
                targetX := Round(ScreenCenter.x + (pressure * MathVars.MaxDist_Div255 * signX))
                MouseMove, %targetX%, % MouseState.Y, 0
            }
            hasDigital := true
            break
        }
    }
    
    if (!hasDigital) {
        for key, value in aArray {
            rawVal := 0
            if (WootingEnabled)
                rawVal := sw.RP(key)
            if (WootingDeadzone > 0)
                rawVal := (rawVal <= WootingDeadzone) ? 0 : (rawVal - WootingDeadzone) * MathVars.WD_Mult
            pressure += rawVal * value
        }
        
        extVal := 0
        rawExt := ExtPadState[axis]
        
        if (isStick) {
            absExt := Abs(rawExt)
            if (ExtStickDeadzone > 0)
                absExt := (absExt <= ExtStickDeadzone) ? 0 : (absExt - ExtStickDeadzone) * MathVars.ExtS_Mult
            extVal := (rawExt < 0) ? -absExt : absExt
        } else {
            if (ExtTriggerDeadzone > 0)
                extVal := (rawExt <= ExtTriggerDeadzone) ? 0 : (rawExt - ExtTriggerDeadzone) * MathVars.ExtT_Mult
            else
                extVal := rawExt
        }
        pressure += extVal
        
        ; --- APPLY SMOOTHED MOUSE ---
        global AHIMouse, AHITranslateMouseToAxes, AHIMouseAxisX, AHIMouseAxisY
        if (AHITranslateMouseToAxes && isStick) {
            if (axis == AHIMouseAxisX)
                pressure += AHIMouse.StickX
            else if (axis == AHIMouseAxisY)
                pressure += AHIMouse.StickY
        }
        
        if (isStick && MouseState.SteeringActive) {
            if (axis == MouseSteeringAxisX && (!AnalogSupersedesMouse || pressure == 0)) {
                mousePressure := (MouseState.X - ScreenCenter.x) * MathVars.MousePressureMult * MouseSteeringAxisX_Mult
                pressure := AnalogSupersedesMouse ? mousePressure : (pressure + mousePressure)
            }
            else if (axis == MouseSteeringAxisY && (!AnalogSupersedesMouse || pressure == 0)) {
                mousePressure := (ScreenCenter.y - MouseState.Y) * MathVars.MousePressureMult * MouseSteeringAxisY_Mult
                pressure := AnalogSupersedesMouse ? mousePressure : (pressure + mousePressure)
            }
        }
    }
    
    pressure := isStick ? Max(-255, Min(255, pressure)) : Max(0, Min(255, pressure))
    
    if (ADZ_Calc[axis].Raw > 0 && pressure != 0) {
        calc_raw := ADZ_Calc[axis].Raw
        calc_scale := ADZ_Calc[axis].Scale
        
        if (isStick)
            pressure := (pressure > 0) ? calc_raw + (pressure * calc_scale) : -calc_raw + (pressure * calc_scale)
        else if (pressure > 0)
            pressure := calc_raw + (pressure * calc_scale)
    }
    
    finalVal := isStick ? Round(pressure * (pressure < 0 ? CONST.MULT_NEG : CONST.MULT_POS)) : Round(pressure)
    
    if (finalVal != lastAxisState[axis]) {
        lastAxisState[axis] := finalVal
        pad.Axes[axis].SetState(finalVal)
    }
}

FocusLost() {
    Click, Middle Up 
    global lastAxisState, pad, SteerKey
    global ahi, AHIMouseIDs, AHIMouseSubscribed, AHIMouse
    
    ; --- DYNAMIC MOUSE UNSUBSCRIPTION ON FOCUS LOST ---
    if (AHIMouseSubscribed) {
        for _, mId in AHIMouseIDs {
            ahi.UnsubscribeMouseMoveRelative(mId)
        }
        AHIMouseSubscribed := false
        AHIMouse.DeltaX := 0
        AHIMouse.DeltaY := 0
        AHIMouse.StickX := 0
        AHIMouse.StickY := 0
    }

    for axis in lastAxisState {
        if (lastAxisState[axis] != 0) {
            lastAxisState[axis] := 0
            pad.Axes[axis].SetState(0)
        }
    }
    SteerKey.Down := false
    CleanupMouseLockAndHide()
}

CleanupMouseLockAndHide() {
    global WindowState, Cursors, pClipCursor, pSystemParametersInfo
    if (WindowState.Locked) {
        DllCall(pClipCursor, "Ptr", 0)
        WindowState.Locked := false
    }
    if (Cursors.Visible) {
        Gui, Hide
        DllCall(pSystemParametersInfo, "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
        Cursors.Visible := False
    }
    if (Cursors.VertVisible) {
        Gui, 2:Hide
        Cursors.VertVisible := false
    }
    Cursors.EnforceCounter := 0
    Cursors.ForceHide := False
}

CleanUp() {
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    global ahi, EnableAHI, pClipCursor, pSystemParametersInfo, pDestroyCursor, BlankCursor
    if (EnableAHI && IsObject(ahi))
        ahi.Dispose()
    DllCall(pClipCursor, "Ptr", 0)
    DllCall(pSystemParametersInfo, "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
    if (BlankCursor)
        DllCall(pDestroyCursor, "Ptr", BlankCursor)
}

ParseAnalog(iniStr) {
    obj := {}
    if (iniStr == "" || iniStr == "ERROR")
        return obj
    Loop, Parse, iniStr, `,
    {
        parts := StrSplit(A_LoopField, ":")
        if (parts.Length() == 2)
            obj[Trim(parts[1])] := Trim(parts[2]) + 0.0
    }
    return obj
}

ParseDigital(iniStr) {
    arr := []
    if (iniStr == "" || iniStr == "ERROR")
        return arr
    Loop, Parse, iniStr, `,
    {
        parts := StrSplit(A_LoopField, ":")
        if (parts.Length() == 2)
            arr.Push([Trim(parts[1]), Trim(parts[2]) + 0.0])
    }
    return arr
}

ParseArray(iniStr) {
    arr := []
    if (iniStr == "" || iniStr == "ERROR")
        return arr
    Loop, Parse, iniStr, `,
        arr.Push(Trim(A_LoopField))
    return arr
}

ParseAxisAndMult(iniStr) {
    parts := StrSplit(iniStr, ",")
    axis := Trim(parts[1])
    mult := (parts.Length() > 1) ? Trim(parts[2]) + 0.0 : 1.0
    return {Axis: axis, Mult: mult}
}

Core_ahiOnMouseMoveRelative(x, y) {
    global AppState, AHIMouse
    if (AppState.IsGameActive) {
        AHIMouse.DeltaX += x
        AHIMouse.DeltaY += y
    }
}

; === Permanent Keybinds ===
!t::
    Run, "%A_AhkPath%" "%A_ScriptDir%\%launcherName%"
    ExitApp
!y::
    FileDelete, %A_ScriptDir%\$MapperConfigs\.last_profile
    Run, "%A_AhkPath%" "%A_ScriptDir%\%launcherName%"
    ExitApp
!u::ExitApp

; === Tray Icon Labels ===
Profile_Folder:
    Run, %A_ScriptDir%\$MapperConfigs
    return
Edit_Launcher:
    Run, edit "%A_ScriptDir%\%launcherName%"
    return
Reload_Launcher:
    Run, "%A_AhkPath%" "%A_ScriptDir%\%launcherName%"
    ExitApp
Reload_Launcher_with_Selection:
    FileDelete, %A_ScriptDir%\$MapperConfigs\.last_profile
    Run, "%A_AhkPath%" "%A_ScriptDir%\%launcherName%"
    ExitApp
Exit_Script:
    ExitApp
[CORE_LOGIC_END]
*/