<#
.SYNOPSIS
  Installs the dynamic sky wallpaper for the current user.

.DESCRIPTION
  Compiles the helper with the C# compiler that ships with Windows, renders
  one frame set per monitor size, and registers a scheduled task that sets
  the right frame at each switch time, at logon, and after a switch missed
  during sleep. Nothing stays running: each switch starts a windowless
  helper that sets the wallpaper and exits. No admin rights needed.

  Re-run with new -Sunrise/-Sunset as the seasons move; uninstall.ps1 undoes
  everything and puts your previous wallpaper back.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File windows\install.ps1 -Sunrise 07:20 -Sunset 17:55
#>
param(
    [ValidatePattern('^\d{2}:\d{2}$')][string]$Sunrise = '07:20',
    [ValidatePattern('^\d{2}:\d{2}$')][string]$Sunset = '17:55',
    [int]$Seed = 7
)
$ErrorActionPreference = 'Stop'

$app = Join-Path $env:LOCALAPPDATA 'SkyWallpaper'
$sky = Join-Path $app 'sky.exe'
$taskName = 'SkyWallpaper'

# The C# 5 compiler that ships with .NET Framework 4.x, part of Windows 10 and 11.
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "No C# compiler at $csc (it ships with .NET Framework 4.x, part of Windows 10 and 11)." }

New-Item -ItemType Directory -Force -Path $app | Out-Null
$sources = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'src') -Filter '*.cs' | ForEach-Object { $_.FullName })
function Compile([string]$target, [string]$name) {
    & $csc /nologo /optimize+ /codepage:65001 "/target:$target" "/out:$(Join-Path $app $name)" $sources
    if ($LASTEXITCODE -ne 0) { throw "Compiling $name failed." }
}
Compile 'exe' 'sky.exe'           # console: for you and this script
Compile 'winexe' 'sky-apply.exe'  # windowless: for the scheduled task

# Remember the wallpapers from before the first install, for uninstall.ps1.
$previous = Join-Path $app 'previous.txt'
if (-not (Test-Path $previous)) {
    & $sky save $previous
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the current wallpapers.' }
}

# A fresh folder per install: Windows caches wallpapers by path, so reusing
# one would keep showing the old frames.
$frames = Join-Path $app ('frames-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
& $sky render --sunrise $Sunrise --sunset $Sunset --seed $Seed --out $frames
if ($LASTEXITCODE -ne 0) { throw 'Rendering failed.' }

$times = @(& $sky schedule $frames)
if ($LASTEXITCODE -ne 0 -or $times.Count -eq 0) { throw 'Could not read the schedule.' }

$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$triggers = @($times | ForEach-Object { New-ScheduledTaskTrigger -Daily -At $_ })

# Catch up whenever the desktop comes back. A switch time missed during sleep
# is not reliably re-run on wake, so the frame from before sleep would stay.
$logon = New-ScheduledTaskTrigger -AtLogOn -User $me
$logon.Delay = 'PT30S'  # let Explorer start first
$triggers += $logon
$cim = 'Root/Microsoft/Windows/TaskScheduler'
$triggers += New-CimInstance -ClientOnly -CimClass (Get-CimClass -Namespace $cim -ClassName MSFT_TaskSessionStateChangeTrigger) `
    -Property @{ StateChange = 8; UserId = $me }  # 8 = session unlock
$wake = New-CimInstance -ClientOnly -CimClass (Get-CimClass -Namespace $cim -ClassName MSFT_TaskEventTrigger)
$wake.Enabled = $true
# Resume from sleep, and leaving Modern Standby.
$wake.Subscription = @'
<QueryList><Query Id="0" Path="System">
<Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]</Select>
<Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=507]]</Select>
</Query></QueryList>
'@

$action = New-ScheduledTaskAction -Execute ('"' + (Join-Path $app 'sky-apply.exe') + '"') -Argument ('apply "' + $frames + '"')
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
function Register-SkyTask([object[]]$with) {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $with -Settings $settings -Principal $principal `
        -Description 'Sets the sky wallpaper frame for the time of day, then exits.' -Force | Out-Null
}
try {
    Register-SkyTask ($triggers + $wake)
} catch {
    # Event triggers can be refused on locked-down machines; unlock and logon still catch up.
    Write-Warning "No wake trigger ($($_.Exception.Message)); the frame catches up at unlock instead."
    Register-SkyTask $triggers
}

& $sky apply $frames
if ($LASTEXITCODE -ne 0) { throw "Setting the wallpaper failed; see $app\sky.log." }

# Older frame sets are no longer referenced by the task or the desktop.
Get-ChildItem -Path $app -Directory -Filter 'frames-*' | Where-Object { $_.FullName -ne $frames } | Remove-Item -Recurse -Force

Write-Host ''
Write-Host "Installed: $($times.Count) switches a day ($($times -join ' ')), task '$taskName'."
Write-Host "Frames and helper: $app"
