#SingleInstance Force
; =========================================
; Elevation auto (admin requis)
; =========================================
if !A_IsAdmin {
    try Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"'
    ExitApp
}

; Vérifie si Limithor est déjà installé

InstallDir := "C:\Program Files\Limithor"
installed := DirExist(InstallDir)
ServiceName := "Limithor"

if !installed {

    ; Demande de confirmation à l'utilisateur
    response := MsgBox("Limithor n'est pas installé. `n`nLancer l'installation ?", "Limithor", "YesNo Iconi")
    if response != "Yes" {
        ExitApp
    }

    ; =========================================
    ; GUI Installation
    ; =========================================
    myGui := Gui("+AlwaysOnTop", "Installation de Limithor")
    myGui.SetFont("s10", "Segoe UI")

    history := myGui.Add("Edit", "w300 h100 ReadOnly -VScroll", "")
    
    progress := myGui.Add("Progress", "w300 h20 -Smooth Range0-20", 0)
    
    btnClose := myGui.Add("Button", "w300 h55 Disabled", "Fermer")
    btnClose.OnEvent("Click", (*) => ExitApp())
    
    myGui.Show("w330 h200")
    
    Sleep 500
    
    history.Value := "Copie des fichiers..."

    ; =========================================
    ; Étape 1 : copie des fichiers
    ; =========================================
    try {
        DirCreate(InstallDir)
        FileInstall("LimithorTray.exe", InstallDir "\LimithorTray.exe", 1)
        FileInstall("LimithorService.exe", InstallDir "\LimithorService.exe", 1)
        FileInstall("config.json", InstallDir "\config.json", 1)
        history.Value .= "✅ `r`n"
    } catch {
        MsgBox("❌ Échec : Erreur lors de la copie des fichiers.", "Limithor", "Iconx")
        ExitApp
    }

    Sleep 1000
    progress.Value := 5

    ; =========================================
    ; Étape 2 : création du service
    ; =========================================
    history.Value .= "Ajout du service Windows... "
    RunWait('sc create ' ServiceName ' binPath= "' InstallDir '\LimithorService.exe" start= auto obj= LocalSystem', , "Hide")
    Sleep 1000
    ; Ajout de la description
    RunWait('sc.exe description ' ServiceName ' "Gestion du temps de session"', , "Hide")
    progress.Value := 10
    Sleep 1000
    history.Value .= "✅ `r`n"
    Sleep 1000

    ; =========================================
    ; Étape 3 : démarrage du service + barre de progression
    ; =========================================
    history.Value .= "Démarrage du service... "
    RunWait('sc start ' ServiceName, , "Hide")
    
    startTime := A_TickCount
    loops := 0
    Loop {
        loops++
        progress.Value := 10 + loops

        ; Recupère le statut du service
        objShell := ComObject("WScript.Shell")
        objExec := objShell.Exec("sc query " ServiceName)
        cmdResult := objExec.StdOut.ReadAll()

        if InStr(cmdResult, "RUNNING") {
            history.Value .= "✅ `r`n"
            Sleep 1000
            history.Value .= "Installation terminée ! `r`n"
            progress.Value := 20
            btnClose.Enabled := true
            return
        }

        if (A_TickCount - startTime > 20000) {
            history.Value .= "❌ Échec : le service ne démarre pas.`r`n"
            btnClose.Enabled := true
            return
        }
        Sleep 1000
    }

    ; Empêche la fermeture auto
    return

} else {
    msgResponse := MsgBox("Limithor est déjà installé. `n`nVoulez-vous le dés/ré installer ?", "Limithor", "YesNo Iconi")
    if (msgResponse = "Yes") {
        ; =========================================
        ; GUI Désinstallation
        ; =========================================
        myGui := Gui("+AlwaysOnTop", "Désinstallation de Limithor")
        myGui.SetFont("s10", "Segoe UI")

        history := myGui.Add("Edit", "w300 h80 ReadOnly -VScroll", "")
        progress := myGui.Add("Progress", "w300 h20 -Smooth Range0-20", 0)
        status := myGui.Add("Text", "w300 h40", "")
        myGui.Show("w330 h120")

        Sleep 1000

        ; Arrête le service
        history.Value .= "Arrêt du service..."
        RunWait('sc stop ' ServiceName, , "Hide")
        objShell := ComObject("WScript.Shell")
        Loop {
            objExec := objShell.Exec("sc query " ServiceName)
            cmdResult := objExec.StdOut.ReadAll()
            if InStr(cmdResult, "STOPPED") {
                break
            }
            progress.Value += 1
            Sleep 1000
        }
        progress.Value := 5

        Sleep 1000
        history.Value .= " ✅`r`n"
        Sleep 1000

        ; Supprime le service
        history.Value .= "Suppression du service..."
        RunWait('sc delete ' ServiceName, , "Hide")
        loop {
            objExec := objShell.Exec("sc query " ServiceName)
            cmdResult := objExec.StdOut.ReadAll()
            if !InStr(cmdResult, "SERVICE_NAME") {
                break
            }
            progress.Value += 1
            Sleep 1000
        }
        progress.Value := 10

        Sleep 1000
        history.Value .= " ✅`r`n"
        Sleep 1000

        ; Supprime les fichiers
        history.Value .= "Suppression des fichiers..."
        DirDelete(InstallDir, true)
        progress.Value := 15

        Sleep 1000
        history.Value .= " ✅`r`n"
        Sleep 1000


        progress.Value := 20

        ; Relance pour réinstallation
        history.Value .= "Relance de l’installation..."
        Sleep 2000
        Run('"' A_ScriptFullPath '"', , "Hide")
    }
}

ExitApp
