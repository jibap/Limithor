<p align="center"><img src="https://github.com/jibap/Limithor/blob/25.12.05/Limithor_exe.png"/></p>

# Limithor
Outil Windows de gestion du temps des sessions utilisateurs. Permet de définir et appliquer des quotas d’utilisation hebdomadaires ou quotidiens.

## Projet
J'ai cherché en vain une petite appli facile à mettre en oeuvre qui permettrait sous Windows de paramétrer un temps de session qui déconnecte automatiquement l'utilisateur, il existe beaucoup de logiciels mais aucun gratuit qui permette efficacement de le faire et surtout aucun qui propose un quota à la semaine ou qui ne déconnecte pas mais historise seulement... \
\
Je l'ai donc crée en **2017** avec **AutoHotKey** via un compteur incrémenté en base de données mais très vite mes enfants ont compris qu'il suffisait d'arrêter le processus lancé au démarrage de la session pour ne plus décompter... 😟\
\
En **2025**, je m'y suis remis pour mes derniers enfants, cette fois c'est une version inviolable basé sur un service Windows (avec .net) qui nécessite les droits admin pour être stoppé, modifié ou supprimé. 👍 

## AutoHotkey / innoSetup / .net (C#)
Le logiciel est composé :
* d'un **installer** ([innoSetup](https://jrsoftware.org/ishelp/index.php)) qui gère aussi la mise à jour et la désinstallation (cette partie n'est pas incluse au dépôt puisque le processus de mise à jour se base sur les releases de la version compilée)
* les **interfaces** de configuration ([Config.ahk](https://github.com/jibap/Limithor/blob/main/Config.ahk)) et de suivi utilisateur ([Tray.ahk](https://github.com/jibap/Limithor/blob/main/README.md)) sont en [AutoHotKey v2](https://www.autohotkey.com/download/ahk-v2.exe)
* le **moteur de décompte** est un [service écrit en .net](https://github.com/jibap/Limithor/tree/main/Service) (C#). Ce dernier génère la config par défaut et le log (si activé). Le dotnet-runtime-9 sera proposé à l'installation si non présent.

Dans ce dépôt vous trouverez les sources nécessaires pour recréer le logiciel par vous-même si vous ne souhaitez pas télécharger la version compilée. 
⚠️Le téléchargement peut-être détecté comme un logiciel malveillant selon votre niveau de protection... pb connu sous AHK, malheureusement !

## Mise en œuvre
Il suffit de télécharger le [fichier d'installation](https://github.com/jibap/Limithor/releases/latest) de ce dépôt et avoir les droits admin sur Windows.

Ensuite tout est guidé. **Il est possible de n'activer qu'un chrono sans quota pour simplement compter le temps de session.** 

Pour la version compilée, le fait d'aller dans le configurateur suffit à détecter une nouvelle version. 

![Limithor_screenshots](https://github.com/user-attachments/assets/31761e14-eebb-4496-87e5-0447859235ab)
