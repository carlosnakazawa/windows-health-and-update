# Windows Health & Update

[![CI](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml/badge.svg)](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml)
[![Licence : MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](../LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Windows 10 | 11 | Server](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4)

[English](../README.md) | [Português (Brasil)](README.pt-BR.md) | [Español](README.es.md) | **Français** | [Deutsch](README.de.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-CN.md)

> Cette traduction peut être en retard sur la [version anglaise](../README.md), qui fait référence.

Script de maintenance PowerShell qui garde un PC Windows à jour et en bonne santé en une seule commande : mise à jour des applications, Windows Update, Microsoft Defender, réparation des fichiers système, nettoyage et état des disques.

Il **détecte la version exacte de Windows** (par exemple *Windows 11 Pro 25H2*, *Windows 10 Entreprise LTSC 2021* ou *Windows Server 2022*), indique **si cette version reçoit encore des mises à jour de sécurité** et **adapte chaque étape** en conséquence.

## Fonctionnalités

| Étape | Rôle |
| --- | --- |
| `RestorePoint` | Crée un point de restauration avant toute modification. |
| `WinGet` | Met à jour silencieusement les applications installées avec `winget`. Trouve winget même s'il n'est pas dans le `PATH` (compte SYSTEM ou autre administrateur). |
| `Store` | Déclenche la recherche de mises à jour des applications du Microsoft Store. |
| `WindowsUpdate` | Recherche, télécharge et **installe** les mises à jour via l'API Windows Update Agent. Les pilotes et les mises à jour de fonctionnalités sont facultatifs. |
| `Defender` | Met à jour les signatures de Microsoft Defender et lance une analyse rapide. Ignorée si un autre antivirus est actif. |
| `Repair` | `DISM /RestoreHealth` puis `sfc /scannow`. |
| `Cleanup` | `DISM /StartComponentCleanup`, fichiers temporaires de plus de N jours pour tous les profils locaux et cache de l'Optimisation de livraison. Indique l'espace libéré. |
| `DiskHealth` | État, température, usure et erreurs de lecture des disques, ainsi que l'espace libre de chaque volume. |
| `UpgradeReadiness` | Windows 10 uniquement : vérifie TPM 2.0, UEFI/Démarrage sécurisé, mémoire, stockage et les exigences de base du processeur pour Windows 11. |

Le script également :

- détecte un **redémarrage en attente** avant et après l'exécution et peut redémarrer automatiquement (`-AutoReboot`) ;
- isole chaque étape : un échec est consigné et l'étape suivante s'exécute quand même ;
- enregistre une **transcription** et un **rapport JSON** dans `%ProgramData%\WindowsHealthAndUpdate\Logs`, avec rétention ;
- prend en charge `-WhatIf` et `-Confirm` ;
- renvoie des codes de sortie compris par les outils d'automatisation : `0` succès, `1` échec, `3010` redémarrage nécessaire.

## Versions de Windows prises en charge

Le script détecte le système sur lequel il tourne et s'adapte. Les étapes marquées « n/a » sont ignorées avec une explication.

| Étape | Windows 11 Famille/Pro | Windows 11 Entreprise/Éducation | Windows 10 22H2 | Windows 10/11 LTSC | Windows Server 2016-2025 |
| --- | :---: | :---: | :---: | :---: | :---: |
| État du support | oui | oui | oui (note ESU) | oui | oui |
| RestorePoint | oui | oui | oui | oui | n/a |
| WinGet | oui | oui | oui ¹ | si installé ¹ | si installé ¹ |
| Store | oui | oui | oui | n/a | n/a |
| WindowsUpdate | oui | oui | oui | oui | oui |
| Defender | oui ² | oui ² | oui ² | oui ² | oui ² |
| Repair / Cleanup / DiskHealth | oui | oui | oui | oui | oui |
| UpgradeReadiness | n/a | n/a | oui | n/a | n/a |

¹ Nécessite le [Programme d'installation d'application](https://aka.ms/getwinget). S'il est absent, l'étape est ignorée.
² Uniquement lorsque Microsoft Defender est l'antivirus actif.

### État du support

Les dates de fin de support proviennent des pages [Windows release health](https://learn.microsoft.com/windows/release-health/) de Microsoft (vérifiées en novembre 2026). À cette date :

| Version | Build | Famille/Pro | Entreprise/Éducation |
| --- | --- | --- | --- |
| Windows 11 26H2 | 26300 | 10/10/2028 | 09/10/2029 |
| Windows 11 26H1 (nouveaux appareils uniquement) | 28000 | 14/03/2028 | 13/03/2029 |
| Windows 11 25H2 | 26200 | 12/10/2027 | 10/10/2028 |
| Windows 11 24H2 | 26100 | **terminé le 13/10/2026** | 12/10/2027 |
| Windows 11 23H2 et antérieures | 22631- | terminé | terminé |
| Windows 10 22H2 | 19045 | **terminé le 14/10/2025** (ESU uniquement) | terminé (ESU uniquement) |

Les versions LTSC et Windows Server sont également couvertes. La table complète se trouve dans la fonction `Get-WindowsLifecycleData` du script.

### Comment la version est détectée

La valeur de registre `ProductName` indique toujours **« Windows 10 »** sous Windows 11 : le script ne s'y fie donc pas. Il lit `CurrentBuild`, `UBR`, `DisplayVersion`, `EditionID` et `InstallationType` dans `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` et en déduit :

- la **famille** : Windows Server lorsque `InstallationType` vaut `Server`/`Server Core`, Windows 11 à partir du build 22000, sinon Windows 10 ;
- le **canal de maintenance** : Famille/Pro (24 mois), Entreprise/Éducation (36 mois), LTSC, IoT LTSC ou Server. C'est lui qui détermine la date de fin applicable. Par exemple, le build 26100 peut être Windows 11 24H2, Windows 11 LTSC 2024 *ou* Windows Server 2025, chacun avec une date différente.

## Prérequis

- Windows 10, Windows 11 ou Windows Server 2016+
- Windows PowerShell 5.1 (intégré à Windows) ou PowerShell 7+
- Une session élevée (Exécuter en tant qu'administrateur)

## Démarrage rapide

1. Téléchargez ou clonez le dépôt, par exemple dans `C:\Program Files\WindowsHealthAndUpdate`.
2. Ouvrez **Windows Terminal** ou **PowerShell** en tant qu'**administrateur**.
3. Lancez le script. `-ExecutionPolicy Bypass` ne s'applique qu'à ce processus et ne modifie aucun paramètre du système :

   ```powershell
   cd 'C:\Program Files\WindowsHealthAndUpdate'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WindowsMaintenance.ps1
   ```

   Si vous avez téléchargé le ZIP, vous pouvez d'abord débloquer les fichiers avec `Get-ChildItem -Recurse | Unblock-File`.

Pour voir ce qui serait fait, sans rien modifier :

```powershell
.\Invoke-WindowsMaintenance.ps1 -WhatIf
```

## Utilisation

```powershell
# Tout ce qui s'applique à ce PC
.\Invoke-WindowsMaintenance.ps1

# Passe rapide : sans DISM/SFC ni analyse Defender
.\Invoke-WindowsMaintenance.ps1 -Skip Repair, Defender

# Mises à jour uniquement, puis redémarrage si nécessaire
.\Invoke-WindowsMaintenance.ps1 -Only WinGet, WindowsUpdate -AutoReboot

# Inclure les pilotes et passer à la dernière version de Windows 11
.\Invoke-WindowsMaintenance.ps1 -IncludeDrivers -IncludeFeatureUpdates

# Enregistrer les journaux sur le Bureau
.\Invoke-WindowsMaintenance.ps1 -LogDirectory ([Environment]::GetFolderPath('Desktop'))

# Aide complète
Get-Help .\Invoke-WindowsMaintenance.ps1 -Detailed
```

| Paramètre | Valeur par défaut | Description |
| --- | --- | --- |
| `-Skip` | aucune | Étapes à ignorer. |
| `-Only` | toutes | N'exécute que ces étapes. |
| `-IncludeDrivers` | désactivé | Installe aussi les pilotes proposés par Windows Update. |
| `-IncludeFeatureUpdates` | désactivé | Installe aussi les mises à jour de fonctionnalités (par exemple de 24H2 vers 25H2). |
| `-AutoReboot` | désactivé | Redémarre 2 minutes après la fin si nécessaire (`shutdown /a` annule). |
| `-TempFileAgeDays` | `2` | Ne supprime que les fichiers temporaires plus anciens que cette durée. |
| `-LogDirectory` | `%ProgramData%\WindowsHealthAndUpdate\Logs` | Emplacement des transcriptions et des rapports JSON. |
| `-LogRetentionDays` | `30` | Supprime les journaux et rapports plus anciens. |
| `-WhatIf` / `-Confirm` | | Simule l'exécution ou demande une confirmation à chaque étape. |

## Planification

`Register-MaintenanceTask.ps1` crée une tâche dans le Planificateur de tâches qui s'exécute avec votre compte, en mode élevé, uniquement lorsque vous êtes connecté : aucun mot de passe n'est stocké. Si le PC était éteint à l'heure prévue, la tâche s'exécute dès que possible.

```powershell
# Chaque dimanche à 10:00 (par défaut)
.\Register-MaintenanceTask.ps1

# Tous les jours à 12:30, mises à jour uniquement
.\Register-MaintenanceTask.ps1 -Frequency Daily -At 12:30 -MaintenanceArguments '-Only WinGet, WindowsUpdate'

# Supprimer la tâche
.\Register-MaintenanceTask.ps1 -Unregister
```

> **Sécurité :** la tâche exécute le script avec des droits d'administrateur. Placez-le dans un dossier que les utilisateurs standard ne peuvent pas modifier (comme `C:\Program Files\...`). Sinon, n'importe quel processus lancé avec votre compte pourrait modifier le script et obtenir une élévation. Le script d'enregistrement vous avertit si le fichier se trouve dans votre profil utilisateur.

## Journaux et rapport

Chaque exécution crée deux fichiers dans le dossier des journaux :

- `maintenance_<horodatage>.log` : transcription PowerShell ;
- `maintenance_<horodatage>.json` : rapport structuré avec les informations système, l'état du support, le résultat de chaque étape, le besoin de redémarrage et le code de sortie. Vous pouvez le collecter sur plusieurs machines ou l'envoyer à un outil de supervision.

DISM et SFC conservent leurs propres journaux détaillés dans `%windir%\Logs\DISM\dism.log` et `%windir%\Logs\CBS\CBS.log`.

## Ce que le script ne fait pas

- Aucune « optimisation » du registre, suppression d'applications, modification de la télémétrie ou des services.
- Pas de `DISM /ResetBase` : les mises à jour installées restent désinstallables.
- Aucune suppression de fichiers utilisateur, du dossier Téléchargements ou de la Corbeille. Seuls les dossiers temporaires sont nettoyés, et uniquement les fichiers plus anciens que `-TempFileAgeDays`.
- Aucune donnée envoyée nulle part.

## Développement

```powershell
# Tests unitaires (Pester 5+)
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed

# Analyse statique
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Le workflow CI exécute l'analyseur, les tests unitaires et un test de fumée avec `-WhatIf` sur **Windows Server 2022 et 2025**, avec **Windows PowerShell 5.1 et PowerShell 7**.

Les scripts restent **uniquement en ASCII** volontairement : Windows PowerShell 5.1 lit les fichiers sans BOM avec la page de codes ANSI, et les caractères accentués casseraient le script. Un test le garantit.

## Contribuer

Les commentaires, rapports de bugs et traductions sont les bienvenus, dans la langue de votre choix. Voir [CONTRIBUTING.md](../CONTRIBUTING.md).

## Feuille de route

- Notification facultative par e-mail, Teams ou webhook avec le rapport JSON.
- Liste des processeurs compatibles pour la vérification de préparation à Windows 11.
- Publication sur la PowerShell Gallery.

## Licence

[MIT](../LICENSE) © Carlos Alberto Nakazawa
