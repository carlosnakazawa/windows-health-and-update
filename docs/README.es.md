# Windows Health & Update

[![CI](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml/badge.svg)](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml)
[![Licencia: MIT](https://img.shields.io/badge/licencia-MIT-blue.svg)](../LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Windows 10 | 11 | Server](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4)

[English](../README.md) | [Português (Brasil)](README.pt-BR.md) | **Español** | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [简体中文](README.zh-CN.md)

> Esta traducción puede estar desactualizada respecto a la [versión en inglés](../README.md), que es la referencia.

Script de mantenimiento en PowerShell que mantiene un PC con Windows actualizado y en buen estado con un solo comando: actualización de aplicaciones, Windows Update, Microsoft Defender, reparación de archivos del sistema, limpieza y estado de los discos.

**Detecta la versión exacta de Windows** (por ejemplo *Windows 11 Pro 25H2*, *Windows 10 Enterprise LTSC 2021* o *Windows Server 2022*), indica **si esa versión todavía recibe actualizaciones de seguridad** y **adapta cada paso** a ella.

## Funciones

| Paso | Qué hace |
| --- | --- |
| `RestorePoint` | Crea un punto de restauración antes de cualquier cambio. |
| `WinGet` | Actualiza en silencio las aplicaciones instaladas con `winget`. Encuentra winget aunque no esté en el `PATH` (cuenta SYSTEM u otro usuario administrador). |
| `Store` | Inicia la búsqueda de actualizaciones de las aplicaciones de Microsoft Store. |
| `WindowsUpdate` | Busca, descarga e **instala** actualizaciones mediante la API de Windows Update Agent. Los controladores y las actualizaciones de características son opcionales. |
| `Defender` | Actualiza las firmas de Microsoft Defender y ejecuta un examen rápido. Se omite si hay otro antivirus activo. |
| `Repair` | `DISM /RestoreHealth` seguido de `sfc /scannow`. |
| `Cleanup` | `DISM /StartComponentCleanup`, archivos temporales con más de N días de todos los perfiles locales y caché de Optimización de distribución. Informa del espacio liberado. |
| `DiskHealth` | Estado, temperatura, desgaste y errores de lectura de los discos, además del espacio libre de cada volumen. |
| `UpgradeReadiness` | Solo en Windows 10: comprueba TPM 2.0, UEFI/Arranque seguro, memoria, almacenamiento y los requisitos básicos de CPU para Windows 11. |

Además, el script:

- detecta un **reinicio pendiente** antes y después de la ejecución y puede reiniciar automáticamente (`-AutoReboot`);
- aísla cada paso: un fallo se registra y el siguiente paso se ejecuta igualmente;
- guarda una **transcripción** y un **informe JSON** en `%ProgramData%\WindowsHealthAndUpdate\Logs`, con retención;
- admite `-WhatIf` y `-Confirm`;
- devuelve códigos de salida que entienden las herramientas de automatización: `0` éxito, `1` fallo, `3010` reinicio necesario.

## Versiones de Windows compatibles

El script detecta en qué sistema se ejecuta y se ajusta. Los pasos marcados como "n/a" se omiten con una explicación.

| Paso | Windows 11 Home/Pro | Windows 11 Enterprise/Education | Windows 10 22H2 | Windows 10/11 LTSC | Windows Server 2016-2025 |
| --- | :---: | :---: | :---: | :---: | :---: |
| Estado de soporte | sí | sí | sí (aviso de ESU) | sí | sí |
| RestorePoint | sí | sí | sí | sí | n/a |
| WinGet | sí | sí | sí ¹ | si está instalado ¹ | si está instalado ¹ |
| Store | sí | sí | sí | n/a | n/a |
| WindowsUpdate | sí | sí | sí | sí | sí |
| Defender | sí ² | sí ² | sí ² | sí ² | sí ² |
| Repair / Cleanup / DiskHealth | sí | sí | sí | sí | sí |
| UpgradeReadiness | n/a | n/a | sí | n/a | n/a |

¹ Requiere el [Instalador de aplicación](https://aka.ms/getwinget). Si no está presente, el paso se omite.
² Solo cuando Microsoft Defender es el antivirus activo.

### Estado de soporte

Las fechas de fin de soporte proceden de las páginas [Windows release health](https://learn.microsoft.com/windows/release-health/) de Microsoft (revisadas en noviembre de 2026). En esa fecha:

| Versión | Compilación | Home/Pro | Enterprise/Education |
| --- | --- | --- | --- |
| Windows 11 26H2 | 26300 | 10/10/2028 | 09/10/2029 |
| Windows 11 26H1 (solo equipos nuevos) | 28000 | 14/03/2028 | 13/03/2029 |
| Windows 11 25H2 | 26200 | 12/10/2027 | 10/10/2028 |
| Windows 11 24H2 | 26100 | **finalizado el 13/10/2026** | 12/10/2027 |
| Windows 11 23H2 y anteriores | 22631- | finalizado | finalizado |
| Windows 10 22H2 | 19045 | **finalizado el 14/10/2025** (solo ESU) | finalizado (solo ESU) |

Las versiones LTSC y Windows Server también están incluidas. La tabla completa está en la función `Get-WindowsLifecycleData` del script.

### Cómo se detecta la versión

El valor de registro `ProductName` sigue diciendo **"Windows 10"** en Windows 11, así que el script no depende de él. Lee `CurrentBuild`, `UBR`, `DisplayVersion`, `EditionID` e `InstallationType` en `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` y deduce:

- la **familia**: Windows Server cuando `InstallationType` es `Server`/`Server Core`, Windows 11 a partir de la compilación 22000 y Windows 10 en los demás casos;
- el **canal de mantenimiento**: Home/Pro (24 meses), Enterprise/Education (36 meses), LTSC, IoT LTSC o Server. Es lo que determina qué fecha de fin se aplica. Por ejemplo, la compilación 26100 puede ser Windows 11 24H2, Windows 11 LTSC 2024 *o* Windows Server 2025, cada uno con una fecha distinta.

## Requisitos

- Windows 10, Windows 11 o Windows Server 2016+
- Windows PowerShell 5.1 (incluido en Windows) o PowerShell 7+
- Una sesión elevada (Ejecutar como administrador)

## Inicio rápido

1. Descarga o clona el repositorio, por ejemplo en `C:\Program Files\WindowsHealthAndUpdate`.
2. Abre **Windows Terminal** o **PowerShell** como **administrador**.
3. Ejecuta el script. `-ExecutionPolicy Bypass` solo afecta a este proceso y no cambia ninguna configuración del sistema:

   ```powershell
   cd 'C:\Program Files\WindowsHealthAndUpdate'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WindowsMaintenance.ps1
   ```

   Si descargaste el ZIP, puedes desbloquear los archivos antes con `Get-ChildItem -Recurse | Unblock-File`.

Para ver qué se haría, sin cambiar nada:

```powershell
.\Invoke-WindowsMaintenance.ps1 -WhatIf
```

## Uso

```powershell
# Todo lo que se aplica a este PC
.\Invoke-WindowsMaintenance.ps1

# Pasada rápida: sin DISM/SFC y sin el examen de Defender
.\Invoke-WindowsMaintenance.ps1 -Skip Repair, Defender

# Solo actualizaciones, reiniciando si hace falta
.\Invoke-WindowsMaintenance.ps1 -Only WinGet, WindowsUpdate -AutoReboot

# Incluir controladores y pasar a la última versión de Windows 11
.\Invoke-WindowsMaintenance.ps1 -IncludeDrivers -IncludeFeatureUpdates

# Guardar los registros en el escritorio
.\Invoke-WindowsMaintenance.ps1 -LogDirectory ([Environment]::GetFolderPath('Desktop'))

# Ayuda completa
Get-Help .\Invoke-WindowsMaintenance.ps1 -Detailed
```

| Parámetro | Valor predeterminado | Descripción |
| --- | --- | --- |
| `-Skip` | ninguno | Pasos que se omiten. |
| `-Only` | todos | Ejecuta solo estos pasos. |
| `-IncludeDrivers` | desactivado | Instala también controladores de Windows Update. |
| `-IncludeFeatureUpdates` | desactivado | Instala también actualizaciones de características (por ejemplo, de 24H2 a 25H2). |
| `-AutoReboot` | desactivado | Reinicia 2 minutos después de terminar si es necesario (`shutdown /a` lo cancela). |
| `-TempFileAgeDays` | `2` | Solo borra archivos temporales más antiguos que esto. |
| `-LogDirectory` | `%ProgramData%\WindowsHealthAndUpdate\Logs` | Dónde se guardan las transcripciones y los informes JSON. |
| `-LogRetentionDays` | `30` | Borra registros e informes más antiguos. |
| `-WhatIf` / `-Confirm` | | Simula la ejecución o pide confirmación en cada paso. |

## Programación

`Register-MaintenanceTask.ps1` crea una tarea en el Programador de tareas que se ejecuta con tu usuario, con privilegios elevados, solo mientras tienes la sesión iniciada, por lo que no se guarda ninguna contraseña. Si el PC estaba apagado a la hora programada, la tarea se ejecuta en cuanto sea posible.

```powershell
# Cada domingo a las 10:00 (predeterminado)
.\Register-MaintenanceTask.ps1

# Todos los días a las 12:30, solo actualizaciones
.\Register-MaintenanceTask.ps1 -Frequency Daily -At 12:30 -MaintenanceArguments '-Only WinGet, WindowsUpdate'

# Quitar la tarea
.\Register-MaintenanceTask.ps1 -Unregister
```

> **Seguridad:** la tarea ejecuta el script con privilegios de administrador. Guárdalo en una carpeta que los usuarios estándar no puedan modificar (como `C:\Program Files\...`). De lo contrario, cualquier proceso que se ejecute con tu usuario podría editar el script y obtener privilegios elevados. El script de registro te avisa si el archivo está dentro de tu perfil de usuario.

## Registros e informe

Cada ejecución crea dos archivos en la carpeta de registros:

- `maintenance_<fecha_hora>.log`: transcripción de PowerShell;
- `maintenance_<fecha_hora>.json`: informe estructurado con los datos del sistema, el estado de soporte, el resultado de cada paso, si hace falta reiniciar y el código de salida. Puedes recopilarlo de varios equipos o enviarlo a una herramienta de monitorización.

DISM y SFC guardan sus propios registros detallados en `%windir%\Logs\DISM\dism.log` y `%windir%\Logs\CBS\CBS.log`.

## Lo que el script no hace

- Ningún "ajuste" del registro, eliminación de aplicaciones ni cambios de telemetría o de servicios.
- No usa `DISM /ResetBase`: las actualizaciones instaladas se pueden seguir desinstalando.
- No borra archivos del usuario, Descargas ni la Papelera de reciclaje. Solo toca las carpetas temporales, y solo archivos más antiguos que `-TempFileAgeDays`.
- No envía datos a ningún sitio.

## Desarrollo

```powershell
# Pruebas unitarias (Pester 5+)
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed

# Análisis estático
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

El flujo de CI ejecuta el analizador, las pruebas unitarias y una prueba de humo con `-WhatIf` en **Windows Server 2022 y 2025**, tanto con **Windows PowerShell 5.1 como con PowerShell 7**.

Los scripts se mantienen **solo en ASCII** a propósito: Windows PowerShell 5.1 lee los archivos sin BOM con la página de códigos ANSI, y los caracteres acentuados romperían el script. Una prueba lo garantiza.

## Contribuir

Los comentarios, los informes de errores y las traducciones son bienvenidos, y puedes escribir en el idioma que prefieras. Consulta [CONTRIBUTING.md](../CONTRIBUTING.md).

## Próximos pasos

- Notificación opcional por correo electrónico, Teams o webhook con el informe JSON.
- Lista de CPU compatibles en la comprobación de preparación para Windows 11.
- Publicación en PowerShell Gallery.

## Licencia

[MIT](../LICENSE) © Carlos Alberto Nakazawa
