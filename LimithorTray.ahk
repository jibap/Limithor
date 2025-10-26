#SingleInstance Force
#Include <JSON>  ; Inclure la bibliothèque JSON

Persistent
OnExit(ExitAppli)

InstallDir := "C:\Program Files\Limithor"

notified := false

; CREATION DU TRAYMENU
; *********************
trayMenu := A_TrayMenu
trayMenu.Delete() ; Supprime les menus par défaut
trayMenu.add("Quitter", ExitAppli)
trayMenu.add()
trayMenu.add("Afficher le profil", displayConfig)
trayMenu.add("Afficher le temps restant", forceCheck)
trayMenu.Default := "4&"


ExitAppli(*) {
    ExitApp
}

forceCheck(*) {
    check(true)
}

displayConfig(*){
    GetRemainingMinutes(true)
}

check(forced := false) {
    global notified
    remaining := GetRemainingMinutes()
    
    if(remaining <= 0) {
        TrayTip("Temps écoulé. Déconnexion imminente !", "Limithor", 2)
        return
    }
    if ((!notified || forced) && remaining <= 5) {
        TrayTip("Il reste " remaining " minute(s) avant déconnexion. Sauvegardez votre travail...", "Limithor", 2)
        notified := true
        return
    }
    ; Affichage du temps restant seulement sur demande au-dessus de 5 minutes
    if(forced){
        TrayTip(humanDuration(remaining) " restantes", "Limithor", 1)
    }
}

GetRemainingMinutes(forDisplay := false) {
    configFile := InstallDir "\config.json"
    if FileExist(configFile) {
        content := FileRead(configFile, "UTF-8")
        jsonObj := JSON.parse(content)
        user := StrLower(A_UserName)
        ; Récupérer le nom d'utilisateur en minuscules
        if jsonObj.Has("users") && jsonObj["users"].Has(user) {
            userData := jsonObj["users"][user]
            userConfig := userData.Has("config") ? userData["config"] : {}
            duration := userConfig.Has("limitDuration") ? userConfig["limitDuration"] : 0
            userState := userData.Has("state") ? userData["state"] : {}
            used := userState.Has("usedDuration") ? userState["usedDuration"] : 0
            if (used = "")
                used := 0
            
            remaining := duration - used
            if(forDisplay) {
                limitType := userConfig.Has("limitType") ? userConfig["limitType"] : "Inconnu"
                limitTypeH := (limitType = "daily") ? "quotidien" : (limitType = "weekly") ? "hebdomadaire" : limitType
                durationH := humanDuration(duration) 
                usedH := humanDuration(used) 
                remainingH := humanDuration(remaining) 
                MsgBox("Utilisateur <" user "> :`nType de quota : " limitTypeH "`nQuota : " durationH "`nUtilisé : " usedH "`nRestant : " remainingH , "Limithor", "Iconi")
            }
            return remaining
        } else {
            response := MsgBox("Utilisateur <" user "> non trouvé dans la configuration.`nFermer le programme ?",
            "Limithor", "YesNo Iconi")
            if (response = "Yes")
                ExitApp
        }
    } else {
        MsgBox("Fichier de configuration introuvable : " configFile "`nFermeture du programme...", "Limithor", "Iconx")
        ExitApp
    }
} 

humanDuration(minutes) {
    if (minutes < 60) {
        return minutes " minute" (minutes > 1 ? "s" : "")
    }
    
    hours := Floor(minutes / 60)
    mins := Mod(minutes, 60)
    
    if (mins = 0) {
        return hours " heure" (hours > 1 ? "s" : "")
    }
    
    return hours " heure" (hours > 1 ? "s" : "") " et " mins " minute" (mins > 1 ? "s" : "")
}


SetTimer check, 60000  ; toutes les 60s