# Windows Health & Update

[![CI](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml/badge.svg)](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml)
[![Лицензия: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](../LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Windows 10 | 11 | Server](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4)

[English](../README.md) | [Português (Brasil)](README.pt-BR.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md) | **Русский** | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-CN.md)

> Этот перевод может отставать от [английской версии](../README.md), которая является основной.

Скрипт обслуживания на PowerShell, который одной командой поддерживает ПК с Windows в актуальном и исправном состоянии: обновление приложений, Windows Update, Microsoft Defender, восстановление системных файлов, очистка и проверка состояния дисков.

Он **определяет точную версию Windows** (например, *Windows 11 Pro 25H2*, *Windows 10 Enterprise LTSC 2021* или *Windows Server 2022*), сообщает, **получает ли эта версия обновления безопасности**, и **адаптирует каждый шаг** под неё.

## Возможности

| Шаг | Что делает |
| --- | --- |
| `RestorePoint` | Создаёт точку восстановления до любых изменений. |
| `WinGet` | Тихо обновляет установленные приложения через `winget`. Находит winget, даже если его нет в `PATH` (учётная запись SYSTEM или другой администратор). |
| `Store` | Запускает поиск обновлений для приложений Microsoft Store. |
| `WindowsUpdate` | Ищет, скачивает и **устанавливает** обновления через API Windows Update Agent. Драйверы и обновления компонентов включаются по желанию. |
| `Defender` | Обновляет сигнатуры Microsoft Defender и запускает быструю проверку. Пропускается, если активен другой антивирус. |
| `Repair` | `DISM /RestoreHealth`, затем `sfc /scannow`. |
| `Cleanup` | `DISM /StartComponentCleanup`, временные файлы старше N дней во всех локальных профилях и кэш оптимизации доставки. Показывает освобождённое место. |
| `DiskHealth` | Состояние, температура, износ и ошибки чтения дисков, а также свободное место на каждом томе. |
| `UpgradeReadiness` | Только Windows 10: проверяет TPM 2.0, UEFI/безопасную загрузку, память, накопитель и базовые требования к процессору для Windows 11. |

Кроме того, скрипт:

- обнаруживает **ожидающую перезагрузку** до и после запуска и может перезагрузить компьютер автоматически (`-AutoReboot`);
- изолирует каждый шаг: ошибка записывается в журнал, а следующий шаг всё равно выполняется;
- сохраняет **журнал сеанса** и **JSON-отчёт** в `%ProgramData%\WindowsHealthAndUpdate\Logs` и удаляет старые файлы;
- поддерживает `-WhatIf` и `-Confirm`;
- запускается **только в одном экземпляре**: если ручной запуск начинается, пока работает запланированное задание (или наоборот), второй запуск сообщает об этом и завершается, ничего не изменив;
- возвращает коды выхода, понятные средствам автоматизации: `0` успех, `1` ошибка, `3010` требуется перезагрузка, `170` уже выполняется другой запуск.

## Поддерживаемые версии Windows

Скрипт определяет, на какой системе он запущен, и подстраивается. Шаги с пометкой «n/a» пропускаются с объяснением.

| Шаг | Windows 11 Home/Pro | Windows 11 Enterprise/Education | Windows 10 22H2 | Windows 10/11 LTSC | Windows Server 2016-2025 |
| --- | :---: | :---: | :---: | :---: | :---: |
| Статус поддержки | да | да | да (с пометкой ESU) | да | да |
| RestorePoint | да | да | да | да | n/a |
| WinGet | да | да | да ¹ | если установлен ¹ | если установлен ¹ |
| Store | да | да | да | n/a | n/a |
| WindowsUpdate | да | да | да | да | да |
| Defender | да ² | да ² | да ² | да ² | да ² |
| Repair / Cleanup / DiskHealth | да | да | да | да | да |
| UpgradeReadiness | n/a | n/a | да | n/a | n/a |

¹ Требуется [Установщик приложений](https://aka.ms/getwinget). Если его нет, шаг пропускается.
² Только если Microsoft Defender является активным антивирусом.

### Статус поддержки

Даты окончания поддержки взяты со страниц Microsoft [Windows release health](https://learn.microsoft.com/windows/release-health/) (проверено в ноябре 2026 года). На эту дату:

| Версия | Сборка | Home/Pro | Enterprise/Education |
| --- | --- | --- | --- |
| Windows 11 26H2 | 26300 | 10.10.2028 | 09.10.2029 |
| Windows 11 26H1 (только новые устройства) | 28000 | 14.03.2028 | 13.03.2029 |
| Windows 11 25H2 | 26200 | 12.10.2027 | 10.10.2028 |
| Windows 11 24H2 | 26100 | **завершена 13.10.2026** | 12.10.2027 |
| Windows 11 23H2 и старше | 22631- | завершена | завершена |
| Windows 10 22H2 | 19045 | **завершена 14.10.2025** (только ESU) | завершена (только ESU) |

Версии LTSC и Windows Server также учтены. Полная таблица находится в функции `Get-WindowsLifecycleData` в скрипте.

### Как определяется версия

Значение реестра `ProductName` в Windows 11 по-прежнему содержит **«Windows 10»**, поэтому скрипт на него не опирается. Он читает `CurrentBuild`, `UBR`, `DisplayVersion`, `EditionID` и `InstallationType` из `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` и определяет:

- **семейство**: Windows Server, если `InstallationType` равен `Server`/`Server Core`; Windows 11 начиная со сборки 22000; в остальных случаях Windows 10;
- **канал обслуживания**: Home/Pro (24 месяца), Enterprise/Education (36 месяцев), LTSC, IoT LTSC или Server. Именно он определяет, какая дата окончания поддержки применяется. Например, сборка 26100 может быть Windows 11 24H2, Windows 11 LTSC 2024 *или* Windows Server 2025, и у каждой своя дата.

## Требования

- Windows 10, Windows 11 или Windows Server 2016+
- Windows PowerShell 5.1 (входит в Windows) или PowerShell 7+
- Сеанс с повышенными правами (Запуск от имени администратора)

## Быстрый старт

1. Скачайте или клонируйте репозиторий, например в `C:\Program Files\WindowsHealthAndUpdate`.
2. Откройте **Windows Terminal** или **PowerShell** от имени **администратора**.
3. Запустите скрипт. `-ExecutionPolicy Bypass` действует только для этого процесса и не меняет системные настройки:

   ```powershell
   cd 'C:\Program Files\WindowsHealthAndUpdate'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WindowsMaintenance.ps1
   ```

   Если вы скачали ZIP-архив, можно сначала разблокировать файлы командой `Get-ChildItem -Recurse | Unblock-File`.

Чтобы посмотреть, что будет сделано, ничего не меняя:

```powershell
.\Invoke-WindowsMaintenance.ps1 -WhatIf
```

## Использование

```powershell
# Всё, что применимо к этому ПК
.\Invoke-WindowsMaintenance.ps1

# Быстрый прогон: без DISM/SFC и без проверки Defender
.\Invoke-WindowsMaintenance.ps1 -Skip Repair, Defender

# Только обновления, затем перезагрузка при необходимости
.\Invoke-WindowsMaintenance.ps1 -Only WinGet, WindowsUpdate -AutoReboot

# Включить драйверы и перейти на последнюю версию Windows 11
.\Invoke-WindowsMaintenance.ps1 -IncludeDrivers -IncludeFeatureUpdates

# Сохранять журналы на рабочем столе
.\Invoke-WindowsMaintenance.ps1 -LogDirectory ([Environment]::GetFolderPath('Desktop'))

# Полная справка
Get-Help .\Invoke-WindowsMaintenance.ps1 -Detailed
```

| Параметр | По умолчанию | Описание |
| --- | --- | --- |
| `-Skip` | нет | Шаги, которые нужно пропустить. |
| `-Only` | все | Выполнить только эти шаги. |
| `-IncludeDrivers` | выкл. | Устанавливать также драйверы из Windows Update. |
| `-IncludeFeatureUpdates` | выкл. | Устанавливать также обновления компонентов (например, с 24H2 на 25H2). |
| `-AutoReboot` | выкл. | Перезагрузить через 2 минуты после завершения, если требуется (`shutdown /a` отменяет). |
| `-TempFileAgeDays` | `2` | Удалять только временные файлы старше этого срока. |
| `-LogDirectory` | `%ProgramData%\WindowsHealthAndUpdate\Logs` | Папка для журналов и JSON-отчётов. |
| `-LogRetentionDays` | `30` | Удалять более старые журналы и отчёты. |
| `-WhatIf` / `-Confirm` | | Пробный запуск или подтверждение каждого шага. |

## Планирование

`Register-MaintenanceTask.ps1` создаёт задание в Планировщике заданий, которое запускается от вашего имени с повышенными правами и только когда вы вошли в систему, поэтому пароль не сохраняется. Если в запланированное время ПК был выключен, задание запустится при первой возможности.

```powershell
# Каждое воскресенье в 10:00 (по умолчанию)
.\Register-MaintenanceTask.ps1

# Каждый день в 12:30, только обновления
.\Register-MaintenanceTask.ps1 -Frequency Daily -At 12:30 -MaintenanceArguments '-Only WinGet, WindowsUpdate'

# Удалить задание
.\Register-MaintenanceTask.ps1 -Unregister
```

> **Безопасность:** задание запускает скрипт с правами администратора. Храните его в папке, которую обычные пользователи не могут изменить (например, `C:\Program Files\...`). Иначе любой процесс, работающий под вашей учётной записью, сможет отредактировать скрипт и получить повышенные права. Скрипт регистрации предупредит, если файл находится в вашем профиле.

## Журналы и отчёт

При каждом запуске в папке журналов создаются два файла:

- `maintenance_<дата_время>.log`: журнал сеанса PowerShell;
- `maintenance_<дата_время>.json`: структурированный отчёт со сведениями о системе, статусом поддержки, результатом каждого шага, необходимостью перезагрузки и кодом выхода. Его можно собирать с нескольких компьютеров или передавать в систему мониторинга.

Для Windows Update отчёт перечисляет **каждое найденное обновление**. Поэтому после запуска без присмотра видно, что установилось, что завершилось ошибкой и нужна ли ещё перезагрузка:

```json
"steps": [{
  "Step": "WindowsUpdate",
  "Status": "Warning",
  "Message": "1 installed, 1 failed (KB5070002). Restart required.",
  "Details": [
    { "Title": "2026-11 Cumulative Update", "KB": "KB5070001", "Result": "Installed", "HResult": null, "RebootRequired": true },
    { "Title": "Servicing Stack Update", "KB": "KB5070002", "Result": "Failed", "HResult": "0x80240022", "RebootRequired": false }
  ]
}],
"rebootRequired": true,
"rebootScheduled": false
```

- `Result`: `Installed`, `InstalledWithErrors`, `Failed`, `Aborted`, `DownloadFailed` или `NotInstalled` с полем `Reason` (`Optional`, `FeatureUpdate`, `NeedsUserInput`).
- `HResult`: код ошибки Windows Update; его можно найти в [списке кодов ошибок Windows Update](https://learn.microsoft.com/windows/deployment/update/windows-update-error-reference).
- `rebootScheduled`: `true` только если `-AutoReboot` действительно запланировал перезагрузку; одно лишь `rebootRequired` означает, что она ещё не выполнена.

Прочитать последний отчёт:

```powershell
$latest = Get-ChildItem "$env:ProgramData\WindowsHealthAndUpdate\Logs\maintenance_*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
$report = Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json
$report.steps | Where-Object Step -eq 'WindowsUpdate' | Select-Object -ExpandProperty Details | Format-Table Title, KB, Result, HResult, RebootRequired
"Restart required: $($report.rebootRequired) (scheduled: $($report.rebootScheduled))"
```

> **Код выхода `1` может также означать, что требуется перезагрузка.** Один код не может одновременно сообщить «что-то не удалось» и «нужна перезагрузка», поэтому приоритет у ошибки. Проверяйте `rebootRequired` в отчёте.

DISM и SFC ведут собственные подробные журналы: `%windir%\Logs\DISM\dism.log` и `%windir%\Logs\CBS\CBS.log`.

## Чего скрипт не делает

- Никаких «твиков» реестра, удаления приложений, изменений телеметрии или служб.
- Не использует `DISM /ResetBase`: установленные обновления можно удалить.
- Не удаляет пользовательские файлы, папку «Загрузки» и корзину. Очищаются только временные папки, и только файлы старше `-TempFileAgeDays`.
- Никуда не отправляет данные.

## Разработка

```powershell
# Модульные тесты (Pester 5+)
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed

# Статический анализ
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Конвейер CI запускает анализатор, модульные тесты и smoke-тест с `-WhatIf` на **Windows Server 2022 и 2025**, в **Windows PowerShell 5.1 и PowerShell 7**.

Скрипты намеренно содержат **только символы ASCII**: Windows PowerShell 5.1 читает файлы без BOM в кодировке ANSI, и символы вне ASCII сломали бы скрипт. Это проверяется тестом.

## Участие

Комментарии, сообщения об ошибках и переводы приветствуются, можно писать на любом языке. См. [CONTRIBUTING.md](../CONTRIBUTING.md).

## Планы

- Необязательные уведомления по электронной почте, в Teams или через webhook с JSON-отчётом.
- Список совместимых процессоров для проверки готовности к Windows 11.
- Публикация в PowerShell Gallery.

## Лицензия

[MIT](../LICENSE) © Carlos Alberto Nakazawa
