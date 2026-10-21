<#
.SYNOPSIS
  Removes the sky wallpaper: the scheduled task, the helper and the frames,
  and puts back the wallpapers from before the first install.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File windows\uninstall.ps1
#>
$ErrorActionPreference = 'Stop'

$app = Join-Path $env:LOCALAPPDATA 'SkyWallpaper'
$sky = Join-Path $app 'sky.exe'
$previous = Join-Path $app 'previous.txt'

if (Get-ScheduledTask -TaskName 'SkyWallpaper' -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName 'SkyWallpaper' -Confirm:$false
}
if ((Test-Path $sky) -and (Test-Path $previous)) {
    & $sky restore $previous
}
if (Test-Path $app) {
    Remove-Item -Path $app -Recurse -Force
}
Write-Host 'Sky wallpaper removed.'
