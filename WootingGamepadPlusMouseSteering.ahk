; Requires ViGEmBus and Wooting SDK/Wootility to be installed, + bundled scripts and DLLs in .\Lib
; Use Ctrl+Shift at startup or Alt+Y while running to load new config, use Alt+T for regular reload, and Alt+U to close script
; profile aliases and auto-fill on exe detection
Global configAliases := {1: "GridLegends", "gl": "GridLegends"}
Global exeMatches := {["test.exe","GridLegends.exe"]:"GridLegends"} 

#Requires AutoHotkey v1.1
#NoEnv
#Persistent
#SingleInstance Force
#UseHook
#HotkeyInterval 0
SetBatchLines, -1
CoordMode, Mouse, Screen
OnExit("CleanUp")

; === Global State & Constants ===
Global justStarted := true 
Global SysCursorsList := [32512, 32513, 32514, 32515, 32516, 32642, 32643, 32644, 32645, 32646, 32648, 32649, 32650]
VarSetCapacity(AndMask, 128, 0xFF)
VarSetCapacity(XorMask, 128, 0x00)
VarSetCapacity(Rect, 16, 0)
VarSetCapacity(CurrentClip, 16, 0)

Global RButtonSuppressed := false, RButtonDown := false
Global MouseSteeringActive := false, FocusPass := true
Global ScreenCenter := {x: A_ScreenWidth // 2, y: A_ScreenHeight // 2}
Global MaxDist := 0 ; Calculated post-config load
Global xpos := 0, ypos := 0, LastMouseX := 0, LastMouseY := 0
Global lastAxisState := {LX: 0, LY: 0, RX: 0, RY: 0, LT: 0, RT: 0}
Global MouseIsLocked := false, Wx := 0, Wy := 0, Ww := 0, Wh := 0
Global CrossHairVisible := False, ForceCursorHide := False, CursorEnforceCounter := 0
Global VertLineVisible := False

; --- Directory Setup ---
IfNotExist, %A_ScriptDir%\$WootingConfigs
    FileCreateDir, %A_ScriptDir%\$WootingConfigs

; === Boot Sequence ===
activeConfigPath := A_ScriptDir . "\$WootingConfigs\$TEMP_STORED"
if ((DllCall("GetAsyncKeyState", "Int", 0x11) & 0x8000) && (DllCall("GetAsyncKeyState", "Int", 0x10) & 0x8000)) {
    FileDelete, %activeConfigPath%
}

if (!FileExist(activeConfigPath)) {
    ; Determine default profile based on running processes
    defaultProfile := ""
    For exeList, profileName in exeMatches {
        For _, exeName in exeList {
            Process, Exist, %exeName%
            if (ErrorLevel) { ; ErrorLevel is set to the Process ID if the process exists
                defaultProfile := profileName
                break 2 ; Break out of both loops once a match is found
            }
        }
    }

    Loop {
        ; Added %defaultProfile% as the 11th parameter (Default value)
        InputBox, userInput, Load Config, Enter config alias or file name (without .ini):,, 300, 130,,,,, %defaultProfile%
        if ErrorLevel ; Esc pressed during input box
            ExitApp
        userInput := Trim(userInput)
        matchedConfig := ""
        
        if configAliases.HasKey(userInput)
            matchedConfig := configAliases[userInput]
        else if FileExist(A_ScriptDir . "\$WootingConfigs\" . userInput . ".ini")
            matchedConfig := userInput
        
        if (matchedConfig != "") {
            FileAppend, #Include *i `%A_ScriptDir`%\$WootingConfigs\%matchedConfig%.ini, %activeConfigPath%
            Break
        }
    }
    Reload
}

; === Libraries & Device Initialization ===
#Include <AutoHotInterception_v1>
#Include <AHK-ViGEm-Bus_v1>
#Include <SimpleWooting_v1>

Global ahi := new AutoHotInterception()
Global pad := new ViGEmXb360()
Global sw := SimpleWooting_v1
sw.Init()
Global MouseIds := []
for _, dev in ahi.GetDeviceList() {
    if (dev.IsMouse) {
        MouseIds.Push(dev.ID)
    }
}

; === Dynamic Config Load ===
#Include *i %A_ScriptDir%\$WootingConfigs\$TEMP_STORED

; === Validation & Fallbacks ===
; Ensure all required variables exist
if !IsObject(LX_A)
    LX_A := {}
if !IsObject(LY_A)
    LY_A := {}
if !IsObject(RX_A)
    RX_A := {}
if !IsObject(RY_A)
    RY_A := {}
if !IsObject(LT_A)
    LT_A := {}
if !IsObject(RT_A)
    RT_A := {}
if !IsObject(LX_D)
    LX_D := []
if !IsObject(LY_D)
    LY_D := []
if !IsObject(RX_D)
    RX_D := []
if !IsObject(RY_D)
    RY_D := []
if !IsObject(LT_D)
    LT_D := []
if !IsObject(RT_D)
    RT_D := []
EnableMouseSteering     := (EnableMouseSteering != "") ? EnableMouseSteering : false
MouseSteerWidth         := (MouseSteerWidth != "") ? MouseSteerWidth : 1.0
LX_D_MovesMouse         := (LX_D_MovesMouse != "") ? LX_D_MovesMouse : false
WootingSupersedesMouse  := (WootingSupersedesMouse != "") ? WootingSupersedesMouse : false
WootingDeadzone         := (WootingDeadzone != "") ? WootingDeadzone : 8
LX_Antideadzone         := (LX_Antideadzone != "") ? LX_Antideadzone : 0
LY_Antideadzone         := (LY_Antideadzone != "") ? LY_Antideadzone : 0
RX_Antideadzone         := (RX_Antideadzone != "") ? RX_Antideadzone : 0
RY_Antideadzone         := (RY_Antideadzone != "") ? RY_Antideadzone : 0
LT_Antideadzone         := (LT_Antideadzone != "") ? LT_Antideadzone : 0
RT_Antideadzone         := (RT_Antideadzone != "") ? RT_Antideadzone : 0
EnableCursorReplacement := (EnableCursorReplacement != "") ? EnableCursorReplacement : false
EnableMouseLock         := (EnableMouseLock != "") ? EnableMouseLock : false
EnableVerticalLine      := (EnableVerticalLine != "") ? EnableVerticalLine : false
ProfileSpecificBinds    := (ProfileSpecificBinds != "") ? ProfileSpecificBinds : ""

; Normalize exeName into an array and create a Window Group
if (!IsObject(exeName)) {
    if (exeName == "") {
        MsgBox, 16, Error, Provide exeName (as a string or array), ExitApp
    }
    exeName := [exeName]
}
For _, exe in exeName {
    GroupAdd, ActiveGameGroup, ahk_exe %exe%
}

; Post-config calculations
MaxDist := (A_ScreenHeight / 2) * MouseSteerWidth

; === GUI Initialization ===
; Crosshair GUI
Gui, +LastFound +AlwaysOnTop -Caption +ToolWindow +E0x20
Gui, Color, White
Gui, Add, Picture, x0 y0 w16 h16, crosshair.png
WinSet, TransColor, White
Global CrosshairHwnd := WinExist()
Gui, Hide

; Vertical Line GUI
Gui, 2:+LastFound +AlwaysOnTop -Caption +ToolWindow +E0x20
Gui, 2:Color, Red                  
Gui, 2:Add, Progress, x1 y0 w1 h10000 BackgroundBlue 
WinSet, Transparent, 127          
Global LineHwnd := WinExist()
Gui, 2:Hide

; === Start Core Loop ===
UpdateRButtonSuppression(WinActive("ahk_group ActiveGameGroup"))
SetTimer, CoreLoop, 10

FileRead, currentHotkeys, temp_hotkeys.ahk
StringReplace, currentHotkeys, currentHotkeys, `r`n, `n, All
checkBinds := ProfileSpecificBinds
StringReplace, checkBinds, checkBinds, `r`n, `n, All

if (currentHotkeys != checkBinds) {
    FileDelete, temp_hotkeys.ahk
    Loop, 10 {
        If !FileExist("temp_hotkeys.ahk")
            break
        Sleep, 50 ; Wait for the file system to catch up
    }
    If FileExist("temp_hotkeys.ahk") {
        MsgBox, 16, Error, Failed to delete temp_hotkeys.ahk. It may be locked by another process.
        ExitApp
    }
    if (ProfileSpecificBinds != "")
        FileAppend, %ProfileSpecificBinds%, temp_hotkeys.ahk
    
    ; The binds changed, so we must reload immediately to parse them
    Reload
    ExitApp
}

#Include *i temp_hotkeys.ahk ; !!! Included strictly at auto-execute threshold
return ; fallback if Include does not contain auto-execute breaking assignments
; ==========================================
; AUTO-EXECUTE ENDS HERE
; ==========================================

CoreLoop:
    isGameActive := WinActive("ahk_group ActiveGameGroup")
    UpdateRButtonSuppression(isGameActive)
    
    if (isGameActive) { 
        MouseGetPos, xpos, ypos
        
        if (EnableMouseLock || EnableVerticalLine) {
            WinGetPos, nWx, nWy, nWw, nWh, ahk_group ActiveGameGroup 
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

        MouseSteeringActive := (EnableMouseSteering && RButtonDown)
        FocusPass := true
        SetSticks()
        SetTriggers()
        
    } else if (FocusPass) {
        FocusLost()
        FocusPass := false
    }
return

; ==========================================
;               FUNCTIONS
; ==========================================
UpdateRButtonSuppression(gameActive) {
    global
    shouldBlock := (EnableMouseSteering && gameActive && MouseIds.MaxIndex() > 0) 
    if (shouldBlock && !RButtonSuppressed) {
        for _, id in MouseIds {
            ahi.SubscribeMouseButton(id, 1, true, Func("AHI_RButton"))
        }
        RButtonSuppressed := true
    } else if (!shouldBlock && RButtonSuppressed) {
        for _, id in MouseIds {
            ahi.UnsubscribeMouseButton(id, 1)
        }
        RButtonSuppressed := false
        RButtonDown := false
    }
}

AHI_RButton(state) {
    global RButtonDown := state
}

SendRButton(state) {
    global MouseIds, ahi
    for _, id in MouseIds {
        ahi.SendMouseButtonEvent(id, 1, state ? 1 : 0)
    }
}

SetSticks() {
    global
    static axesList := ["LX", "LY", "RX", "RY"]
    
    for _, axis in axesList {
        pressure := 0
        hasDigital := false
        dArray := %axis%_D
        aArray := %axis%_A
        adz := %axis%_Antideadzone
        
        for _, pair in dArray {
            if GetKeyState(pair[1], "P") {
                pressure := pair[2]
                if (axis == "LX" && LX_D_MovesMouse) {
                    targetX := Round(ScreenCenter.x + ((pressure / 255.0) * MaxDist))
                    MouseMove, %targetX%, %ypos%, 0
                }
                hasDigital := true
                break
            }
        }
        
        if (!hasDigital) {
            for key, value in aArray {
                rawVal := sw.RP(key)
                if (WootingDeadzone > 0) {
                    if (WootingDeadzone >= 255)
                        rawVal := 0
                    else
                        rawVal := (rawVal <= WootingDeadzone) ? 0 : (rawVal - WootingDeadzone) * (255.0 / (255 - WootingDeadzone))
                }
                pressure += rawVal * value
            }
                
            if (axis == "LX" && MouseSteeringActive) {
                if (!WootingSupersedesMouse || pressure == 0) {
                    mousePressure := ((xpos - ScreenCenter.x) / MaxDist) * 255
                    pressure := WootingSupersedesMouse ? mousePressure : (pressure + mousePressure)
                }
            }
        }
        
        pressure := Max(-255, Min(255, pressure))
        
        if (adz > 0 && pressure != 0) {
            adzRaw := adz * 2.55
            pressure := (pressure > 0) ? adzRaw + (pressure * ((255 - adzRaw) / 255.0)) : -adzRaw + (pressure * ((255 - adzRaw) / 255.0))
        }
        
        scaledPressure := Round(pressure * (pressure < 0 ? (32768 / 255.0) : (32767 / 255.0)))
        if (scaledPressure != lastAxisState[axis]) {
            lastAxisState[axis] := scaledPressure
            pad.Axes[axis].SetState(scaledPressure)
        }
    }
}

SetTriggers() {
    global
    static triggerList := ["LT", "RT"]
    
    for _, trig in triggerList {
        pressure := 0
        hasDigital := false
        dArray := %trig%_D
        aArray := %trig%_A
        adz := %trig%_Antideadzone
        
        for _, pair in dArray {
            if GetKeyState(pair[1], "P") {
                pressure := pair[2]
                hasDigital := true
                break
            }
        }
        
        if (!hasDigital) {
            for key, value in aArray {
                rawVal := sw.RP(key)
                if (WootingDeadzone > 0) {
                    if (WootingDeadzone >= 255)
                        rawVal := 0
                    else
                        rawVal := (rawVal <= WootingDeadzone) ? 0 : (rawVal - WootingDeadzone) * (255.0 / (255 - WootingDeadzone))
                }
                pressure += rawVal * value
            }
        }
        
        if (adz > 0 && pressure > 0) {
            adzRaw := adz * 2.55
            pressure := adzRaw + (pressure * ((255 - adzRaw) / 255.0))
        }
        
        finalPressure := Round(Max(0, Min(255, pressure)))
        if (finalPressure != lastAxisState[trig]) {
            lastAxisState[trig] := finalPressure
            pad.Axes[trig].SetState(finalPressure)
        }
    }
}

FocusLost() {
    global
    for axis, _ in lastAxisState {
        if (lastAxisState[axis] != 0) {
            lastAxisState[axis] := 0
            pad.Axes[axis].SetState(0)
        }
    }
    if GetKeyState("RButton", "P")
        Send, {RButton up}
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

CleanUp() {
    ; Do not delete the temp file if the script is just reloading or restarting
    if (A_ExitReason != "Reload" && A_ExitReason != "Single")
        FileDelete, temp_hotkeys.ahk
}

; === Permanent Keybinds ===
!t::Reload
!y::
    FileDelete, %A_ScriptDir%\$WootingConfigs\$TEMP_STORED
    Reload
!u::ExitApp
return