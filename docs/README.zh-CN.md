# Windows Health & Update

[![CI](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml/badge.svg)](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml)
[![许可证: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](../LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Windows 10 | 11 | Server](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4)

[English](../README.md) | [Português (Brasil)](README.pt-BR.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | **简体中文**

> 本译文可能落后于作为基准的[英文版本](../README.md)。

一个 PowerShell 维护脚本，只需一条命令即可让 Windows 电脑保持最新、健康的状态：应用更新、Windows 更新、Microsoft Defender、系统文件修复、清理以及磁盘健康检查。

它会**识别确切的 Windows 版本**（例如 *Windows 11 Pro 25H2*、*Windows 10 Enterprise LTSC 2021* 或 *Windows Server 2022*），告诉你**该版本是否仍在接收安全更新**，并**根据该版本调整每个步骤**。

## 功能

| 步骤 | 作用 |
| --- | --- |
| `RestorePoint` | 在进行任何更改之前创建还原点。 |
| `WinGet` | 使用 `winget` 静默更新已安装的应用。即使 winget 不在 `PATH` 中（SYSTEM 账户或其他管理员账户），也能找到它。 |
| `Store` | 触发 Microsoft Store 应用的更新检查。 |
| `WindowsUpdate` | 通过 Windows Update Agent API 搜索、下载并**安装**更新。驱动程序和功能更新为可选项。 |
| `Defender` | 更新 Microsoft Defender 的病毒定义并运行快速扫描。如果启用了其他杀毒软件，则跳过此步骤。 |
| `Repair` | 先运行 `DISM /RestoreHealth`，再运行 `sfc /scannow`。 |
| `Cleanup` | 运行 `DISM /StartComponentCleanup`，清理所有本地用户配置文件中超过 N 天的临时文件以及传递优化缓存，并报告释放的空间。 |
| `DiskHealth` | 显示磁盘的健康状态、温度、磨损程度和读取错误，以及每个卷的可用空间。 |
| `UpgradeReadiness` | 仅限 Windows 10：检查 Windows 11 所需的 TPM 2.0、UEFI/安全启动、内存、存储空间和 CPU 基本要求。 |

此外，该脚本还会：

- 在运行前后检测**待处理的重启**，并可自动重启（`-AutoReboot`）；
- 隔离每个步骤：某一步失败会被记录下来，后续步骤照常执行；
- 将**运行记录（transcript）**和 **JSON 报告**保存到 `%ProgramData%\WindowsHealthAndUpdate\Logs`，并自动删除旧文件；
- 支持 `-WhatIf` 和 `-Confirm`；
- 返回自动化工具能够识别的退出代码：`0` 成功，`1` 失败，`3010` 需要重启。

## 支持的 Windows 版本

脚本会识别当前运行的系统并相应调整。标记为 "n/a" 的步骤会被跳过，并说明原因。

| 步骤 | Windows 11 家庭版/专业版 | Windows 11 企业版/教育版 | Windows 10 22H2 | Windows 10/11 LTSC | Windows Server 2016-2025 |
| --- | :---: | :---: | :---: | :---: | :---: |
| 支持状态检查 | 是 | 是 | 是（附 ESU 提示） | 是 | 是 |
| RestorePoint | 是 | 是 | 是 | 是 | n/a |
| WinGet | 是 | 是 | 是 ¹ | 已安装时 ¹ | 已安装时 ¹ |
| Store | 是 | 是 | 是 | n/a | n/a |
| WindowsUpdate | 是 | 是 | 是 | 是 | 是 |
| Defender | 是 ² | 是 ² | 是 ² | 是 ² | 是 ² |
| Repair / Cleanup / DiskHealth | 是 | 是 | 是 | 是 | 是 |
| UpgradeReadiness | n/a | n/a | 是 | n/a | n/a |

¹ 需要[应用安装程序](https://aka.ms/getwinget)。如果未安装，则跳过此步骤。
² 仅当 Microsoft Defender 是当前启用的杀毒软件时。

### 支持状态

支持结束日期来自 Microsoft 的 [Windows release health](https://learn.microsoft.com/windows/release-health/) 页面（2026 年 11 月核对）。截至该日期：

| 版本 | 内部版本 | 家庭版/专业版 | 企业版/教育版 |
| --- | --- | --- | --- |
| Windows 11 26H2 | 26300 | 2028-10-10 | 2029-10-09 |
| Windows 11 26H1（仅限新设备） | 28000 | 2028-03-14 | 2029-03-13 |
| Windows 11 25H2 | 26200 | 2027-10-12 | 2028-10-10 |
| Windows 11 24H2 | 26100 | **已于 2026-10-13 结束** | 2027-10-12 |
| Windows 11 23H2 及更早版本 | 22631- | 已结束 | 已结束 |
| Windows 10 22H2 | 19045 | **已于 2025-10-14 结束**（仅 ESU） | 已结束（仅 ESU） |

LTSC 和 Windows Server 版本同样涵盖在内。完整的表格见脚本中的 `Get-WindowsLifecycleData` 函数。

### 如何识别版本

在 Windows 11 上，注册表值 `ProductName` 仍然显示为 **"Windows 10"**，因此脚本不依赖它。脚本从 `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` 读取 `CurrentBuild`、`UBR`、`DisplayVersion`、`EditionID` 和 `InstallationType`，并据此判断：

- **产品系列**：当 `InstallationType` 为 `Server`/`Server Core` 时为 Windows Server，内部版本 22000 及以上为 Windows 11，其余为 Windows 10；
- **服务通道**：家庭版/专业版（24 个月）、企业版/教育版（36 个月）、LTSC、IoT LTSC 或 Server。适用哪个支持结束日期由它决定。例如，内部版本 26100 可能是 Windows 11 24H2、Windows 11 LTSC 2024 *或* Windows Server 2025，每个的结束日期都不同。

## 系统要求

- Windows 10、Windows 11 或 Windows Server 2016 及以上
- Windows PowerShell 5.1（Windows 自带）或 PowerShell 7 及以上
- 以管理员身份运行的会话

## 快速开始

1. 下载或克隆本仓库，例如放到 `C:\Program Files\WindowsHealthAndUpdate`。
2. 以**管理员身份**打开 **Windows 终端**或 **PowerShell**。
3. 运行脚本。`-ExecutionPolicy Bypass` 只对当前进程生效，不会更改任何系统设置：

   ```powershell
   cd 'C:\Program Files\WindowsHealthAndUpdate'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WindowsMaintenance.ps1
   ```

   如果你下载的是 ZIP 包，可以先用 `Get-ChildItem -Recurse | Unblock-File` 解除文件锁定。

在不做任何更改的情况下预览将执行的操作：

```powershell
.\Invoke-WindowsMaintenance.ps1 -WhatIf
```

## 用法

```powershell
# 执行适用于这台电脑的所有步骤
.\Invoke-WindowsMaintenance.ps1

# 快速运行：跳过 DISM/SFC 和 Defender 扫描
.\Invoke-WindowsMaintenance.ps1 -Skip Repair, Defender

# 只做更新，必要时重启
.\Invoke-WindowsMaintenance.ps1 -Only WinGet, WindowsUpdate -AutoReboot

# 包括驱动程序，并升级到最新的 Windows 11 版本
.\Invoke-WindowsMaintenance.ps1 -IncludeDrivers -IncludeFeatureUpdates

# 将日志保存到桌面
.\Invoke-WindowsMaintenance.ps1 -LogDirectory ([Environment]::GetFolderPath('Desktop'))

# 完整帮助
Get-Help .\Invoke-WindowsMaintenance.ps1 -Detailed
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-Skip` | 无 | 要跳过的步骤。 |
| `-Only` | 全部 | 只运行这些步骤。 |
| `-IncludeDrivers` | 关闭 | 同时安装 Windows 更新提供的驱动程序。 |
| `-IncludeFeatureUpdates` | 关闭 | 同时安装功能更新（例如从 24H2 升级到 25H2）。 |
| `-AutoReboot` | 关闭 | 如有需要，在结束 2 分钟后重启（`shutdown /a` 可取消）。 |
| `-TempFileAgeDays` | `2` | 只删除比这更旧的临时文件。 |
| `-LogDirectory` | `%ProgramData%\WindowsHealthAndUpdate\Logs` | 运行记录和 JSON 报告的保存位置。 |
| `-LogRetentionDays` | `30` | 删除更旧的日志和报告。 |
| `-WhatIf` / `-Confirm` | | 预览执行内容，或在每一步前确认。 |

## 计划任务

`Register-MaintenanceTask.ps1` 会在任务计划程序中创建一个任务。该任务以你的用户身份、管理员权限运行，并且只在你登录时运行，因此不会保存密码。如果到了计划时间电脑处于关机状态，任务会在条件允许时尽快运行。

```powershell
# 每周日 10:00（默认）
.\Register-MaintenanceTask.ps1

# 每天 12:30，只做更新
.\Register-MaintenanceTask.ps1 -Frequency Daily -At 12:30 -MaintenanceArguments '-Only WinGet, WindowsUpdate'

# 删除任务
.\Register-MaintenanceTask.ps1 -Unregister
```

> **安全提示：** 该任务会以管理员权限运行脚本。请把脚本放在普通用户无法修改的文件夹中（例如 `C:\Program Files\...`）。否则，任何以你的用户身份运行的进程都可能修改脚本并获得管理员权限。如果脚本位于你的用户配置文件目录中，注册脚本会发出警告。

## 日志和报告

每次运行都会在日志文件夹中生成两个文件：

- `maintenance_<时间戳>.log`：PowerShell 运行记录；
- `maintenance_<时间戳>.json`：结构化报告，包含系统信息、支持状态、每个步骤的结果、是否需要重启以及退出代码。可以从多台电脑收集，或交给监控工具处理。

对于 Windows 更新，报告会列出**找到的每一个更新**。因此在无人值守运行之后，也能知道哪些已安装、哪些失败了，以及是否仍需重启：

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

- `Result`：`Installed`、`InstalledWithErrors`、`Failed`、`Aborted`、`DownloadFailed`，或带有 `Reason`（`Optional`、`FeatureUpdate`、`NeedsUserInput`）的 `NotInstalled`。
- `HResult`：Windows 更新的错误代码，可在 [Windows 更新错误代码列表](https://learn.microsoft.com/windows/deployment/update/windows-update-error-reference)中查询。
- `rebootScheduled`：只有当 `-AutoReboot` 确实安排了重启时才为 `true`；仅 `rebootRequired` 为 `true` 表示重启仍待完成。

读取最新的报告：

```powershell
$latest = Get-ChildItem "$env:ProgramData\WindowsHealthAndUpdate\Logs\maintenance_*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
$report = Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json
$report.steps | Where-Object Step -eq 'WindowsUpdate' | Select-Object -ExpandProperty Details | Format-Table Title, KB, Result, HResult, RebootRequired
"Restart required: $($report.rebootRequired) (scheduled: $($report.rebootScheduled))"
```

> **退出代码 `1` 也可能表示有待完成的重启。** 一个退出代码无法同时表达"有步骤失败"和"需要重启"，因此以失败为准。请查看报告中的 `rebootRequired`。

DISM 和 SFC 会分别在 `%windir%\Logs\DISM\dism.log` 和 `%windir%\Logs\CBS\CBS.log` 中保留各自的详细日志。

## 脚本不会做的事

- 不做注册表"优化"、不删除应用、不更改遥测或系统服务。
- 不使用 `DISM /ResetBase`：已安装的更新仍然可以卸载。
- 不删除用户文件、"下载"文件夹或回收站。只清理临时文件夹，并且只删除比 `-TempFileAgeDays` 更旧的文件。
- 不向任何地方发送数据。

## 开发

```powershell
# 单元测试（Pester 5 及以上）
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed

# 静态分析
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

CI 工作流会在 **Windows Server 2022 和 2025** 上，分别使用 **Windows PowerShell 5.1 和 PowerShell 7** 运行静态分析、单元测试以及 `-WhatIf` 冒烟测试。

脚本文件有意**只使用 ASCII 字符**：Windows PowerShell 5.1 会用 ANSI 代码页读取没有 BOM 的文件，非 ASCII 字符会导致脚本出错。有专门的测试确保这一点。

## 参与贡献

欢迎提出意见、报告问题和提供翻译，使用任何语言都可以。请参阅 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 路线图

- 可选的通知功能，通过电子邮件、Teams 或 Webhook 发送 JSON 报告。
- 在 Windows 11 就绪检查中加入兼容 CPU 列表。
- 发布到 PowerShell Gallery。

## 许可证

[MIT](../LICENSE) © Carlos Alberto Nakazawa
