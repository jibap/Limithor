; =============================================================================
; Licence : GNU GPL v3 - https://www.gnu.org/licenses/gpl-3.0.html
; Auteur : Jibap - https://github.com/jibap/
; GUI qui permet de voir la config utilisateur Limithor (affichage du temps restant) + notifications dans la barre des tâches
; =============================================================================

#SingleInstance Force
#Include <JSON>  ; Inclure la bibliothèque JSON

#Include "*i version.txt" ; utilisé lors de la compilation
if !A_IsCompiled || !IsSet(currentVersion) { ; fallback si non compilé
    currentVersion := "AHK_DIRECT"
}

; Vérifie si l'utilisateur est membre du groupe Administrateurs par SID (plus fiable, multilingue)
; adminUser := false
; cmd := 'whoami /groups | find "S-1-5-32-544"'
; exitCode := RunWait(A_ComSpec ' /c ' cmd, , 'Hide')

; if (exitCode = 0){
;     adminUser := true
; }

; #### ##    ## #### ########
;  ##  ###   ##  ##     ##
;  ##  ####  ##  ##     ##
;  ##  ## ## ##  ##     ##
;  ##  ##  ####  ##     ##
;  ##  ##   ###  ##     ##
; #### ##    ## ####    ##

; ICONES
settingsIconID := "315"

; DETERMINE LA VERSION DE WINDOWS
objWMIService := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\" A_ComputerName "\root\cimv2")
for objOperatingSystem in objWMIService.ExecQuery("Select * from Win32_OperatingSystem")
    windowsVersion := objOperatingSystem.Caption
; SI WINDOWS 10
if (InStr(windowsVersion, "10")) {
    settingsIconID := "317"
}

lastMinutes := ""

Persistent
OnExit(ExitAppli)
OnMessage(0x404, OnTrayClick)
SetWorkingDir(A_ScriptDir)

; CREATION DU TRAYMENU
; *********************
trayMenu := A_TrayMenu
trayMenu.Delete() ; Supprime les menus par défaut
trayMenu.add("Afficher le profil", displayConfig)
trayMenu.add("Afficher le temps restant", checkFromTray)
trayMenu.add()
trayMenu.add("Configurer", runConfig)
trayMenu.add()
trayMenu.add("Quitter", ExitAppli)
trayMenu.Default := "1&"

; ##     ##  ######  ######## ########      ######   ##     ## ####
; ##     ## ##    ## ##       ##     ##    ##    ##  ##     ##  ##
; ##     ## ##       ##       ##     ##    ##        ##     ##  ##
; ##     ##  ######  ######   ########     ##   #### ##     ##  ##
; ##     ##       ## ##       ##   ##      ##    ##  ##     ##  ##
; ##     ## ##    ## ##       ##    ##     ##    ##  ##     ##  ##
;  #######   ######  ######## ##     ##     ######    #######  ####

UserGUI := Gui("")
UserGUI.Title := "Limithor"
UserGUI.MarginX := 0

; Logo
UserGUI.Add("Picture", "x0 y0 w260 h90 BackgroundWhite")  ; Zone blanche en arrière-plan
; --- Logo + titre au-dessus ---
if (!A_IsCompiled) {
    iconPath := A_ScriptDir "\Limithor.ico"
} else {
    iconPath := A_ScriptFullPath
}
UserGUI.Add("Picture", "x30 y10 w64 h64 +BackgroundTrans icon1", iconPath)
UserGUI.SetFont("s30")
UserGUI.Add("Text", "x100 yp+20 +BackgroundTrans", "Limithor")

UserGUI.SetFont("s20")
Username := UserGUI.Add("Text", "x80 y150 w150", "")
UserGUI.SetFont("s10 norm")
PeriodType := UserGUI.Add("Text", "x100 yp+30 w150", "")

borderProgress := UserGUI.Add("Picture", "x19 y99 w32 h152 BackgroundBlack")
progressBar := UserGUI.Add("Progress", "x20 y100 w30 h150 vertical Backgrounde2e2e2 c1BBCA8", "")

Quota := UserGUI.Add("Text", "x60 y100  w150", "")
UserGUI.SetFont("c1BBCA8  s11 bold")
RemainingDuration := UserGUI.Add("Text", "x60 y230  w200", "")

UserGUI.SetFont("s10 norm")

settingsButton := UserGUI.Add("Button", "x18 y260 w35 h40 +BackgroundTrans +0x40 +0x0C", A_Space)
SetButtonIcon(settingsButton, "shell32.dll", settingsIconID, 24)
settingsButton.OnEvent("Click", runConfig)

quitButton := UserGUI.Add("Button", "x60 y260 w180 h40 +BackgroundTrans", "Fermer")
quitButton.OnEvent("Click", CloseGui)

; ########  #######  ##    ##  ######  ######## ####  #######  ##    ##  ######
; ##       ##     ## ###   ## ##    ##    ##     ##  ##     ## ###   ## ##    ##
; ##       ##     ## ####  ## ##          ##     ##  ##     ## ####  ## ##
; ######   ##     ## ## ## ## ##          ##     ##  ##     ## ## ## ##  ######
; ##       ##     ## ##  #### ##          ##     ##  ##     ## ##  ####       ##
; ##       ##     ## ##   ### ##    ##    ##     ##  ##     ## ##   ### ##    ##
; ##        #######  ##    ##  ######     ##    ####  #######  ##    ##  ######

ExitAppli(*) {
    ExitApp
}

CloseGui(*) {
    UserGUI.Hide()
}

displayConfig(*) {
    GetRemainingMinutes(true)
}

restartAsAdmin(*) {
    Run '*RunAs "' A_ScriptFullPath '"'
    ExitApp
}

checkFromTray(*) {
    check(true)
}

; Fonction spéciale pour les GUI, permet d'afficher une icone dans un bouton
SetButtonIcon(Button, File, Index, Size := 16) {
    hIcon := LoadPicture(File, "h" . Size . " Icon" . Index, &_)
    ErrorLevel := SendMessage(0xF7, 1, hIcon, , "ahk_id " Button.hwnd)
}

check(forced := false) {
    global lastMinutes
    remaining := GetRemainingMinutes()
    specialText := ""

    ; Si erreur lors de la récupération, on ne fait rien
    if (remaining = "error") {
        return
    }
    ; Cas Chrono
    if (InStr(remaining, "chrono:")) {
        if (forced){
            used := SubStr(remaining, 8)
            TrayTip("Mode Chrono : " humanDuration(used, " comptée"), "Limithor", 1)
        }
        return
    }
    ; Cas temps écoulé
    if (remaining <= 0) {
        TrayTip("Temps écoulé. Déconnexion imminente !", "Limithor", 2)
        return
    }
    ; Cas < 5 minutes : avertir mais seulement si la minute a changé
    if (remaining <= 5) {
        if (remaining != lastMinutes) {
            lastMinutes := remaining
            specialText := "avant déconnexion. Sauvegardez votre travail..."
        }
    }

    ; Affichage du temps restant seulement sur demande au-dessus de 5 minutes
    if (forced || specialText != "") {
        TrayTip(humanDuration(remaining) " " specialText, "Limithor", 1)
    }
}

GetRemainingMinutes(forDisplay := false) {
    configFile := A_ScriptDir "\config.json"
    if FileExist(configFile) {
        content := FileRead(configFile, "UTF-8")
        try {
            jsonObj := JSON.parse(content)
        }
        catch {
            response := MsgBox("Erreur lors de l'analyse du fichier de configuration :`n`n" content "`n`nFermer le programme ?",
                "Limithor", "YesNo Icon!")
            if (response = "Yes")
                ExitApp
            return "error"
        }
        user := A_UserName
        if jsonObj.Has("users") && jsonObj["users"].Has(user) {
            userData := jsonObj["users"][user]
            userConfig := userData.Has("config") ? userData["config"] : {}
            duration := userConfig.Has("limitDuration") ? userConfig["limitDuration"] : 0
            userState := userData.Has("state") ? userData["state"] : {}
            used := userState.Has("usedDuration") ? userState["usedDuration"] : 0
            enabled := userConfig.Has("enabled") ? userConfig["enabled"] : false

            ; Vérifie que l'utilisateur est activé
            if (!enabled) {
                if (forDisplay) {
                    MsgBox("L'Utilisateur < " user " > `nn'a pas de limite activée.", "Limithor", "Iconi")
                }
                return "error"
            }

            if (used = "")
                used := 0

            if (duration == 0) {
                remaining := "chrono:" used
            } else {
                remaining := duration - used
            }

            if (forDisplay) {
                Username.Text := user
                limitType := userConfig.Has("limitType") ? userConfig["limitType"] : "Inconnu"
                limitTypeH := (limitType = "daily") ? "Cycle Quotidien" : (limitType = "weekly") ? "Cycle Hebdomadaire" :
                    limitType
                PeriodType.Text := limitTypeH
                if (duration == 0) {
                    Quota.Text := "Mode Chrono"
                    RemainingDuration.Text := humanDuration(used, " comptée")
                    borderProgress.Visible := false
                    progressBar.Visible := false
                } else {
                    Quota.Text := humanDuration(duration, "")
                    RemainingDuration.Text := humanDuration(remaining)
                    progressBar.Value := (remaining / duration) * 100
                }
                UserGUI.Show()
            }
            return remaining
        } else {
            response := MsgBox("Utilisateur < " user " >`nnon trouvé dans la configuration.`n`nFermer le programme ?",
                "Limithor", "YesNo Iconi")
            if (response = "Yes")
                ExitApp
            return "error"
        }
    } else {
        response := MsgBox("Fichier de configuration introuvable : " configFile "`n`nFermer le programme ?", "Limithor",
            "YesNo Icon!")
        if (response = "Yes")
            ExitApp
        return "error"
    }
}

humanDuration(minutes, postfix := " restante") {
    if (minutes < 60) {
        return minutes " minute" (minutes > 1 ? "s" : "") postfix (minutes > 1 && postfix != "" ? "s" : "")
    }

    hours := Floor(minutes / 60)
    mins := Mod(minutes, 60)

    if (mins = 0) {
        return hours " heure" (hours > 1 ? "s" : "") postfix (hours > 1 && postfix != "" ? "s" : "")
    }

    return hours "h" (mins < 10 ? "0" : "") mins postfix "s"
}

OnTrayClick(wParam, lParam, msg, hwnd) {
    if (hwnd != A_ScriptHwnd || lParam == 512) ; Survol de l'icône ou pas le bon hwnd
        return
    if (lParam == 0x201) { ; Clic gauche up
        SetTimer checkFromTray, -400 ;
        return 1
    } else if (lParam == 0x203) { ; Double clic gauche
        SetTimer checkFromTray, 0 ; Annule le Timer du simple clic
        displayConfig()
        return 1
    } else if (lParam == 0x205) { ; clic droit up
        trayMenu.Show()
        return 1
    } else if (lParam == 1029) { ; clic sur notification
        displayConfig()
        return 1
    }
    return 0
}

runConfig(*) {
    Run(A_ScriptDir "\Config.exe")
}

; ########  ##     ## ##    ##
; ##     ## ##     ## ###   ##
; ##     ## ##     ## ####  ##
; ########  ##     ## ## ## ##
; ##   ##   ##     ## ##  ####
; ##    ##  ##     ## ##   ###
; ##     ##  #######  ##    ##

SetTimer check, 50000  ; toutes les 60s
