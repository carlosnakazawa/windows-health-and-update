# Windows Health & Update

[![CI](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml/badge.svg)](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml)
[![Licença: MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-blue.svg)](../LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Windows 10 | 11 | Server](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4)

[English](../README.md) | **Português (Brasil)** | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-CN.md)

> Esta tradução pode estar desatualizada em relação à [versão em inglês](../README.md), que é a referência.

Script de manutenção em PowerShell que deixa um PC com Windows atualizado e saudável com um único comando: atualização de aplicativos, Windows Update, Microsoft Defender, reparo de arquivos do sistema, limpeza e saúde dos discos.

Ele **identifica a versão exata do Windows** (por exemplo *Windows 11 Pro 25H2*, *Windows 10 Enterprise LTSC 2021* ou *Windows Server 2022*), informa **se essa versão ainda recebe atualizações de segurança** e **adapta cada etapa** a ela.

## Funcionalidades

| Etapa | O que faz |
| --- | --- |
| `RestorePoint` | Cria um ponto de restauração antes de qualquer alteração. |
| `WinGet` | Atualiza os aplicativos instalados com `winget`, em modo silencioso. Encontra o winget mesmo fora do `PATH` (conta SYSTEM ou outro usuário administrador). |
| `Store` | Dispara a verificação de atualizações dos apps da Microsoft Store. |
| `WindowsUpdate` | Procura, baixa e **instala** atualizações pela API do Windows Update Agent. Drivers e atualizações de recurso são opcionais. |
| `Defender` | Atualiza as definições do Microsoft Defender e executa uma verificação rápida. É ignorada quando outro antivírus está ativo. |
| `Repair` | `DISM /RestoreHealth` seguido de `sfc /scannow`. |
| `Cleanup` | `DISM /StartComponentCleanup`, arquivos temporários com mais de N dias de todos os perfis locais e cache do Delivery Optimization. Informa o espaço liberado. |
| `DiskHealth` | Saúde, temperatura, desgaste e erros de leitura dos discos, além do espaço livre por volume. |
| `UpgradeReadiness` | Somente no Windows 10: verifica TPM 2.0, UEFI/Secure Boot, memória, armazenamento e requisitos básicos de CPU para o Windows 11. |

Além disso, o script:

- detecta **reinicialização pendente** antes e depois da execução e pode reiniciar sozinho (`-AutoReboot`);
- isola cada etapa: uma falha é registrada e a próxima etapa continua;
- grava uma **transcrição** e um **relatório JSON** em `%ProgramData%\WindowsHealthAndUpdate\Logs`, com retenção;
- suporta `-WhatIf` e `-Confirm`;
- retorna códigos de saída que ferramentas de automação entendem: `0` sucesso, `1` falha, `3010` reinicialização necessária.

## Versões do Windows suportadas

O script identifica onde está rodando e se ajusta. Etapas marcadas como "n/a" são ignoradas com uma explicação.

| Etapa | Windows 11 Home/Pro | Windows 11 Enterprise/Education | Windows 10 22H2 | Windows 10/11 LTSC | Windows Server 2016-2025 |
| --- | :---: | :---: | :---: | :---: | :---: |
| Status de suporte | sim | sim | sim (aviso de ESU) | sim | sim |
| RestorePoint | sim | sim | sim | sim | n/a |
| WinGet | sim | sim | sim ¹ | se instalado ¹ | se instalado ¹ |
| Store | sim | sim | sim | n/a | n/a |
| WindowsUpdate | sim | sim | sim | sim | sim |
| Defender | sim ² | sim ² | sim ² | sim ² | sim ² |
| Repair / Cleanup / DiskHealth | sim | sim | sim | sim | sim |
| UpgradeReadiness | n/a | n/a | sim | n/a | n/a |

¹ Requer o [Instalador de Aplicativo](https://aka.ms/getwinget). Se não estiver presente, a etapa é ignorada.
² Apenas quando o Microsoft Defender é o antivírus ativo.

### Status de suporte

As datas de fim de suporte vêm das páginas [Windows release health](https://learn.microsoft.com/windows/release-health/) da Microsoft (revisadas em novembro de 2026). Nessa data:

| Versão | Build | Home/Pro | Enterprise/Education |
| --- | --- | --- | --- |
| Windows 11 26H2 | 26300 | 10/10/2028 | 09/10/2029 |
| Windows 11 26H1 (apenas dispositivos novos) | 28000 | 14/03/2028 | 13/03/2029 |
| Windows 11 25H2 | 26200 | 12/10/2027 | 10/10/2028 |
| Windows 11 24H2 | 26100 | **encerrado em 13/10/2026** | 12/10/2027 |
| Windows 11 23H2 e anteriores | 22631- | encerrado | encerrado |
| Windows 10 22H2 | 19045 | **encerrado em 14/10/2025** (apenas ESU) | encerrado (apenas ESU) |

As versões LTSC e Windows Server também estão cobertas. A tabela completa está na função `Get-WindowsLifecycleData`, no script.

### Como a versão é detectada

O valor de registro `ProductName` continua dizendo **"Windows 10"** no Windows 11, por isso o script não depende dele. Ele lê `CurrentBuild`, `UBR`, `DisplayVersion`, `EditionID` e `InstallationType` em `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` e deduz:

- a **família**: Windows Server quando `InstallationType` é `Server`/`Server Core`, Windows 11 a partir do build 22000, e Windows 10 nos demais casos;
- a **trilha de manutenção**: Home/Pro (24 meses), Enterprise/Education (36 meses), LTSC, IoT LTSC ou Server. É ela que define qual data de fim vale. Por exemplo, o build 26100 pode ser o Windows 11 24H2, o Windows 11 LTSC 2024 *ou* o Windows Server 2025, cada um com uma data diferente.

## Requisitos

- Windows 10, Windows 11 ou Windows Server 2016+
- Windows PowerShell 5.1 (já incluído no Windows) ou PowerShell 7+
- Sessão elevada (Executar como administrador)

## Início rápido

1. Baixe ou clone o repositório, por exemplo em `C:\Program Files\WindowsHealthAndUpdate`.
2. Abra o **Terminal do Windows** ou o **PowerShell** como **Administrador**.
3. Execute o script. O `-ExecutionPolicy Bypass` vale só para este processo e não altera nenhuma configuração do sistema:

   ```powershell
   cd 'C:\Program Files\WindowsHealthAndUpdate'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WindowsMaintenance.ps1
   ```

   Se você baixou o ZIP, pode desbloquear os arquivos antes com `Get-ChildItem -Recurse | Unblock-File`.

Para ver o que seria feito, sem alterar nada:

```powershell
.\Invoke-WindowsMaintenance.ps1 -WhatIf
```

## Uso

```powershell
# Tudo o que se aplica a este PC
.\Invoke-WindowsMaintenance.ps1

# Execução rápida: sem DISM/SFC e sem a verificação do Defender
.\Invoke-WindowsMaintenance.ps1 -Skip Repair, Defender

# Somente atualizações, reiniciando se necessário
.\Invoke-WindowsMaintenance.ps1 -Only WinGet, WindowsUpdate -AutoReboot

# Incluir drivers e migrar para a versão mais recente do Windows 11
.\Invoke-WindowsMaintenance.ps1 -IncludeDrivers -IncludeFeatureUpdates

# Salvar os logs na Área de Trabalho
.\Invoke-WindowsMaintenance.ps1 -LogDirectory ([Environment]::GetFolderPath('Desktop'))

# Ajuda completa
Get-Help .\Invoke-WindowsMaintenance.ps1 -Detailed
```

| Parâmetro | Padrão | Descrição |
| --- | --- | --- |
| `-Skip` | nenhum | Etapas a ignorar. |
| `-Only` | todas | Executa só estas etapas. |
| `-IncludeDrivers` | desligado | Instala também drivers do Windows Update. |
| `-IncludeFeatureUpdates` | desligado | Instala também atualizações de recurso (por exemplo, 24H2 para 25H2). |
| `-AutoReboot` | desligado | Reinicia 2 minutos após o fim, se necessário (`shutdown /a` cancela). |
| `-TempFileAgeDays` | `2` | Só apaga arquivos temporários mais antigos que isso. |
| `-LogDirectory` | `%ProgramData%\WindowsHealthAndUpdate\Logs` | Onde ficam as transcrições e os relatórios JSON. |
| `-LogRetentionDays` | `30` | Apaga logs e relatórios mais antigos. |
| `-WhatIf` / `-Confirm` | | Simula a execução, ou pede confirmação a cada etapa. |

## Agendamento

O `Register-MaintenanceTask.ps1` cria uma tarefa no Agendador de Tarefas que roda com o seu usuário, elevada, apenas enquanto você está conectado, então nenhuma senha é armazenada. Se o PC estiver desligado no horário marcado, a tarefa roda assim que possível.

```powershell
# Todo domingo às 10:00 (padrão)
.\Register-MaintenanceTask.ps1

# Todos os dias às 12:30, só atualizações
.\Register-MaintenanceTask.ps1 -Frequency Daily -At 12:30 -MaintenanceArguments '-Only WinGet, WindowsUpdate'

# Remover a tarefa
.\Register-MaintenanceTask.ps1 -Unregister
```

> **Segurança:** a tarefa executa o script com privilégios de administrador. Mantenha-o numa pasta que usuários comuns não podem alterar (como `C:\Program Files\...`). Caso contrário, qualquer processo rodando com o seu usuário poderia editar o script e obter elevação. O script de registro avisa quando o arquivo está dentro do seu perfil de usuário.

## Logs e relatório

Cada execução cria dois arquivos na pasta de logs:

- `maintenance_<data_hora>.log`: transcrição do PowerShell;
- `maintenance_<data_hora>.json`: relatório estruturado com detalhes do sistema, status de suporte, resultado de cada etapa, necessidade de reinicialização e código de saída. Dá para coletá-lo de várias máquinas ou enviá-lo a uma ferramenta de monitoramento.

No Windows Update, o relatório lista **cada atualização encontrada**. Assim, depois de uma execução sem supervisão, dá para saber o que foi instalado, o que falhou e se ainda falta reiniciar:

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

- `Result`: `Installed`, `InstalledWithErrors`, `Failed`, `Aborted`, `DownloadFailed`, ou `NotInstalled` com um `Reason` (`Optional`, `FeatureUpdate`, `NeedsUserInput`).
- `HResult`: o código de erro do Windows Update, para consultar nos [códigos de erro do Windows Update](https://learn.microsoft.com/windows/deployment/update/windows-update-error-reference).
- `rebootScheduled`: `true` só quando o `-AutoReboot` de fato agendou a reinicialização; `rebootRequired` sozinho significa que ela ainda está pendente.

Para ler o relatório mais recente:

```powershell
$latest = Get-ChildItem "$env:ProgramData\WindowsHealthAndUpdate\Logs\maintenance_*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
$report = Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json
$report.steps | Where-Object Step -eq 'WindowsUpdate' | Select-Object -ExpandProperty Details | Format-Table Title, KB, Result, HResult, RebootRequired
"Restart required: $($report.rebootRequired) (scheduled: $($report.rebootScheduled))"
```

> **O código de saída `1` também pode significar reinicialização pendente.** Um único código não consegue dizer "algo falhou" e "precisa reiniciar" ao mesmo tempo, então a falha prevalece. Confira `rebootRequired` no relatório.

O DISM e o SFC mantêm seus próprios logs detalhados em `%windir%\Logs\DISM\dism.log` e `%windir%\Logs\CBS\CBS.log`.

## O que o script não faz

- Nenhum "tweak" de registro, remoção de apps, mudança de telemetria ou de serviços.
- Não usa `DISM /ResetBase`: as atualizações instaladas continuam podendo ser desinstaladas.
- Não apaga arquivos do usuário, Downloads nem a Lixeira. Só mexe nas pastas temporárias, e apenas em arquivos mais antigos que `-TempFileAgeDays`.
- Não envia dados para lugar nenhum.

## Desenvolvimento

```powershell
# Testes unitários (Pester 5+)
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed

# Análise estática
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

O workflow de CI roda o analisador, os testes unitários e um teste de fumaça com `-WhatIf` no **Windows Server 2022 e 2025**, tanto no **Windows PowerShell 5.1 quanto no PowerShell 7**.

Os scripts são mantidos **somente em ASCII** de propósito: o Windows PowerShell 5.1 lê arquivos sem BOM com a página de código ANSI, e caracteres acentuados quebrariam o script. Um teste garante isso.

## Contribuindo

Comentários, relatos de bugs e traduções são bem-vindos, em qualquer idioma. Veja o [CONTRIBUTING.md](../CONTRIBUTING.md).

## Próximos passos

- Notificação opcional por e-mail, Teams ou webhook com o relatório JSON.
- Lista de CPUs compatíveis na verificação de prontidão para o Windows 11.
- Publicação na PowerShell Gallery.

## Licença

[MIT](../LICENSE) © Carlos Alberto Nakazawa
