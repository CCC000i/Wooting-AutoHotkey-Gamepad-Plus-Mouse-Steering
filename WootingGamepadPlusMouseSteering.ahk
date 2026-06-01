; Requires ViGEmBus and Wooting SDK/Wootility to be installed, + bundled scripts and DLLs in .\Lib

#Requires AutoHotkey v1.1
#NoEnv
#SingleInstance Force
SetBatchLines, -1

; --- Directory Setup & Global Settings Load ---
settingsFile := A_ScriptDir . "\$WootingConfigs\.Settings.ini"
IfNotExist, %A_ScriptDir%\$WootingConfigs
    FileCreateDir, %A_ScriptDir%\$WootingConfigs

IniRead, aliasStr, %settingsFile%, GlobalSettings, configAliases, % ""
IniRead, exeStr, %settingsFile%, GlobalSettings, exeMatches, % ""
configAliases := ParseConfigAliases(aliasStr)
exeMatches := ParseExeMatches(exeStr)

; === Session & Profile Selection ===
sessionFile := A_ScriptDir . "\$WootingConfigs\.last_profile"
matchedConfig := ""

if ((DllCall("GetAsyncKeyState", "Int", 0x11) & 0x8000) && (DllCall("GetAsyncKeyState", "Int", 0x10) & 0x8000))
    FileDelete, %sessionFile%

if FileExist(sessionFile) {
    FileRead, matchedConfig, %sessionFile%
    matchedConfig := Trim(matchedConfig)
}

if (matchedConfig == "") {
    defaultProfile := ""
    For exeList, profileName in exeMatches {
        For _, exeName in exeList {
            Process, Exist, %exeName%
            if (ErrorLevel) { 
                defaultProfile := profileName
                break 2 
            }
        }
    }

    Loop {
        InputBox, userInput, Load Config, Enter config alias or file name (without .ini)`n(Hold Ctrl+Shift on script start to see this again):,, 320, 150,,,,, %defaultProfile%
        if ErrorLevel 
            ExitApp
        userInput := Trim(userInput)
        
        if configAliases.HasKey(userInput)
            matchedConfig := configAliases[userInput]
        else if FileExist(A_ScriptDir . "\$WootingConfigs\" . userInput . ".ini")
            matchedConfig := userInput
        
        if (matchedConfig != "") {
            FileDelete, %sessionFile%
            FileAppend, %matchedConfig%, %sessionFile%
            Break
        }
    }
}

; === Dynamic Config Load ===
configFile := A_ScriptDir . "\$WootingConfigs\" . matchedConfig . ".ini"
Fileread, FileContent, %configFile%
if (ErrorLevel) {
    MsgBox Ini could not be read.
    ExitApp
}
RegExMatch(FileContent, "s)\[CustomCode\]\R*(.*)", Match)
CustomCode := Match1

; === Rebuild and Launch Temporary Script ===
; Read settings for conditional inclusion
IniRead, EnableAHI, %settingsFile%, GlobalSettings, EnableAHI, 1

; Build the includes dynamically
IncludeDirectives := "#Include <AHK-ViGEm-Bus_v1>`n#Include <SimpleWooting_v1>`n"
if (EnableAHI)
    IncludeDirectives := "#Include <AutoHotInterception_v1>`n" . IncludeDirectives

FileRead, selfCode, %A_ScriptFullPath%
RegExMatch(selfCode, "s)\/\*\s*\[CORE_LOGIC_START\]\R(.*?)\R\[CORE_LOGIC_END\]\s*\*\/", coreMatch)
CoreLogic := coreMatch1

CCPath := A_ScriptDir "\$TEMPRUNNINGSCRIPT.ahk"
FileDelete, %CCPath%
; Write Includes followed by Core Logic and Custom Code
FileAppend, %IncludeDirectives%`n%CoreLogic%`n`n; === CUSTOM CODE ===`n%CustomCode%, %CCPath%

Run, "%A_AhkPath%" "%CCPath%" "%matchedConfig%" "%A_ScriptName%", %A_ScriptDir%
ExitApp

; === Launcher Functions ===
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
        obj[exeArr] := profile
        Pos += M.Len(0)
    }
    return obj
}

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
OnExit("CleanUp")
DllCall("winmm\timeBeginPeriod", "UInt", 1) 

matchedConfig := A_Args[1]
launcherName := A_Args[2]

settingsFile := A_ScriptDir . "\$WootingConfigs\.Settings.ini"
configFile := A_ScriptDir . "\$WootingConfigs\" . matchedConfig . ".ini"

IniRead, WootingEnabled, %settingsFile%, GlobalSettings, WootingEnabled, 1
IniRead, ExternalXInputEnabled, %settingsFile%, GlobalSettings, ExternalXInputEnabled, 1
IniRead, EnableAHI, %settingsFile%, GlobalSettings, EnableAHI, 1

; === Global State & Constants ===
Global SysCursorsList := [32512, 32513, 32514, 32515, 32516, 32642, 32643, 32644, 32645, 32646, 32648, 32649, 32650]
VarSetCapacity(AndMask, 128, 0xFF)
VarSetCapacity(XorMask, 128, 0x00)
VarSetCapacity(Rect, 16, 0)
VarSetCapacity(CurrentClip, 16, 0)

Global SteeringKeySuppressed := false, SteeringKeyDown := false
Global MouseSteeringActive := false, FocusPass := true
Global ScreenCenter := {x: A_ScreenWidth // 2, y: A_ScreenHeight // 2}
Global MaxDist := 0 
Global xpos := 0, ypos := 0, LastMouseX := 0, LastMouseY := 0
Global lastAxisState := {LX: 0, LY: 0, RX: 0, RY: 0, LT: 0, RT: 0}
Global MouseIsLocked := false, Wx := 0, Wy := 0, Ww := 0, Wh := 0
Global CrossHairVisible := False, ForceCursorHide := False, CursorEnforceCounter := 0
Global VertLineVisible := False
Global WD_Mult := 1.0, ExtS_Mult := 1.0, ExtT_Mult := 1.0
Global RunAlways := false

; === Pre-ViGEm External Controller Detection ===
Global ExternalGamepads := []
Global ExtPadState := {LX: 0, LY: 0, RX: 0, RY: 0, LT: 0, RT: 0}

if (ExternalXInputEnabled) {
    Global hXInput := DllCall("LoadLibrary", "Str", "xinput1_4.dll", "Ptr")
    if (!hXInput)
        hXInput := DllCall("LoadLibrary", "Str", "xinput1_3.dll", "Ptr")
    Global XInputGetStateStr := hXInput ? (DllCall("GetModuleHandle", "Str", "xinput1_4.dll", "Ptr") ? "xinput1_4\XInputGetState" : "xinput1_3\XInputGetState") : ""

    if (XInputGetStateStr) {
        Loop, 4 {
            idx := A_Index - 1
            VarSetCapacity(XINPUT_STATE, 16, 0)
            if (DllCall(XInputGetStateStr, "UInt", idx, "Ptr", &XINPUT_STATE) == 0)
                ExternalGamepads.Push({Type: "XInput", ID: idx})
        }
    }

    Loop, 16 {
        GetKeyState, joyName, %A_Index%JoyName
        if (joyName != "" && !InStr(joyName, "XBOX"))
            ExternalGamepads.Push({Type: "DInput", ID: A_Index})
    }
}

; === Libraries & Device Initialization ===
#Include <AHK-ViGEm-Bus_v1>
#Include <SimpleWooting_v1>

if (EnableAHI) {
    Global ahi := new AutoHotInterception()
    Global MouseIds := []
    for _, dev in ahi.GetDeviceList() {
        if (dev.IsMouse)
            MouseIds.Push(dev.ID)
    }
}
Global pad := new ViGEmXb360()
Global sw := SimpleWooting_v1
if (WootingEnabled)
    sw.Init()
Global MouseIds := []
for _, dev in ahi.GetDeviceList() {
    if (dev.IsMouse)
        MouseIds.Push(dev.ID)
}

; === Read Arrays and Settings ===
IniRead, SteeringKeyRaw, %configFile%, Settings, SteeringKey, rbutton
Global SteeringKey := NormalizeSteeringKey(SteeringKeyRaw)
Global SteeringKeyDown := false
Global SteeringKeySuppressed := false
Global SteeringButtonId := GetSteeringButtonId(SteeringKey)
IniRead, val, %configFile%, Settings, exeName, ERROR
Global exeName := (val != "ERROR") ? ParseArray(val) : []
IniRead, EnableMouseSteering, %configFile%, Settings, EnableMouseSteering, 0
IniRead, MouseSteerWidth, %configFile%, Settings, MouseSteerWidth, 1.0
IniRead, LX_D_MovesMouse, %configFile%, Settings, LX_D_MovesMouse, 0
IniRead, AnalogSupersedesMouse, %configFile%, Settings, AnalogSupersedesMouse, 0
IniRead, WootingDeadzone, %configFile%, Settings, WootingDeadzone, 8
IniRead, ExtStickDeadzone, %configFile%, Settings, ExtStickDeadzone, 8
IniRead, ExtTriggerDeadzone, %configFile%, Settings, ExtTriggerDeadzone, 8
IniRead, LX_Antideadzone, %configFile%, Settings, LX_Antideadzone, 0
IniRead, LY_Antideadzone, %configFile%, Settings, LY_Antideadzone, 0
IniRead, RX_Antideadzone, %configFile%, Settings, RX_Antideadzone, 0
IniRead, RY_Antideadzone, %configFile%, Settings, RY_Antideadzone, 0
IniRead, LT_Antideadzone, %configFile%, Settings, LT_Antideadzone, 0
IniRead, RT_Antideadzone, %configFile%, Settings, RT_Antideadzone, 0
IniRead, EnableCursorReplacement, %configFile%, Settings, EnableCursorReplacement, 0
IniRead, EnableMouseLock, %configFile%, Settings, EnableMouseLock, 0
IniRead, EnableVerticalLine, %configFile%, Settings, EnableVerticalLine, 0

Global WD_Mult := (WootingDeadzone >= 255 || WootingDeadzone <= 0) ? 0 : (255.0 / (255 - WootingDeadzone))
Global ExtS_Mult := (ExtStickDeadzone >= 255 || ExtStickDeadzone <= 0) ? 0 : (255.0 / (255 - ExtStickDeadzone))
Global ExtT_Mult := (ExtTriggerDeadzone >= 255 || ExtTriggerDeadzone <= 0) ? 0 : (255.0 / (255 - ExtTriggerDeadzone))
MaxDist := (A_ScreenHeight / 2) * MouseSteerWidth

Global LX_A := ParseAnalog(ReadIni(configFile, "LX_A")), LX_D := ParseDigital(ReadIni(configFile, "LX_D", "DigitalBinds"))
Global LY_A := ParseAnalog(ReadIni(configFile, "LY_A")), LY_D := ParseDigital(ReadIni(configFile, "LY_D", "DigitalBinds"))
Global RX_A := ParseAnalog(ReadIni(configFile, "RX_A")), RX_D := ParseDigital(ReadIni(configFile, "RX_D", "DigitalBinds"))
Global RY_A := ParseAnalog(ReadIni(configFile, "RY_A")), RY_D := ParseDigital(ReadIni(configFile, "RY_D", "DigitalBinds"))
Global LT_A := ParseAnalog(ReadIni(configFile, "LT_A")), LT_D := ParseDigital(ReadIni(configFile, "LT_D", "DigitalBinds"))
Global RT_A := ParseAnalog(ReadIni(configFile, "RT_A")), RT_D := ParseDigital(ReadIni(configFile, "RT_D", "DigitalBinds"))

if (exeName.Length() == 0) {
    RunAlways := true
    EnableMouseLock := 0 
}

if (!RunAlways) {
    For _, exe in exeName {
        GroupAdd, ActiveGameGroup, ahk_exe %exe%
    }
}

; === GUI Initialization ===
Gui, +LastFound +AlwaysOnTop -Caption +ToolWindow +E0x20
Gui, Color, White
Gui, Add, Picture, x0 y0 w16 h16, crosshair.png
WinSet, TransColor, White
Global CrosshairHwnd := WinExist()

Gui, 2:+LastFound +AlwaysOnTop -Caption +ToolWindow +E0x20
Gui, 2:Color, Red                  
Gui, 2:Add, Progress, x1 y0 w1 h10000 BackgroundBlue 
WinSet, Transparent, 127          
Global LineHwnd := WinExist()

UpdateSteeringKeySuppression(RunAlways ? true : WinActive("ahk_group ActiveGameGroup"))
SetTimer, CoreLoop, 10
return

; ==========================================
; AUTO-EXECUTE ENDS HERE
; ==========================================

CoreLoop:
    isGameActive := RunAlways ? true : WinActive("ahk_group ActiveGameGroup")
    
    ; Determine Steering Key state based on method
    if (EnableAHI) {
        UpdateSteeringKeySuppression(isGameActive)
    } else if (EnableMouseSteering && isGameActive) {
        SteeringKeyDown := GetKeyState(SteeringKey, "P")
    } else {
        SteeringKeyDown := false
    }

    if (isGameActive) { 
        ReadExternalGamepads()
        
        MouseGetPos, xpos, ypos
        
        if (EnableMouseLock || EnableVerticalLine) {
            if (RunAlways) {
                nWx := 0, nWy := 0, nWw := A_ScreenWidth, nWh := A_ScreenHeight
            } else {
                WinGetPos, nWx, nWy, nWw, nWh, ahk_group ActiveGameGroup 
            }

            if (nWx != Wx || nWy != Wy || nWw != Ww || nWh != Wh) {
                Wx := nWx, Wy := nWy, Ww := nWw, Wh := nWh
                NumPut(Wx, Rect, 0, "Int"), NumPut(Wy, Rect, 4, "Int")
                NumPut(Wx + Ww, Rect, 8, "Int"), NumPut(Wy + Wh, Rect, 12, "Int")
                if (EnableVerticalLine && VertLineVisible)
                    Gui, 2:Show, x0 y0 w3 h%Wh% NoActivate, VertLine
            }
        }

        if (EnableMouseLock) {
            DllCall("GetClipCursor", "Ptr", &CurrentClip)
            if (NumGet(CurrentClip, 0, "Int") != Wx || NumGet(CurrentClip, 4, "Int") != Wy || NumGet(CurrentClip, 8, "Int") != Wx + Ww || NumGet(CurrentClip, 12, "Int") != Wy + Wh) {
                DllCall("ClipCursor", "Ptr", &Rect)
                if (EnableCursorReplacement)
                    ForceCursorHide := True 
            }
            MouseIsLocked := true
        } else if (MouseIsLocked) {
            DllCall("ClipCursor", "Ptr", 0)
            MouseIsLocked := false
        }

        if (EnableCursorReplacement) {
            if (!CrossHairVisible || ForceCursorHide || ++CursorEnforceCounter >= 50) {
                if !CrossHairVisible
                    Gui, Show, x0 y0 w16 h16 NoActivate, Crosshair
                CrossHairVisible := True, CursorEnforceCounter := 0, ForceCursorHide := False
                
                For _, cursorID in SysCursorsList {
                    hCursor := DllCall("CreateCursor", "Ptr", 0, "Int", 0, "Int", 0, "Int", 32, "Int", 32, "Ptr", &AndMask, "Ptr", &XorMask, "Ptr")
                    DllCall("SetSystemCursor", "Ptr", hCursor, "UInt", cursorID)
                }
            }
        } else if (CrossHairVisible) {
            Gui, Hide
            DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
            CrossHairVisible := False, CursorEnforceCounter := 0, ForceCursorHide := False
        }

        if (EnableVerticalLine) {
            if !VertLineVisible
                Gui, 2:Show, x0 y0 w3 h%Wh% NoActivate, VertLine
            VertLineVisible := true
        } else if (VertLineVisible) {
            Gui, 2:Hide
            VertLineVisible := false
        }

        if (xpos != LastMouseX || ypos != LastMouseY) {
            if (EnableCursorReplacement && CrossHairVisible)
                DllCall("SetWindowPos", "Ptr", CrosshairHwnd, "Ptr", 0, "Int", xpos-8, "Int", ypos-8, "Int", 0, "Int", 0, "UInt", 0x15)
            if (EnableVerticalLine && VertLineVisible)
                DllCall("SetWindowPos", "Ptr", LineHwnd, "Ptr", 0, "Int", xpos, "Int", Wy, "Int", 0, "Int", 0, "UInt", 0x15)
            LastMouseX := xpos, LastMouseY := ypos
        }

        MouseSteeringActive := (EnableMouseSteering && SteeringKeyDown)
        FocusPass := true
        
        UpdateVirtualAxis("LX", true, LX_D, LX_A, LX_Antideadzone)
        UpdateVirtualAxis("LY", true, LY_D, LY_A, LY_Antideadzone)
        UpdateVirtualAxis("RX", true, RX_D, RX_A, RX_Antideadzone)
        UpdateVirtualAxis("RY", true, RY_D, RY_A, RY_Antideadzone)
        UpdateVirtualAxis("LT", false, LT_D, LT_A, LT_Antideadzone)
        UpdateVirtualAxis("RT", false, RT_D, RT_A, RT_Antideadzone)
        
    } else if (FocusPass) {
        FocusLost()
        FocusPass := false
    }
return

; ==========================================
;                 FUNCTIONS
; ==========================================

ReadExternalGamepads() {
    global ExternalGamepads, ExtPadState, XInputGetStateStr

    ExtPadState.LX := 0, ExtPadState.LY := 0, ExtPadState.RX := 0, ExtPadState.RY := 0, ExtPadState.LT := 0, ExtPadState.RT := 0

    for _, padObj in ExternalGamepads {
        if (padObj.Type == "XInput" && XInputGetStateStr) {
            VarSetCapacity(XINPUT_STATE, 16, 0)
            if (DllCall(XInputGetStateStr, "UInt", padObj.ID, "Ptr", &XINPUT_STATE) == 0) {
                ExtPadState.LT := NumGet(XINPUT_STATE, 6, "UChar")
                ExtPadState.RT := NumGet(XINPUT_STATE, 7, "UChar")
                ExtPadState.LX := Round(NumGet(XINPUT_STATE, 8, "Short") / 128.50196)
                ExtPadState.LY := Round(NumGet(XINPUT_STATE, 10, "Short") / 128.50196)
                ExtPadState.RX := Round(NumGet(XINPUT_STATE, 12, "Short") / 128.50196)
                ExtPadState.RY := Round(NumGet(XINPUT_STATE, 14, "Short") / 128.50196)
                break 
            }
        } else if (padObj.Type == "DInput") {
            id := padObj.ID
            GetKeyState, jX, %id%JoyX
            if (jX != "") {
                GetKeyState, jY, %id%JoyY
                GetKeyState, jZ, %id%JoyZ 
                GetKeyState, jR, %id%JoyR 
                GetKeyState, jU, %id%JoyU 

                nX := (Abs(jX - 50) < 0.8) ? 50 : jX
                nY := (Abs(jY - 50) < 0.8) ? 50 : jY
                nU := (Abs(jU - 50) < 0.8) ? 50 : jU
                nR := (Abs(jR - 50) < 0.8) ? 50 : jR

                ExtPadState.LX := Max(-255, Min(255, Round((nX - 50) * 5.1)))
                ExtPadState.LY := Max(-255, Min(255, Round((nY - 50) * -5.1)))
                ExtPadState.RX := Max(-255, Min(255, Round((nU - 50) * 5.1)))
                ExtPadState.RY := Max(-255, Min(255, Round((nR - 50) * -5.1)))

                ExtPadState.LT := (jZ > 50.5) ? Max(0, Min(255, Round((jZ - 50) * 5.1))) : 0
                ExtPadState.RT := (jZ < 49.5) ? Max(0, Min(255, Round((50 - jZ) * 5.1))) : 0
                break
            }
        }
    }
}

ReadIni(file, key, section := "AnalogBinds") {
    IniRead, out, %file%, %section%, %key%, ERROR
    return out
}

UpdateVirtualAxis(axis, isStick, ByRef dArray, ByRef aArray, adz) {
    global lastAxisState, ScreenCenter, MaxDist, ypos, xpos
    global LX_D_MovesMouse, WootingDeadzone, WD_Mult, MouseSteeringActive, AnalogSupersedesMouse
    global ExtPadState, ExtStickDeadzone, ExtTriggerDeadzone, ExtS_Mult, ExtT_Mult, WootingEnabled
    
    pressure := 0, hasDigital := false
    
    for _, pair in dArray {
        if GetKeyState(pair[1], "P") {
            pressure := pair[2]
            if (isStick && axis == "LX" && LX_D_MovesMouse) {
                targetX := Round(ScreenCenter.x + ((pressure / 255.0) * MaxDist))
                MouseMove, %targetX%, %ypos%, 0
            }
            hasDigital := true
            break
        }
    }
    
    if (!hasDigital) {
        for key, value in aArray {
            if (WootingEnabled)
                rawVal := sw.RP(key)
            if (WootingDeadzone > 0)
                rawVal := (rawVal <= WootingDeadzone) ? 0 : (rawVal - WootingDeadzone) * WD_Mult
            pressure += rawVal * value
        }
        
        extVal := 0
        if (isStick) {
            rawExt := ExtPadState[axis]
            absExt := Abs(rawExt)
            if (ExtStickDeadzone > 0)
                absExt := (absExt <= ExtStickDeadzone) ? 0 : (absExt - ExtStickDeadzone) * ExtS_Mult
            extVal := rawExt < 0 ? -absExt : absExt
        } else {
            rawExt := ExtPadState[axis]
            if (ExtTriggerDeadzone > 0)
                extVal := (rawExt <= ExtTriggerDeadzone) ? 0 : (rawExt - ExtTriggerDeadzone) * ExtT_Mult
            else
                extVal := rawExt
        }
        pressure += extVal
        
        if (isStick && axis == "LX" && MouseSteeringActive) {
            if (!AnalogSupersedesMouse || pressure == 0) {
                mousePressure := ((xpos - ScreenCenter.x) / MaxDist) * 255
                pressure := AnalogSupersedesMouse ? mousePressure : (pressure + mousePressure)
            }
        }
    }
    
    pressure := isStick ? Max(-255, Min(255, pressure)) : Max(0, Min(255, pressure))
    
    if (adz > 0 && pressure != 0) {
        adzRaw := adz * 2.55
        if (isStick)
            pressure := (pressure > 0) ? adzRaw + (pressure * ((255 - adzRaw) / 255.0)) : -adzRaw + (pressure * ((255 - adzRaw) / 255.0))
        else if (pressure > 0)
            pressure := adzRaw + (pressure * ((255 - adzRaw) / 255.0))
    }
    
    finalVal := Round(isStick ? (pressure * (pressure < 0 ? 128.50196 : 128.49803)) : pressure) 
    if (finalVal != lastAxisState[axis]) {
        lastAxisState[axis] := finalVal
        pad.Axes[axis].SetState(finalVal)
    }
}

UpdateSteeringKeySuppression(gameActive) {
    global
    if (!EnableAHI)
        return

    shouldBlock := (EnableMouseSteering && gameActive && MouseIds.Length() > 0)

    if (shouldBlock && !SteeringKeySuppressed) {
        callbackFn := Func("AHI_" . SteeringKey)

        for _, id in MouseIds
            ahi.SubscribeMouseButton(id, SteeringButtonId, true, callbackFn)

        SteeringKeySuppressed := true

    } else if (!shouldBlock && SteeringKeySuppressed) {
        for _, id in MouseIds
            ahi.UnsubscribeMouseButton(id, SteeringButtonId)

        SteeringKeySuppressed := false
        SteeringKeyDown := false
    }
}

AHI_LButton(state) {
    AHI_SteeringKey(state)
}

AHI_RButton(state) {
    AHI_SteeringKey(state)
}

AHI_MButton(state) {
    AHI_SteeringKey(state)
}

AHI_XButton1(state) {
    AHI_SteeringKey(state)
}

AHI_XButton2(state) {
    AHI_SteeringKey(state)
}

AHI_SteeringKey(state) {
    global SteeringKeyDown
    SteeringKeyDown := state
}

FocusLost() {
    global
    for axis in lastAxisState {
        if (lastAxisState[axis] != 0) {
            lastAxisState[axis] := 0
            pad.Axes[axis].SetState(0)
        }
    }
	if GetKeyState(SteeringKey, "P")
		Send, {%SteeringKey% up}
    CleanupMouseLockAndHide()
}

CleanupMouseLockAndHide() {
    global
    if (MouseIsLocked) {
        DllCall("ClipCursor", "Ptr", 0)
        MouseIsLocked := false
    }
    if (CrossHairVisible) {
        Gui, Hide
        DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
        CrossHairVisible := False
    }
    if (VertLineVisible) {
        Gui, 2:Hide
        VertLineVisible := false
    }
    CursorEnforceCounter := 0
    ForceCursorHide := False
}

NormalizeSteeringKey(key) {
    key := Trim(key)
    StringLower, key, key

    if (key = "lbutton" || key = "rbutton" || key = "mbutton" || key = "xbutton1" || key = "xbutton2")
        return key

    return "rbutton"
}

GetSteeringButtonId(key) {
    static map := {lbutton: 0, rbutton: 1, mbutton: 2, xbutton1: 3, xbutton2: 4}
    key := NormalizeSteeringKey(key)
    return map[key]
}

CleanUp() {
    DllCall("ClipCursor", "Ptr", 0)
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
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

; === Permanent Keybinds ===
!t::
    Run, "%A_AhkPath%" "%A_ScriptDir%\%launcherName%"
    ExitApp
!y::
    FileDelete, %A_ScriptDir%\$WootingConfigs\.last_profile
    Run, "%A_AhkPath%" "%A_ScriptDir%\%launcherName%"
    ExitApp
!u::ExitApp
return
[CORE_LOGIC_END]
*/