# Windows Health & Update

[![CI](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml/badge.svg)](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml)
[![ライセンス: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](../LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Windows 10 | 11 | Server](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4)

[English](../README.md) | [Português (Brasil)](README.pt-BR.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | **日本語** | [한국어](README.ko.md) | [简体中文](README.zh-CN.md)

> この翻訳は、基準となる[英語版](../README.md)より古い場合があります。

Windows PC を 1 つのコマンドで最新かつ健全な状態に保つ PowerShell メンテナンススクリプトです。アプリの更新、Windows Update、Microsoft Defender、システムファイルの修復、クリーンアップ、ディスクの状態確認を行います。

**Windows の正確なバージョンを判定**し(例: *Windows 11 Pro 25H2*、*Windows 10 Enterprise LTSC 2021*、*Windows Server 2022*)、**そのバージョンがまだセキュリティ更新プログラムを受け取れるか**を表示し、**各ステップをそのバージョンに合わせて調整**します。

## 機能

| ステップ | 内容 |
| --- | --- |
| `RestorePoint` | 変更を加える前に復元ポイントを作成します。 |
| `WinGet` | インストール済みのアプリを `winget` でサイレント更新します。`PATH` に winget がない場合 (SYSTEM アカウントや別の管理者ユーザー) でも見つけ出します。 |
| `Store` | Microsoft Store アプリの更新チェックを開始します。 |
| `WindowsUpdate` | Windows Update Agent API を使って更新プログラムを検索、ダウンロード、**インストール**します。ドライバーと機能更新プログラムはオプションです。 |
| `Defender` | Microsoft Defender の定義を更新し、クイックスキャンを実行します。別のウイルス対策ソフトが有効な場合はスキップします。 |
| `Repair` | `DISM /RestoreHealth` の後に `sfc /scannow` を実行します。 |
| `Cleanup` | `DISM /StartComponentCleanup`、すべてのローカルプロファイルの N 日より古い一時ファイル、配信の最適化キャッシュを削除し、解放した容量を報告します。 |
| `DiskHealth` | ディスクの状態、温度、摩耗、読み取りエラー、各ボリュームの空き容量を表示します。 |
| `UpgradeReadiness` | Windows 10 のみ: Windows 11 に必要な TPM 2.0、UEFI/セキュアブート、メモリ、ストレージ、CPU の基本要件を確認します。 |

さらにこのスクリプトは:

- 実行の前後で**保留中の再起動**を検出し、自動で再起動できます (`-AutoReboot`)。
- 各ステップを独立して実行します。失敗は記録され、次のステップは引き続き実行されます。
- **トランスクリプト**と **JSON レポート**を `%ProgramData%\WindowsHealthAndUpdate\Logs` に保存し、古いものは自動で削除します。
- `-WhatIf` と `-Confirm` に対応しています。
- **同時に 1 つだけ**実行されます。スケジュールされたタスクの実行中に手動で実行した場合 (またはその逆)、後から起動した方はその旨を表示し、何も変更せずに終了します。
- 自動化ツールが理解できる終了コードを返します: `0` 成功、`1` 失敗、`3010` 再起動が必要、`170` 別の実行がすでに進行中。

## 対応する Windows バージョン

スクリプトは実行中のシステムを判定して動作を調整します。「n/a」のステップは理由を表示してスキップします。

| ステップ | Windows 11 Home/Pro | Windows 11 Enterprise/Education | Windows 10 22H2 | Windows 10/11 LTSC | Windows Server 2016-2025 |
| --- | :---: | :---: | :---: | :---: | :---: |
| サポート状況の確認 | ○ | ○ | ○ (ESU の案内) | ○ | ○ |
| RestorePoint | ○ | ○ | ○ | ○ | n/a |
| WinGet | ○ | ○ | ○ ¹ | インストール時 ¹ | インストール時 ¹ |
| Store | ○ | ○ | ○ | n/a | n/a |
| WindowsUpdate | ○ | ○ | ○ | ○ | ○ |
| Defender | ○ ² | ○ ² | ○ ² | ○ ² | ○ ² |
| Repair / Cleanup / DiskHealth | ○ | ○ | ○ | ○ | ○ |
| UpgradeReadiness | n/a | n/a | ○ | n/a | n/a |

¹ [アプリ インストーラー](https://aka.ms/getwinget)が必要です。ない場合、このステップはスキップされます。
² Microsoft Defender が有効なウイルス対策ソフトである場合のみ。

### サポート状況

サポート終了日は Microsoft の [Windows release health](https://learn.microsoft.com/windows/release-health/) ページに基づいています (2026 年 11 月に確認)。その時点での状況:

| バージョン | ビルド | Home/Pro | Enterprise/Education |
| --- | --- | --- | --- |
| Windows 11 26H2 | 26300 | 2028-10-10 | 2029-10-09 |
| Windows 11 26H1 (新しいデバイスのみ) | 28000 | 2028-03-14 | 2029-03-13 |
| Windows 11 25H2 | 26200 | 2027-10-12 | 2028-10-10 |
| Windows 11 24H2 | 26100 | **2026-10-13 に終了** | 2027-10-12 |
| Windows 11 23H2 以前 | 22631- | 終了 | 終了 |
| Windows 10 22H2 | 19045 | **2025-10-14 に終了** (ESU のみ) | 終了 (ESU のみ) |

LTSC と Windows Server のバージョンにも対応しています。完全な一覧はスクリプト内の `Get-WindowsLifecycleData` 関数にあります。

### バージョンの判定方法

レジストリ値 `ProductName` は Windows 11 でも **「Windows 10」** のままなので、スクリプトはこの値に頼りません。`HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` から `CurrentBuild`、`UBR`、`DisplayVersion`、`EditionID`、`InstallationType` を読み取り、次の情報を導き出します。

- **ファミリ**: `InstallationType` が `Server`/`Server Core` なら Windows Server、ビルド 22000 以降なら Windows 11、それ以外は Windows 10。
- **サービスチャネル**: Home/Pro (24 か月)、Enterprise/Education (36 か月)、LTSC、IoT LTSC、Server。どのサポート終了日が適用されるかはこれで決まります。たとえばビルド 26100 は Windows 11 24H2、Windows 11 LTSC 2024、Windows Server 2025 の*いずれか*であり、それぞれ終了日が異なります。

## 必要な環境

- Windows 10、Windows 11、または Windows Server 2016 以降
- Windows PowerShell 5.1 (Windows に標準搭載) または PowerShell 7 以降
- 管理者として実行したセッション

## クイックスタート

1. リポジトリをダウンロードまたはクローンします。例: `C:\Program Files\WindowsHealthAndUpdate`。
2. **Windows ターミナル**または **PowerShell** を**管理者として**開きます。
3. スクリプトを実行します。`-ExecutionPolicy Bypass` はこのプロセスにだけ適用され、システムの設定は変更しません。

   ```powershell
   cd 'C:\Program Files\WindowsHealthAndUpdate'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WindowsMaintenance.ps1
   ```

   ZIP をダウンロードした場合は、先に `Get-ChildItem -Recurse | Unblock-File` でファイルのブロックを解除できます。

何も変更せずに、実行内容だけを確認するには:

```powershell
.\Invoke-WindowsMaintenance.ps1 -WhatIf
```

## 使い方

```powershell
# この PC に該当するすべてのステップ
.\Invoke-WindowsMaintenance.ps1

# 短時間の実行: DISM/SFC と Defender のスキャンを省略
.\Invoke-WindowsMaintenance.ps1 -Skip Repair, Defender

# 更新だけを行い、必要なら再起動
.\Invoke-WindowsMaintenance.ps1 -Only WinGet, WindowsUpdate -AutoReboot

# ドライバーも含め、最新の Windows 11 バージョンに移行
.\Invoke-WindowsMaintenance.ps1 -IncludeDrivers -IncludeFeatureUpdates

# ログをデスクトップに保存
.\Invoke-WindowsMaintenance.ps1 -LogDirectory ([Environment]::GetFolderPath('Desktop'))

# 詳しいヘルプ
Get-Help .\Invoke-WindowsMaintenance.ps1 -Detailed
```

| パラメーター | 既定値 | 説明 |
| --- | --- | --- |
| `-Skip` | なし | スキップするステップ。 |
| `-Only` | すべて | 指定したステップだけを実行します。 |
| `-IncludeDrivers` | オフ | Windows Update のドライバーもインストールします。 |
| `-IncludeFeatureUpdates` | オフ | 機能更新プログラムもインストールします (例: 24H2 から 25H2)。 |
| `-AutoReboot` | オフ | 必要な場合、終了 2 分後に再起動します (`shutdown /a` で取り消し)。 |
| `-TempFileAgeDays` | `2` | これより古い一時ファイルだけを削除します。 |
| `-LogDirectory` | `%ProgramData%\WindowsHealthAndUpdate\Logs` | トランスクリプトと JSON レポートの保存先。 |
| `-LogRetentionDays` | `30` | これより古いログとレポートを削除します。 |
| `-WhatIf` / `-Confirm` | | 実行内容の確認、またはステップごとの確認。 |

## スケジュール実行

`Register-MaintenanceTask.ps1` はタスク スケジューラにタスクを作成します。タスクはあなたのユーザーとして管理者権限で、サインインしている間だけ実行されるため、パスワードは保存されません。予定の時刻に PC の電源が切れていた場合は、可能になり次第実行されます。

```powershell
# 毎週日曜日の 10:00 (既定)
.\Register-MaintenanceTask.ps1

# 毎日 12:30 に更新だけを実行
.\Register-MaintenanceTask.ps1 -Frequency Daily -At 12:30 -MaintenanceArguments '-Only WinGet, WindowsUpdate'

# タスクを削除
.\Register-MaintenanceTask.ps1 -Unregister
```

> **セキュリティ:** タスクはスクリプトを管理者権限で実行します。標準ユーザーが変更できないフォルダー (`C:\Program Files\...` など) に置いてください。そうしないと、あなたのユーザーで動く任意のプロセスがスクリプトを書き換えて管理者権限を得られてしまいます。スクリプトがユーザープロファイル内にある場合、登録スクリプトが警告します。

## ログとレポート

実行のたびに、ログフォルダーに 2 つのファイルが作成されます。

- `maintenance_<日時>.log`: PowerShell のトランスクリプト。
- `maintenance_<日時>.json`: システム情報、サポート状況、各ステップの結果、再起動の要否、終了コードを含む構造化レポート。複数の PC から収集したり、監視ツールに渡したりできます。

Windows Update については、レポートに**見つかったすべての更新プログラム**が記録されます。無人実行の後でも、何がインストールされ、何が失敗し、まだ再起動が必要かがわかります。

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

- `Result`: `Installed`、`InstalledWithErrors`、`Failed`、`Aborted`、`DownloadFailed`、または `Reason` (`Optional`、`FeatureUpdate`、`NeedsUserInput`) 付きの `NotInstalled`。
- `HResult`: Windows Update のエラーコード。[Windows Update のエラーコード一覧](https://learn.microsoft.com/windows/deployment/update/windows-update-error-reference)で調べられます。
- `rebootScheduled`: `-AutoReboot` が実際に再起動を予約した場合だけ `true` になります。`rebootRequired` だけが `true` の場合、再起動はまだ保留中です。

最新のレポートを読むには:

```powershell
$latest = Get-ChildItem "$env:ProgramData\WindowsHealthAndUpdate\Logs\maintenance_*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
$report = Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json
$report.steps | Where-Object Step -eq 'WindowsUpdate' | Select-Object -ExpandProperty Details | Format-Table Title, KB, Result, HResult, RebootRequired
"Restart required: $($report.rebootRequired) (scheduled: $($report.rebootScheduled))"
```

> **終了コード `1` は、再起動が保留中であることも意味する場合があります。** 1 つの終了コードで「失敗した」と「再起動が必要」を同時に表すことはできないため、失敗が優先されます。レポートの `rebootRequired` を確認してください。

DISM と SFC は、それぞれ `%windir%\Logs\DISM\dism.log` と `%windir%\Logs\CBS\CBS.log` に詳しいログを残します。

## このスクリプトが行わないこと

- レジストリの「チューニング」、アプリの削除、テレメトリやサービスの変更は行いません。
- `DISM /ResetBase` は使いません。インストール済みの更新プログラムは引き続きアンインストールできます。
- ユーザーのファイル、ダウンロード フォルダー、ごみ箱は削除しません。対象は一時フォルダーだけで、`-TempFileAgeDays` より古いファイルに限ります。
- データをどこにも送信しません。

## 開発

```powershell
# 単体テスト (Pester 5 以降)
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed

# 静的解析
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

CI ワークフローは、**Windows Server 2022 と 2025** 上で **Windows PowerShell 5.1 と PowerShell 7** の両方を使い、静的解析、単体テスト、`-WhatIf` によるスモークテストを実行します。

スクリプトファイルは意図的に **ASCII 文字だけ**で書かれています。Windows PowerShell 5.1 は BOM のないファイルを ANSI コードページで読み込むため、ASCII 以外の文字があるとスクリプトが壊れます。テストでこれを確認しています。

## コントリビュート

コメント、バグ報告、翻訳を歓迎します。どの言語で書いてもかまいません。[CONTRIBUTING.md](../CONTRIBUTING.md) をご覧ください。

## 今後の予定

- JSON レポートをメール、Teams、Webhook で通知する機能 (オプション)。
- Windows 11 への準備状況チェックでの対応 CPU 一覧の確認。
- PowerShell Gallery への公開。

## ライセンス

[MIT](../LICENSE) © Carlos Alberto Nakazawa
