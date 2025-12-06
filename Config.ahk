; =============================================================================
; Licence : GNU GPL v3 - https://www.gnu.org/licenses/gpl-3.0.html
; Auteur : Jibap - https://github.com/jibap/
; GUI qui permet de configurer Limithor (gestion des utilisateurs, quotas, etc.)
; =============================================================================

#Warn
#SingleInstance force ; Ecrase si instance en cours
#Include <JSON>  ; Inclure la bibliothèque JSON
#Include <GuiCtrlTips>

; =========================================
; Elevation auto (admin requis)
; =========================================
if A_IsCompiled && !A_IsAdmin {
    try {
        ; Demande l'élévation des privilèges
        Run '*RunAs "' A_ScriptFullPath '"'
    } 
    ExitApp()
}

; =========================================
; Includes
; =========================================
#Include "*i version.txt" ; utilisé lors de la compilation
if !A_IsCompiled || !IsSet(currentVersion) { ; fallback si non compilé
    currentVersion := "AHK_DIRECT"
}
#Include "*i updater.ahk" ; gestion des mises à jour

; VÉRIFICATION MISES À JOUR, SI INCLUSE
try{
    CheckForUpdate()
}

; #### ##    ## #### ########
;  ##  ###   ##  ##     ##
;  ##  ####  ##  ##     ##
;  ##  ## ## ##  ##     ##
;  ##  ##  ####  ##     ##
;  ##  ##   ###  ##     ##
; #### ##    ## ####    ##

SetWorkingDir(A_ScriptDir)
configFile := A_ScriptDir "\config.json"
refuseUpdate := false
jsonObj := ""
lastUserSelected := ""

; ICONES
validIconID := "301"
quitIconID := "132"
settingsIconID := "315"
helpIconID := "222"
contactIconID := "161"
deleteIconID := "32"

; DETERMINE LA VERSION DE WINDOWS
objWMIService := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\" A_ComputerName "\root\cimv2")
for objOperatingSystem in objWMIService.ExecQuery("Select * from Win32_OperatingSystem")
    windowsVersion := objOperatingSystem.Caption
; SI WINDOWS 10
if (InStr(windowsVersion, "10")) {
    validIconID := "297"
    settingsIconID := "317"
}

;  ######   #######  ##    ## ######## ####  ######       ######   ##     ## ####
; ##    ## ##     ## ###   ## ##        ##  ##    ##     ##    ##  ##     ##  ##
; ##       ##     ## ####  ## ##        ##  ##           ##        ##     ##  ##
; ##       ##     ## ## ## ## ######    ##  ##   ####    ##   #### ##     ##  ##
; ##       ##     ## ##  #### ##        ##  ##    ##     ##    ##  ##     ##  ##
; ##    ## ##     ## ##   ### ##        ##  ##    ##     ##    ##  ##     ##  ##
;  ######   #######  ##    ## ##       ####  ######       ######    #######  ####

ConfigGUI := Gui("")
ConfigGUI.Title := "Limithor - Configuration"
ConfigGUI.MarginX := 0

initTips(ConfigGUI)

; Logo
ConfigGUI.Add("Picture", "x0 y0 w450 h90 BackgroundWhite")  ; Zone blanche en arrière-plan
; --- Logo + titre au-dessus ---
if (!A_IsCompiled) {
    iconPath := A_ScriptDir "\Limithor.ico"
} else {
    iconPath := A_ScriptFullPath
}
ConfigGUI.Add("Picture", "x30 y10 w64 h64 +BackgroundTrans icon1", iconPath)
ConfigGUI.SetFont("s20")
ConfigGUI.Add("Text", "x120 y10 +BackgroundTrans", "Limithor")
ConfigGUI.SetFont("s30")
ConfigGUI.Add("Text", "x100 yp+20 +BackgroundTrans", "Configuration")
ConfigGUI.SetFont("s10 norm")


; Liste déroulante des comptes
UserList := ConfigGUI.Add("ListBox", "xs+15 y+30 h200")
UserList.OnEvent("Change", userSelected)

SaveButton := ConfigGUI.Add("Button", "w155 h35 Disabled", A_Space . "Enregistrer")
SetButtonIcon(SaveButton, "shell32.dll", validIconID, 20)
SaveButton.OnEvent("Click", saveConfig)

; Champs de paramétrage
ConfigGUI.SetFont("s15")
ConfigGUI.Add("Picture", "Icon" . contactIconID . " x+10 y110 w36 h36", "shell32.dll")
UsernameSelected := ConfigGUI.Add("Text", "x+5 yp-5 w100", "")

UserEnabledCB := ConfigGUI.Add("Checkbox", "", "Activé")
UserEnabledCB.OnEvent("Click", userHasChanged)
ConfigGUI.SetFont("s10 norm")

ChronoModeCB := ConfigGUI.Add("Checkbox", "x+10 yp+3", "Mode chrono")
ChronoModeCB.OnEvent("Click", chronoModeCBChanged)

chronoHelp := ConfigGUI.Add("Picture", "Icon" . helpIconID . " x+0 w16 h16 +0x0100", "shell32.dll")
ConfigGUI.Tips.SetTip(chronoHelp, "Le temps de session est compté mais il n'y a pas de déconnexion.`nÀ la fin de la période choisie, le temps compté est remis à zéro`net conservé dans l'historique (si activé).")

ConfigGUI.Add("GroupBox", "x180 y+30 w240 h50", "Périodicité")
radioPeriodH := ConfigGUI.Add("Radio", "xp+10 yp+20 Group", "Hebdomadaire")
radioPeriodQ := ConfigGUI.Add("Radio", "x+20 ", "Quotidien")
radioPeriodH.OnEvent("Click", userHasChanged)
radioPeriodQ.OnEvent("Click", userHasChanged)

ConfigGUI.Add("GroupBox", "x180 y+30 w240 h50", "Quota")
quotaEdit := ConfigGUI.Add("Edit", "xp+10 yp+15 w30 Right Number", "0")
quotaEdit.OnEvent("Change", quotaChanged)

RadioQuotaUnitM := ConfigGUI.Add("Radio", "x+10 yp+5 Group", "Minutes")
RadioQuotaUnitH := ConfigGUI.Add("Radio", "x+20", "Heure(s)")
RadioQuotaUnitM.OnEvent("Click", quotaChanged)
RadioQuotaUnitH.OnEvent("Click", quotaChanged)

ConfigGUI.Add("Text", "x180 y+30", "Temps restant :")
remainingMinutes := ConfigGUI.Add("Edit", "x+10 w40 Right Number", "0")
ConfigGUI.Add("Text", "x+10", "(minutes)")
remainingMinutes.OnEvent("Change", remainingMinutesChanged)

ConfigGUI.Add("Picture", "x0 y+20 w450 h2 BackgroundSilver")

logCB := ConfigGUI.Add("Checkbox", "x20 y+15", "Activer l'historique")
logCB.OnEvent("Click", toggleLogs)

resetLogImg := ConfigGUI.Add("Picture", "Icon" . deleteIconID . " x+0 yp-5 w24 h24 +0x0100", "shell32.dll")
ConfigGUI.Tips.SetTip(resetLogImg, "Réinitialiser l'historique")
resetLogImg.OnEvent("Click", resetLog)

ExitButton := ConfigGUI.Add("Button", "x+35 yp-5 w200 h35", A_Space . "Quitter")
SetButtonIcon(ExitButton, "shell32.dll", quitIconID, 24)
ExitButton.OnEvent("Click", ExitAppli)


; ######## ##     ## ##    ##  ######  ######## ####  #######  ##    ##  ######
; ##       ##     ## ###   ## ##    ##    ##     ##  ##     ## ###   ## ##    ##
; ##       ##     ## ####  ## ##          ##     ##  ##     ## ####  ## ##
; ######   ##     ## ## ## ## ##          ##     ##  ##     ## ## ## ##  ######
; ##       ##     ## ##  #### ##          ##     ##  ##     ## ##  ####       ##
; ##       ##     ## ##   ### ##    ##    ##     ##  ##     ## ##   ### ##    ##
; ##        #######  ##    ##  ######     ##    ####  #######  ##    ##  ######


ExitAppli(*) {
    if (SaveButton.Enabled) {
        response := MsgBox("Des modifications n'ont pas été enregistrées.`n`nQuitter ?", "Limithor", "YesNo Icon!")
        if (response = "No") {
            return
        }
    }
    if (A_IsCompiled) {
        RunWait('sc start Limithor', , "Hide")
    }
    ExitApp
}

initTips(GUIObj) {
    GUIObj.Tips := GuiCtrlTips(GUIObj)
    GUIObj.Tips.SetBkColor(0xFFFFFF)
    GUIObj.Tips.SetTxColor(0x404040)
    GUIObj.Tips.SetMargins(4, 4, 4, 4)
}

; Fonction spéciale pour les GUI, permet d'afficher une icone dans un bouton
SetButtonIcon(Button, File, Index, Size := 16) {
    hIcon := LoadPicture(File, "h" . Size . " Icon" . Index, &_)
    ErrorLevel := SendMessage(0xF7, 1, hIcon, , "ahk_id " Button.hwnd)
}

toggleLogs(*) {
    global jsonObj

    jsonObj["log"] := logCB.Value ? JSON.true : JSON.false
    saveJSON()
}

userHasChanged(*) {
    SaveButton.Enabled := true
}

fillUserList() {
    global jsonObj

    users := []

    ; récupère tous les utilisateurs locaux
    if (jsonObj.Has("users") > 0) {
        for username, _ in jsonObj["users"] {
            users.Push(username)
        }
        UserList.Add(users)
    }
}

getJSON() {
    global jsonObj
    if FileExist(configFile) {
        content := FileRead(configFile, "UTF-8")
        try {
            jsonObj := JSON.parse(content, true)
        }
        catch {
            response := MsgBox("Erreur lors de l'analyse du fichier de configuration :`n`n" content "`n`nFermer le programme ?",
                "Limithor", "YesNo Icon!")
            if (response = "Yes")
                ExitApp
            return "error"
        }
    } else {
        response := MsgBox("Fichier de configuration introuvable : `n`n" configFile "`n`nFermer le programme ?",
            "Limithor", "YesNo Icon!")
        if (response = "Yes")
            ExitApp
        return "error"
    }
}

userSelected(*) {
    global lastUserSelected
    if (SaveButton.Enabled) {
        response := MsgBox("Des modifications n'ont pas été enregistrées.`n`nChanger quand même d'utilisateur ?",
            "Limithor", "YesNo Icon!")
        if (response = "No") {
            UserList.Value := lastUserSelected
            return
        }
    }
    lastUserSelected := UserList.Value
    SaveButton.Enabled := false
    currentUser := jsonObj["users"][UserList.Text]
    currentUserConfig := currentUser.Has("config") ? currentUser["config"] : {}

    UsernameSelected.Text := UserList.Text
    
    UserEnabledCB.Value := (currentUserConfig.Has("enabled") && currentUserConfig["enabled"] == JSON.true) ? true : false
    ChronoModeCB.Value := (currentUserConfig.Has("limitDuration") && currentUserConfig["limitDuration"] = 0) ? true : false
    radioPeriodH.Value := (currentUserConfig.Has("limitType") && currentUserConfig["limitType"] = "weekly") ? true : false
    radioPeriodQ.Value := (currentUserConfig.Has("limitType") && currentUserConfig["limitType"] = "daily") ? true : false
    quotaInMinutes := currentUserConfig.Has("limitDuration") ? currentUserConfig["limitDuration"] : 0

    if (ChronoModeCB.Value)
        chronoChecked(true)

    ; Détermine l'unité du quota
    if (quotaInMinutes > 60 && (Mod(quotaInMinutes, 60) = 0)) {
        RadioQuotaUnitM.Value := false
        RadioQuotaUnitH.Value := true
        quotaEdit.Value := Round(quotaInMinutes / 60)
    } else {
        RadioQuotaUnitM.Value := true
        RadioQuotaUnitH.Value := false
        quotaEdit.Value := quotaInMinutes
    }

    currentUserState := currentUser.Has("state") ? currentUser["state"] : {}
    currentUserUsedDuration := currentUserState.Has("usedDuration") ? currentUserState["usedDuration"] : 0
    currentUserRemaining := quotaInMinutes - currentUserUsedDuration
    if (currentUserRemaining < 0) {
        currentUserRemaining := 0
    }
    remainingMinutes.Value := currentUserRemaining
}

saveConfig(*) {
    global jsonObj

    selectedUser := UserList.Text
    if (!selectedUser || !jsonObj["users"].Has(selectedUser))
        return

    userObj := jsonObj["users"][selectedUser]
    if !userObj.Has("config")
        userObj["config"] := {}

    cfg := userObj["config"]

    ; état activé
    cfg["enabled"] := UserEnabledCB.Value ? JSON.true : JSON.false

    ; périodicité
    if (radioPeriodH.Value)
        cfg["limitType"] := "weekly"
    else if (radioPeriodQ.Value)
        cfg["limitType"] := "daily"

    ; quota
    quota := quotaEdit.Value * 1
    if (RadioQuotaUnitH.Value)
        quota := quota * 60

    cfg["limitDuration"] := quota

    usedDuration := quota - remainingMinutes.Value
    if (usedDuration < 0) {
        usedDuration := 0
    }
    userObj["state"]["usedDuration"] := usedDuration

    ; journal
    jsonObj["log"] := logCB.Value ? JSON.true : JSON.false

    ; écriture fichier
    saveJSON()

    SaveButton.Enabled := false
}

saveJSON() {
    jsonText := JSON.stringify(jsonObj, 4)
    FileDelete(configFile)
    FileAppend(jsonText, configFile, "UTF-8")
}

chronoModeCBChanged(*){
    chronoChecked(false)
}

chronoChecked(init := false) {
    quotaEdit.Enabled := !ChronoModeCB.Value
    RadioQuotaUnitM.Enabled := !ChronoModeCB.Value
    RadioQuotaUnitH.Enabled := !ChronoModeCB.Value
    remainingMinutes.Enabled := !ChronoModeCB.Value
    quotaEdit.Value := ChronoModeCB.Value ? 0 : 1
    if (ChronoModeCB.Value = false) {
        RadioQuotaUnitH.Value := true
        RadioQuotaUnitM.Value := false
    }
    if !init{ ; besoin de faire suivre les changements si cliqué par l'utilisateur et non à l'initialisation
        quotaChanged()
        userHasChanged()
    }
}

quotaChanged(*) {
    if (quotaEdit.Value != "") {
        if (RadioQuotaUnitM.Value == true) {
            remainingMinutes.Value := quotaEdit.Value
        } else {
            remainingMinutes.Value := quotaEdit.Value * 60
        }
    }
    userHasChanged()
}

remainingMinutesChanged(*) {
    if (remainingMinutes.Value != "") {
        if (RadioQuotaUnitM.Value == true) {
            if (remainingMinutes.Value > quotaEdit.Value) {
                remainingMinutes.Value := quotaEdit.Value
            }
        } else {
            if (remainingMinutes.Value > quotaEdit.Value * 60) {
                remainingMinutes.Value := quotaEdit.Value * 60
            }
        }
        userHasChanged()
    }
}

resetLog(*) {
    if (FileExist(A_ScriptDir "\service.log")) {
        FileDelete(A_ScriptDir "\service.log")
        MsgBox("L'historique a été réinitialisé.", "Limithor", "Iconi")
    } else {
        MsgBox("Aucun historique n'a été trouvé.", "Limithor", "Icon!")
    }
}

; ########  ##     ## ##    ##
; ##     ## ##     ## ###   ##
; ##     ## ##     ## ####  ##
; ########  ##     ## ## ## ##
; ##   ##   ##     ## ##  ####
; ##    ##  ##     ## ##   ###
; ##     ##  #######  ##    ##

if (A_IsCompiled) {
    RunWait('sc stop Limithor', , "Hide")
}
getJSON()
; Remplit la liste des utilisateurs
if jsonObj.Has("users") {
    fillUserList()
    UserList.Value := 1
    userSelected()
}
; Initialise l'état du journal
if jsonObj.Has("log") {
    logCB.Value := jsonObj["log"] == JSON.true ? true : false
}

ConfigGUI.Show()