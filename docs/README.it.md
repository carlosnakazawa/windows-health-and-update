# Windows Health & Update

[![CI](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml/badge.svg)](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml)
[![Licenza: MIT](https://img.shields.io/badge/licenza-MIT-blue.svg)](../LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Windows 10 | 11 | Server](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4)

[English](../README.md) | [Português (Brasil)](README.pt-BR.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | **Italiano** | [Русский](README.ru.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-CN.md)

> Questa traduzione potrebbe non essere aggiornata rispetto alla [versione inglese](../README.md), che fa da riferimento.

Script di manutenzione PowerShell che mantiene un PC Windows aggiornato e in salute con un solo comando: aggiornamento delle applicazioni, Windows Update, Microsoft Defender, riparazione dei file di sistema, pulizia e stato dei dischi.

**Rileva la versione esatta di Windows** (ad esempio *Windows 11 Pro 25H2*, *Windows 10 Enterprise LTSC 2021* o *Windows Server 2022*), indica **se quella versione riceve ancora aggiornamenti di sicurezza** e **adatta ogni passaggio** di conseguenza.

## Funzionalità

| Passaggio | Cosa fa |
| --- | --- |
| `RestorePoint` | Crea un punto di ripristino prima di qualsiasi modifica. |
| `WinGet` | Aggiorna in modo silenzioso le applicazioni installate con `winget`. Trova winget anche se non è nel `PATH` (account SYSTEM o un altro amministratore). |
| `Store` | Avvia la ricerca di aggiornamenti per le app di Microsoft Store. |
| `WindowsUpdate` | Cerca, scarica e **installa** gli aggiornamenti tramite l'API di Windows Update Agent. Driver e aggiornamenti delle funzionalità sono facoltativi. |
| `Defender` | Aggiorna le firme di Microsoft Defender ed esegue un'analisi veloce. Viene saltato se è attivo un altro antivirus. |
| `Repair` | `DISM /RestoreHealth` seguito da `sfc /scannow`. |
| `Cleanup` | `DISM /StartComponentCleanup`, file temporanei più vecchi di N giorni per tutti i profili locali e cache di Ottimizzazione recapito. Riporta lo spazio liberato. |
| `DiskHealth` | Stato, temperatura, usura ed errori di lettura dei dischi, oltre allo spazio libero di ogni volume. |
| `UpgradeReadiness` | Solo Windows 10: verifica TPM 2.0, UEFI/Avvio protetto, memoria, archiviazione e i requisiti di base della CPU per Windows 11. |

Inoltre lo script:

- rileva un **riavvio in sospeso** prima e dopo l'esecuzione e può riavviare automaticamente (`-AutoReboot`);
- isola ogni passaggio: un errore viene registrato e il passaggio successivo viene eseguito comunque;
- salva una **trascrizione** e un **report JSON** in `%ProgramData%\WindowsHealthAndUpdate\Logs`, con conservazione limitata nel tempo;
- supporta `-WhatIf` e `-Confirm`;
- restituisce codici di uscita comprensibili dagli strumenti di automazione: `0` successo, `1` errore, `3010` riavvio necessario.

## Versioni di Windows supportate

Lo script rileva il sistema su cui gira e si adatta. I passaggi indicati con "n/a" vengono saltati con una spiegazione.

| Passaggio | Windows 11 Home/Pro | Windows 11 Enterprise/Education | Windows 10 22H2 | Windows 10/11 LTSC | Windows Server 2016-2025 |
| --- | :---: | :---: | :---: | :---: | :---: |
| Stato del supporto | sì | sì | sì (nota ESU) | sì | sì |
| RestorePoint | sì | sì | sì | sì | n/a |
| WinGet | sì | sì | sì ¹ | se installato ¹ | se installato ¹ |
| Store | sì | sì | sì | n/a | n/a |
| WindowsUpdate | sì | sì | sì | sì | sì |
| Defender | sì ² | sì ² | sì ² | sì ² | sì ² |
| Repair / Cleanup / DiskHealth | sì | sì | sì | sì | sì |
| UpgradeReadiness | n/a | n/a | sì | n/a | n/a |

¹ Richiede il [Programma di installazione app](https://aka.ms/getwinget). Se manca, il passaggio viene saltato.
² Solo quando Microsoft Defender è l'antivirus attivo.

### Stato del supporto

Le date di fine supporto provengono dalle pagine [Windows release health](https://learn.microsoft.com/windows/release-health/) di Microsoft (verificate a novembre 2026). A quella data:

| Versione | Build | Home/Pro | Enterprise/Education |
| --- | --- | --- | --- |
| Windows 11 26H2 | 26300 | 10/10/2028 | 09/10/2029 |
| Windows 11 26H1 (solo nuovi dispositivi) | 28000 | 14/03/2028 | 13/03/2029 |
| Windows 11 25H2 | 26200 | 12/10/2027 | 10/10/2028 |
| Windows 11 24H2 | 26100 | **terminato il 13/10/2026** | 12/10/2027 |
| Windows 11 23H2 e precedenti | 22631- | terminato | terminato |
| Windows 10 22H2 | 19045 | **terminato il 14/10/2025** (solo ESU) | terminato (solo ESU) |

Sono coperte anche le versioni LTSC e Windows Server. La tabella completa si trova nella funzione `Get-WindowsLifecycleData` dello script.

### Come viene rilevata la versione

Il valore di registro `ProductName` riporta ancora **"Windows 10"** su Windows 11, quindi lo script non si basa su di esso. Legge `CurrentBuild`, `UBR`, `DisplayVersion`, `EditionID` e `InstallationType` da `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` e ricava:

- la **famiglia**: Windows Server quando `InstallationType` è `Server`/`Server Core`, Windows 11 dalla build 22000, altrimenti Windows 10;
- il **canale di manutenzione**: Home/Pro (24 mesi), Enterprise/Education (36 mesi), LTSC, IoT LTSC o Server. È questo a stabilire quale data di fine si applica. Ad esempio la build 26100 può essere Windows 11 24H2, Windows 11 LTSC 2024 *oppure* Windows Server 2025, ognuno con una data diversa.

## Requisiti

- Windows 10, Windows 11 o Windows Server 2016+
- Windows PowerShell 5.1 (incluso in Windows) o PowerShell 7+
- Una sessione con privilegi elevati (Esegui come amministratore)

## Avvio rapido

1. Scarica o clona il repository, ad esempio in `C:\Program Files\WindowsHealthAndUpdate`.
2. Apri **Windows Terminal** o **PowerShell** come **amministratore**.
3. Esegui lo script. `-ExecutionPolicy Bypass` vale solo per questo processo e non modifica alcuna impostazione di sistema:

   ```powershell
   cd 'C:\Program Files\WindowsHealthAndUpdate'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WindowsMaintenance.ps1
   ```

   Se hai scaricato lo ZIP, puoi prima sbloccare i file con `Get-ChildItem -Recurse | Unblock-File`.

Per vedere cosa verrebbe fatto, senza modificare nulla:

```powershell
.\Invoke-WindowsMaintenance.ps1 -WhatIf
```

## Utilizzo

```powershell
# Tutto ciò che si applica a questo PC
.\Invoke-WindowsMaintenance.ps1

# Passata veloce: senza DISM/SFC e senza l'analisi di Defender
.\Invoke-WindowsMaintenance.ps1 -Skip Repair, Defender

# Solo aggiornamenti, poi riavvio se necessario
.\Invoke-WindowsMaintenance.ps1 -Only WinGet, WindowsUpdate -AutoReboot

# Includere i driver e passare all'ultima versione di Windows 11
.\Invoke-WindowsMaintenance.ps1 -IncludeDrivers -IncludeFeatureUpdates

# Salvare i log sul Desktop
.\Invoke-WindowsMaintenance.ps1 -LogDirectory ([Environment]::GetFolderPath('Desktop'))

# Guida completa
Get-Help .\Invoke-WindowsMaintenance.ps1 -Detailed
```

| Parametro | Predefinito | Descrizione |
| --- | --- | --- |
| `-Skip` | nessuno | Passaggi da saltare. |
| `-Only` | tutti | Esegue solo questi passaggi. |
| `-IncludeDrivers` | disattivato | Installa anche i driver da Windows Update. |
| `-IncludeFeatureUpdates` | disattivato | Installa anche gli aggiornamenti delle funzionalità (ad esempio da 24H2 a 25H2). |
| `-AutoReboot` | disattivato | Riavvia 2 minuti dopo la fine, se necessario (`shutdown /a` annulla). |
| `-TempFileAgeDays` | `2` | Elimina solo i file temporanei più vecchi di questo valore. |
| `-LogDirectory` | `%ProgramData%\WindowsHealthAndUpdate\Logs` | Dove vengono salvati trascrizioni e report JSON. |
| `-LogRetentionDays` | `30` | Elimina log e report più vecchi. |
| `-WhatIf` / `-Confirm` | | Simula l'esecuzione o chiede conferma a ogni passaggio. |

## Pianificazione

`Register-MaintenanceTask.ps1` crea un'attività nell'Utilità di pianificazione che viene eseguita con il tuo utente, con privilegi elevati, solo mentre hai effettuato l'accesso: nessuna password viene memorizzata. Se il PC era spento all'ora prevista, l'attività parte appena possibile.

```powershell
# Ogni domenica alle 10:00 (predefinito)
.\Register-MaintenanceTask.ps1

# Ogni giorno alle 12:30, solo aggiornamenti
.\Register-MaintenanceTask.ps1 -Frequency Daily -At 12:30 -MaintenanceArguments '-Only WinGet, WindowsUpdate'

# Rimuovere l'attività
.\Register-MaintenanceTask.ps1 -Unregister
```

> **Sicurezza:** l'attività esegue lo script con privilegi di amministratore. Tienilo in una cartella che gli utenti standard non possono modificare (come `C:\Program Files\...`). Altrimenti qualsiasi processo eseguito con il tuo utente potrebbe modificare lo script e ottenere privilegi elevati. Lo script di registrazione ti avvisa se il file si trova nel tuo profilo utente.

## Log e report

Ogni esecuzione crea due file nella cartella dei log:

- `maintenance_<data_ora>.log`: trascrizione di PowerShell;
- `maintenance_<data_ora>.json`: report strutturato con i dati di sistema, lo stato del supporto, il risultato di ogni passaggio, l'eventuale necessità di riavvio e il codice di uscita. Puoi raccoglierlo da più computer o inviarlo a uno strumento di monitoraggio.

DISM e SFC mantengono i propri log dettagliati in `%windir%\Logs\DISM\dism.log` e `%windir%\Logs\CBS\CBS.log`.

## Cosa lo script non fa

- Nessun "tweak" del registro, rimozione di app o modifica di telemetria e servizi.
- Nessun `DISM /ResetBase`: gli aggiornamenti installati restano disinstallabili.
- Non elimina file utente, Download o il Cestino. Pulisce solo le cartelle temporanee, e solo i file più vecchi di `-TempFileAgeDays`.
- Non invia dati da nessuna parte.

## Sviluppo

```powershell
# Test unitari (Pester 5+)
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed

# Analisi statica
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Il workflow di CI esegue l'analizzatore, i test unitari e uno smoke test con `-WhatIf` su **Windows Server 2022 e 2025**, sia con **Windows PowerShell 5.1 sia con PowerShell 7**.

Gli script sono volutamente **solo ASCII**: Windows PowerShell 5.1 legge i file senza BOM con la tabella codici ANSI, e i caratteri accentati romperebbero lo script. Un test lo garantisce.

## Contribuire

Commenti, segnalazioni di bug e traduzioni sono benvenuti, anche nella tua lingua. Vedi [CONTRIBUTING.md](../CONTRIBUTING.md).

## Prossimi passi

- Notifica facoltativa via e-mail, Teams o webhook con il report JSON.
- Elenco delle CPU compatibili nella verifica di idoneità a Windows 11.
- Pubblicazione sulla PowerShell Gallery.

## Licenza

[MIT](../LICENSE) © Carlos Alberto Nakazawa
