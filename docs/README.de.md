# Windows Health & Update

[![CI](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml/badge.svg)](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml)
[![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-blue.svg)](../LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Windows 10 | 11 | Server](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4)

[English](../README.md) | [Português (Brasil)](README.pt-BR.md) | [Español](README.es.md) | [Français](README.fr.md) | **Deutsch** | [Italiano](README.it.md) | [Русский](README.ru.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-CN.md)

> Diese Übersetzung kann hinter der [englischen Version](../README.md) zurückliegen, die maßgeblich ist.

Ein PowerShell-Wartungsskript, das einen Windows-PC mit einem einzigen Befehl aktuell und in gutem Zustand hält: App-Updates, Windows Update, Microsoft Defender, Reparatur der Systemdateien, Bereinigung und Datenträgerzustand.

Es **erkennt die genaue Windows-Version** (zum Beispiel *Windows 11 Pro 25H2*, *Windows 10 Enterprise LTSC 2021* oder *Windows Server 2022*), zeigt an, **ob diese Version noch Sicherheitsupdates erhält**, und **passt jeden Schritt** daran an.

## Funktionen

| Schritt | Was er macht |
| --- | --- |
| `RestorePoint` | Erstellt vor jeder Änderung einen Wiederherstellungspunkt. |
| `WinGet` | Aktualisiert installierte Anwendungen still mit `winget`. Findet winget auch, wenn es nicht im `PATH` liegt (SYSTEM-Konto oder ein anderer Administrator). |
| `Store` | Startet die Updatesuche für Apps aus dem Microsoft Store. |
| `WindowsUpdate` | Sucht, lädt und **installiert** Updates über die Windows Update Agent API. Treiber und Funktionsupdates sind optional. |
| `Defender` | Aktualisiert die Signaturen von Microsoft Defender und führt eine Schnellüberprüfung aus. Wird übersprungen, wenn ein anderes Antivirenprogramm aktiv ist. |
| `Repair` | `DISM /RestoreHealth`, danach `sfc /scannow`. |
| `Cleanup` | `DISM /StartComponentCleanup`, temporäre Dateien älter als N Tage in allen lokalen Profilen und der Cache der Übermittlungsoptimierung. Meldet den freigegebenen Speicherplatz. |
| `DiskHealth` | Zustand, Temperatur, Verschleiß und Lesefehler der Datenträger sowie der freie Speicher jedes Volumes. |
| `UpgradeReadiness` | Nur Windows 10: prüft TPM 2.0, UEFI/Secure Boot, Arbeitsspeicher, Speicherplatz und die grundlegenden CPU-Anforderungen für Windows 11. |

Außerdem:

- erkennt das Skript einen **ausstehenden Neustart** vor und nach der Ausführung und kann automatisch neu starten (`-AutoReboot`);
- ist jeder Schritt isoliert: Ein Fehler wird protokolliert, und der nächste Schritt läuft trotzdem;
- werden ein **Transkript** und ein **JSON-Bericht** in `%ProgramData%\WindowsHealthAndUpdate\Logs` gespeichert, mit Aufbewahrungsfrist;
- werden `-WhatIf` und `-Confirm` unterstützt;
- liefert das Skript Exitcodes, die Automatisierungswerkzeuge verstehen: `0` Erfolg, `1` Fehler, `3010` Neustart erforderlich.

## Unterstützte Windows-Versionen

Das Skript erkennt, auf welchem System es läuft, und passt sich an. Mit „n/a" markierte Schritte werden mit einer Begründung übersprungen.

| Schritt | Windows 11 Home/Pro | Windows 11 Enterprise/Education | Windows 10 22H2 | Windows 10/11 LTSC | Windows Server 2016-2025 |
| --- | :---: | :---: | :---: | :---: | :---: |
| Supportstatus | ja | ja | ja (ESU-Hinweis) | ja | ja |
| RestorePoint | ja | ja | ja | ja | n/a |
| WinGet | ja | ja | ja ¹ | falls installiert ¹ | falls installiert ¹ |
| Store | ja | ja | ja | n/a | n/a |
| WindowsUpdate | ja | ja | ja | ja | ja |
| Defender | ja ² | ja ² | ja ² | ja ² | ja ² |
| Repair / Cleanup / DiskHealth | ja | ja | ja | ja | ja |
| UpgradeReadiness | n/a | n/a | ja | n/a | n/a |

¹ Erfordert den [App-Installer](https://aka.ms/getwinget). Fehlt er, wird der Schritt übersprungen.
² Nur wenn Microsoft Defender das aktive Antivirenprogramm ist.

### Supportstatus

Die Enddaten stammen aus Microsofts [Windows release health](https://learn.microsoft.com/windows/release-health/)-Seiten (geprüft im November 2026). Stand zu diesem Zeitpunkt:

| Version | Build | Home/Pro | Enterprise/Education |
| --- | --- | --- | --- |
| Windows 11 26H2 | 26300 | 10.10.2028 | 09.10.2029 |
| Windows 11 26H1 (nur neue Geräte) | 28000 | 14.03.2028 | 13.03.2029 |
| Windows 11 25H2 | 26200 | 12.10.2027 | 10.10.2028 |
| Windows 11 24H2 | 26100 | **beendet am 13.10.2026** | 12.10.2027 |
| Windows 11 23H2 und älter | 22631- | beendet | beendet |
| Windows 10 22H2 | 19045 | **beendet am 14.10.2025** (nur ESU) | beendet (nur ESU) |

LTSC- und Windows-Server-Versionen sind ebenfalls abgedeckt. Die vollständige Tabelle steht in der Funktion `Get-WindowsLifecycleData` im Skript.

### Wie die Version erkannt wird

Der Registrierungswert `ProductName` lautet unter Windows 11 weiterhin **„Windows 10"**, deshalb verlässt sich das Skript nicht darauf. Es liest `CurrentBuild`, `UBR`, `DisplayVersion`, `EditionID` und `InstallationType` aus `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` und leitet daraus ab:

- die **Produktfamilie**: Windows Server, wenn `InstallationType` den Wert `Server`/`Server Core` hat, Windows 11 ab Build 22000, sonst Windows 10;
- den **Wartungskanal**: Home/Pro (24 Monate), Enterprise/Education (36 Monate), LTSC, IoT LTSC oder Server. Er bestimmt, welches Enddatum gilt. Build 26100 kann zum Beispiel Windows 11 24H2, Windows 11 LTSC 2024 *oder* Windows Server 2025 sein, jeweils mit einem anderen Datum.

## Voraussetzungen

- Windows 10, Windows 11 oder Windows Server 2016+
- Windows PowerShell 5.1 (in Windows enthalten) oder PowerShell 7+
- Eine Sitzung mit erhöhten Rechten (Als Administrator ausführen)

## Schnellstart

1. Laden Sie das Repository herunter oder klonen Sie es, zum Beispiel nach `C:\Program Files\WindowsHealthAndUpdate`.
2. Öffnen Sie **Windows Terminal** oder **PowerShell** als **Administrator**.
3. Führen Sie das Skript aus. `-ExecutionPolicy Bypass` gilt nur für diesen Prozess und ändert keine Systemeinstellung:

   ```powershell
   cd 'C:\Program Files\WindowsHealthAndUpdate'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WindowsMaintenance.ps1
   ```

   Wenn Sie das ZIP heruntergeladen haben, können Sie die Dateien vorher mit `Get-ChildItem -Recurse | Unblock-File` entsperren.

Um zu sehen, was passieren würde, ohne etwas zu ändern:

```powershell
.\Invoke-WindowsMaintenance.ps1 -WhatIf
```

## Verwendung

```powershell
# Alles, was für diesen PC gilt
.\Invoke-WindowsMaintenance.ps1

# Schneller Durchlauf: ohne DISM/SFC und ohne Defender-Überprüfung
.\Invoke-WindowsMaintenance.ps1 -Skip Repair, Defender

# Nur Updates, danach bei Bedarf neu starten
.\Invoke-WindowsMaintenance.ps1 -Only WinGet, WindowsUpdate -AutoReboot

# Treiber einschließen und auf die neueste Windows-11-Version wechseln
.\Invoke-WindowsMaintenance.ps1 -IncludeDrivers -IncludeFeatureUpdates

# Protokolle auf dem Desktop speichern
.\Invoke-WindowsMaintenance.ps1 -LogDirectory ([Environment]::GetFolderPath('Desktop'))

# Vollständige Hilfe
Get-Help .\Invoke-WindowsMaintenance.ps1 -Detailed
```

| Parameter | Standard | Beschreibung |
| --- | --- | --- |
| `-Skip` | keine | Zu überspringende Schritte. |
| `-Only` | alle | Führt nur diese Schritte aus. |
| `-IncludeDrivers` | aus | Installiert auch Treiber aus Windows Update. |
| `-IncludeFeatureUpdates` | aus | Installiert auch Funktionsupdates (zum Beispiel von 24H2 auf 25H2). |
| `-AutoReboot` | aus | Startet bei Bedarf 2 Minuten nach dem Ende neu (`shutdown /a` bricht ab). |
| `-TempFileAgeDays` | `2` | Löscht nur temporäre Dateien, die älter sind. |
| `-LogDirectory` | `%ProgramData%\WindowsHealthAndUpdate\Logs` | Speicherort der Transkripte und JSON-Berichte. |
| `-LogRetentionDays` | `30` | Löscht ältere Protokolle und Berichte. |
| `-WhatIf` / `-Confirm` | | Simuliert die Ausführung oder fragt bei jedem Schritt nach. |

## Zeitplanung

`Register-MaintenanceTask.ps1` legt eine Aufgabe in der Aufgabenplanung an, die mit Ihrem Benutzerkonto und erhöhten Rechten läuft, aber nur, solange Sie angemeldet sind. Daher wird kein Kennwort gespeichert. War der PC zum geplanten Zeitpunkt ausgeschaltet, läuft die Aufgabe so bald wie möglich.

```powershell
# Jeden Sonntag um 10:00 (Standard)
.\Register-MaintenanceTask.ps1

# Täglich um 12:30, nur Updates
.\Register-MaintenanceTask.ps1 -Frequency Daily -At 12:30 -MaintenanceArguments '-Only WinGet, WindowsUpdate'

# Aufgabe entfernen
.\Register-MaintenanceTask.ps1 -Unregister
```

> **Sicherheit:** Die Aufgabe führt das Skript mit Administratorrechten aus. Legen Sie es in einem Ordner ab, den Standardbenutzer nicht ändern können (etwa `C:\Program Files\...`). Andernfalls könnte jeder Prozess, der unter Ihrem Konto läuft, das Skript bearbeiten und sich so erhöhte Rechte verschaffen. Das Registrierungsskript warnt, wenn die Datei in Ihrem Benutzerprofil liegt.

## Protokolle und Bericht

Jeder Lauf erzeugt zwei Dateien im Protokollordner:

- `maintenance_<Zeitstempel>.log`: PowerShell-Transkript;
- `maintenance_<Zeitstempel>.json`: strukturierter Bericht mit Systemdaten, Supportstatus, dem Ergebnis jedes Schritts, Neustartbedarf und Exitcode. Sie können ihn von mehreren Rechnern einsammeln oder an ein Monitoring-Werkzeug übergeben.

DISM und SFC führen eigene ausführliche Protokolle in `%windir%\Logs\DISM\dism.log` und `%windir%\Logs\CBS\CBS.log`.

## Was das Skript nicht tut

- Keine Registry-„Tweaks", kein Entfernen von Apps, keine Änderungen an Telemetrie oder Diensten.
- Kein `DISM /ResetBase`: Installierte Updates bleiben deinstallierbar.
- Keine Benutzerdateien, keine Downloads und kein Papierkorb werden gelöscht. Nur temporäre Ordner werden bereinigt, und nur Dateien, die älter als `-TempFileAgeDays` sind.
- Es werden keine Daten irgendwohin gesendet.

## Entwicklung

```powershell
# Unit-Tests (Pester 5+)
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed

# Statische Analyse
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Der CI-Workflow führt den Analyzer, die Unit-Tests und einen Smoke-Test mit `-WhatIf` auf **Windows Server 2022 und 2025** aus, jeweils mit **Windows PowerShell 5.1 und PowerShell 7**.

Die Skripte enthalten bewusst **nur ASCII-Zeichen**: Windows PowerShell 5.1 liest Dateien ohne BOM mit der ANSI-Codepage, und Umlaute würden das Skript beschädigen. Ein Test stellt das sicher.

## Mitmachen

Kommentare, Fehlerberichte und Übersetzungen sind willkommen, gern in Ihrer eigenen Sprache. Siehe [CONTRIBUTING.md](../CONTRIBUTING.md).

## Roadmap

- Optionale Benachrichtigung per E-Mail, Teams oder Webhook mit dem JSON-Bericht.
- Liste kompatibler CPUs für die Windows-11-Bereitschaftsprüfung.
- Veröffentlichung in der PowerShell Gallery.

## Lizenz

[MIT](../LICENSE) © Carlos Alberto Nakazawa
