# Windows Health & Update

[![CI](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml/badge.svg)](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml)
[![라이선스: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](../LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Windows 10 | 11 | Server](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4)

[English](../README.md) | [Português (Brasil)](README.pt-BR.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [日本語](README.ja.md) | **한국어** | [简体中文](README.zh-CN.md)

> 이 번역은 기준 문서인 [영어 버전](../README.md)보다 오래되었을 수 있습니다.

명령 하나로 Windows PC를 최신 상태로, 건강하게 유지하는 PowerShell 유지 관리 스크립트입니다. 앱 업데이트, Windows 업데이트, Microsoft Defender, 시스템 파일 복구, 정리, 디스크 상태 점검을 수행합니다.

**정확한 Windows 버전을 감지**하고(예: *Windows 11 Pro 25H2*, *Windows 10 Enterprise LTSC 2021*, *Windows Server 2022*), **해당 버전이 아직 보안 업데이트를 받는지** 알려 주며, **각 단계를 그 버전에 맞게 조정**합니다.

## 기능

| 단계 | 하는 일 |
| --- | --- |
| `RestorePoint` | 변경하기 전에 복원 지점을 만듭니다. |
| `WinGet` | 설치된 앱을 `winget`으로 자동 업데이트합니다. winget이 `PATH`에 없어도(SYSTEM 계정 또는 다른 관리자 계정) 찾아냅니다. |
| `Store` | Microsoft Store 앱의 업데이트 검사를 시작합니다. |
| `WindowsUpdate` | Windows Update Agent API로 업데이트를 검색, 다운로드, **설치**합니다. 드라이버와 기능 업데이트는 선택 사항입니다. |
| `Defender` | Microsoft Defender 정의를 업데이트하고 빠른 검사를 실행합니다. 다른 백신 프로그램이 활성화되어 있으면 건너뜁니다. |
| `Repair` | `DISM /RestoreHealth` 후 `sfc /scannow`를 실행합니다. |
| `Cleanup` | `DISM /StartComponentCleanup`, 모든 로컬 프로필에서 N일보다 오래된 임시 파일, 전송 최적화 캐시를 정리하고 확보한 공간을 보고합니다. |
| `DiskHealth` | 디스크의 상태, 온도, 마모도, 읽기 오류와 각 볼륨의 여유 공간을 보여 줍니다. |
| `UpgradeReadiness` | Windows 10 전용: Windows 11에 필요한 TPM 2.0, UEFI/보안 부팅, 메모리, 저장 공간, CPU 기본 요구 사항을 확인합니다. |

또한 이 스크립트는:

- 실행 전후에 **보류 중인 재부팅**을 감지하고 자동으로 다시 시작할 수 있습니다(`-AutoReboot`).
- 각 단계를 독립적으로 실행합니다. 실패는 기록되고, 다음 단계는 계속 실행됩니다.
- **기록(transcript)**과 **JSON 보고서**를 `%ProgramData%\WindowsHealthAndUpdate\Logs`에 저장하고, 오래된 파일은 삭제합니다.
- `-WhatIf`와 `-Confirm`을 지원합니다.
- 자동화 도구가 이해하는 종료 코드를 반환합니다: `0` 성공, `1` 실패, `3010` 재부팅 필요.

## 지원하는 Windows 버전

스크립트는 실행 중인 시스템을 파악하고 그에 맞게 동작합니다. "n/a"로 표시된 단계는 이유를 알려 주고 건너뜁니다.

| 단계 | Windows 11 Home/Pro | Windows 11 Enterprise/Education | Windows 10 22H2 | Windows 10/11 LTSC | Windows Server 2016-2025 |
| --- | :---: | :---: | :---: | :---: | :---: |
| 지원 상태 확인 | 예 | 예 | 예 (ESU 안내) | 예 | 예 |
| RestorePoint | 예 | 예 | 예 | 예 | n/a |
| WinGet | 예 | 예 | 예 ¹ | 설치된 경우 ¹ | 설치된 경우 ¹ |
| Store | 예 | 예 | 예 | n/a | n/a |
| WindowsUpdate | 예 | 예 | 예 | 예 | 예 |
| Defender | 예 ² | 예 ² | 예 ² | 예 ² | 예 ² |
| Repair / Cleanup / DiskHealth | 예 | 예 | 예 | 예 | 예 |
| UpgradeReadiness | n/a | n/a | 예 | n/a | n/a |

¹ [앱 설치 관리자](https://aka.ms/getwinget)가 필요합니다. 없으면 이 단계를 건너뜁니다.
² Microsoft Defender가 활성 백신 프로그램인 경우에만 해당합니다.

### 지원 상태

지원 종료일은 Microsoft의 [Windows release health](https://learn.microsoft.com/windows/release-health/) 페이지를 기준으로 합니다(2026년 11월 확인). 해당 시점 기준:

| 버전 | 빌드 | Home/Pro | Enterprise/Education |
| --- | --- | --- | --- |
| Windows 11 26H2 | 26300 | 2028-10-10 | 2029-10-09 |
| Windows 11 26H1 (새 장치 전용) | 28000 | 2028-03-14 | 2029-03-13 |
| Windows 11 25H2 | 26200 | 2027-10-12 | 2028-10-10 |
| Windows 11 24H2 | 26100 | **2026-10-13 종료** | 2027-10-12 |
| Windows 11 23H2 이하 | 22631- | 종료 | 종료 |
| Windows 10 22H2 | 19045 | **2025-10-14 종료** (ESU만 해당) | 종료 (ESU만 해당) |

LTSC와 Windows Server 버전도 포함됩니다. 전체 표는 스크립트의 `Get-WindowsLifecycleData` 함수에 있습니다.

### 버전 감지 방식

레지스트리 값 `ProductName`은 Windows 11에서도 여전히 **"Windows 10"**으로 표시되므로 스크립트는 이 값에 의존하지 않습니다. `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion`에서 `CurrentBuild`, `UBR`, `DisplayVersion`, `EditionID`, `InstallationType`을 읽어 다음을 판단합니다.

- **제품군**: `InstallationType`이 `Server`/`Server Core`이면 Windows Server, 빌드 22000 이상이면 Windows 11, 그 외에는 Windows 10.
- **서비스 채널**: Home/Pro(24개월), Enterprise/Education(36개월), LTSC, IoT LTSC, Server. 어떤 지원 종료일이 적용되는지가 이것으로 결정됩니다. 예를 들어 빌드 26100은 Windows 11 24H2, Windows 11 LTSC 2024, Windows Server 2025 *중 하나*일 수 있으며, 각각 종료일이 다릅니다.

## 요구 사항

- Windows 10, Windows 11 또는 Windows Server 2016 이상
- Windows PowerShell 5.1(Windows 기본 제공) 또는 PowerShell 7 이상
- 관리자 권한으로 실행한 세션

## 빠른 시작

1. 저장소를 다운로드하거나 복제합니다. 예: `C:\Program Files\WindowsHealthAndUpdate`.
2. **Windows 터미널** 또는 **PowerShell**을 **관리자 권한으로** 엽니다.
3. 스크립트를 실행합니다. `-ExecutionPolicy Bypass`는 이 프로세스에만 적용되며 시스템 설정은 바꾸지 않습니다.

   ```powershell
   cd 'C:\Program Files\WindowsHealthAndUpdate'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WindowsMaintenance.ps1
   ```

   ZIP을 다운로드했다면 먼저 `Get-ChildItem -Recurse | Unblock-File`로 파일 차단을 해제할 수 있습니다.

아무것도 바꾸지 않고 수행될 작업만 확인하려면:

```powershell
.\Invoke-WindowsMaintenance.ps1 -WhatIf
```

## 사용법

```powershell
# 이 PC에 해당하는 모든 단계
.\Invoke-WindowsMaintenance.ps1

# 빠른 실행: DISM/SFC와 Defender 검사 생략
.\Invoke-WindowsMaintenance.ps1 -Skip Repair, Defender

# 업데이트만 하고, 필요하면 다시 시작
.\Invoke-WindowsMaintenance.ps1 -Only WinGet, WindowsUpdate -AutoReboot

# 드라이버를 포함하고 최신 Windows 11 버전으로 전환
.\Invoke-WindowsMaintenance.ps1 -IncludeDrivers -IncludeFeatureUpdates

# 로그를 바탕 화면에 저장
.\Invoke-WindowsMaintenance.ps1 -LogDirectory ([Environment]::GetFolderPath('Desktop'))

# 전체 도움말
Get-Help .\Invoke-WindowsMaintenance.ps1 -Detailed
```

| 매개 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `-Skip` | 없음 | 건너뛸 단계. |
| `-Only` | 전체 | 지정한 단계만 실행합니다. |
| `-IncludeDrivers` | 끔 | Windows 업데이트의 드라이버도 설치합니다. |
| `-IncludeFeatureUpdates` | 끔 | 기능 업데이트도 설치합니다(예: 24H2에서 25H2로). |
| `-AutoReboot` | 끔 | 필요하면 종료 2분 후 다시 시작합니다(`shutdown /a`로 취소). |
| `-TempFileAgeDays` | `2` | 이보다 오래된 임시 파일만 삭제합니다. |
| `-LogDirectory` | `%ProgramData%\WindowsHealthAndUpdate\Logs` | 기록과 JSON 보고서를 저장할 위치. |
| `-LogRetentionDays` | `30` | 이보다 오래된 로그와 보고서를 삭제합니다. |
| `-WhatIf` / `-Confirm` | | 실행 내용을 미리 보거나 단계마다 확인합니다. |

## 예약 실행

`Register-MaintenanceTask.ps1`은 작업 스케줄러에 작업을 만듭니다. 이 작업은 사용자 계정으로, 관리자 권한으로, 로그인해 있는 동안에만 실행되므로 암호를 저장하지 않습니다. 예약 시간에 PC가 꺼져 있었다면 가능한 한 빨리 실행됩니다.

```powershell
# 매주 일요일 10:00 (기본값)
.\Register-MaintenanceTask.ps1

# 매일 12:30에 업데이트만 실행
.\Register-MaintenanceTask.ps1 -Frequency Daily -At 12:30 -MaintenanceArguments '-Only WinGet, WindowsUpdate'

# 작업 제거
.\Register-MaintenanceTask.ps1 -Unregister
```

> **보안:** 이 작업은 스크립트를 관리자 권한으로 실행합니다. 일반 사용자가 수정할 수 없는 폴더(예: `C:\Program Files\...`)에 보관하세요. 그렇지 않으면 사용자 계정으로 실행되는 어떤 프로세스든 스크립트를 수정해 관리자 권한을 얻을 수 있습니다. 스크립트가 사용자 프로필 안에 있으면 등록 스크립트가 경고합니다.

## 로그와 보고서

실행할 때마다 로그 폴더에 두 개의 파일이 만들어집니다.

- `maintenance_<날짜_시간>.log`: PowerShell 기록.
- `maintenance_<날짜_시간>.json`: 시스템 정보, 지원 상태, 단계별 결과, 재부팅 필요 여부, 종료 코드를 담은 구조화된 보고서. 여러 PC에서 수집하거나 모니터링 도구로 보낼 수 있습니다.

Windows 업데이트의 경우 보고서에 **발견된 모든 업데이트**가 기록됩니다. 그래서 무인 실행 후에도 무엇이 설치되었고, 무엇이 실패했으며, 아직 다시 시작해야 하는지 알 수 있습니다.

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

- `Result`: `Installed`, `InstalledWithErrors`, `Failed`, `Aborted`, `DownloadFailed`, 또는 `Reason`(`Optional`, `FeatureUpdate`, `NeedsUserInput`)이 붙은 `NotInstalled`.
- `HResult`: Windows 업데이트 오류 코드입니다. [Windows 업데이트 오류 코드 목록](https://learn.microsoft.com/windows/deployment/update/windows-update-error-reference)에서 찾아볼 수 있습니다.
- `rebootScheduled`: `-AutoReboot`이 실제로 다시 시작을 예약한 경우에만 `true`입니다. `rebootRequired`만 `true`라면 다시 시작이 아직 대기 중이라는 뜻입니다.

최신 보고서 읽기:

```powershell
$latest = Get-ChildItem "$env:ProgramData\WindowsHealthAndUpdate\Logs\maintenance_*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
$report = Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json
$report.steps | Where-Object Step -eq 'WindowsUpdate' | Select-Object -ExpandProperty Details | Format-Table Title, KB, Result, HResult, RebootRequired
"Restart required: $($report.rebootRequired) (scheduled: $($report.rebootScheduled))"
```

> **종료 코드 `1`은 다시 시작이 대기 중이라는 뜻일 수도 있습니다.** 종료 코드 하나로 "실패"와 "다시 시작 필요"를 동시에 나타낼 수 없으므로 실패가 우선합니다. 보고서의 `rebootRequired`를 확인하세요.

DISM과 SFC는 각각 `%windir%\Logs\DISM\dism.log`와 `%windir%\Logs\CBS\CBS.log`에 자세한 로그를 남깁니다.

## 이 스크립트가 하지 않는 일

- 레지스트리 "튜닝", 앱 제거, 원격 분석(텔레메트리)이나 서비스 변경을 하지 않습니다.
- `DISM /ResetBase`를 사용하지 않습니다. 설치된 업데이트는 계속 제거할 수 있습니다.
- 사용자 파일, 다운로드 폴더, 휴지통을 삭제하지 않습니다. 임시 폴더만, 그것도 `-TempFileAgeDays`보다 오래된 파일만 정리합니다.
- 어떤 데이터도 외부로 보내지 않습니다.

## 개발

```powershell
# 단위 테스트 (Pester 5 이상)
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed

# 정적 분석
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

CI 워크플로는 **Windows Server 2022와 2025**에서 **Windows PowerShell 5.1과 PowerShell 7** 모두를 사용해 정적 분석, 단위 테스트, `-WhatIf` 스모크 테스트를 실행합니다.

스크립트 파일은 의도적으로 **ASCII 문자만** 사용합니다. Windows PowerShell 5.1은 BOM이 없는 파일을 ANSI 코드 페이지로 읽기 때문에 ASCII 이외의 문자가 있으면 스크립트가 깨집니다. 테스트로 이를 확인합니다.

## 기여하기

의견, 버그 보고, 번역을 환영합니다. 어떤 언어로 작성해도 괜찮습니다. [CONTRIBUTING.md](../CONTRIBUTING.md)를 참고하세요.

## 향후 계획

- JSON 보고서를 이메일, Teams, 웹훅으로 보내는 선택적 알림.
- Windows 11 준비 상태 검사에 호환 CPU 목록 추가.
- PowerShell Gallery 게시.

## 라이선스

[MIT](../LICENSE) © Carlos Alberto Nakazawa
