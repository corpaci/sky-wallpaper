<#
.SYNOPSIS
  Removes the sky wallpaper: the scheduled tasks, the helper and the frames,
  and puts back the wallpapers from before the first install.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File windows\uninstall.ps1
#>
$ErrorActionPreference = 'Stop'

$app = Join-Path $env:LOCALAPPDATA 'SkyWallpaper'
$sky = Join-Path $app 'sky.exe'
$previous = Join-Path $app 'previous.txt'

foreach ($task in 'SkyWallpaperFollow', 'SkyWallpaper') {
    if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $task -Confirm:$false
    }
}
# Anything still running from here (a tick the follower started) holds files open.
Get-Process -Name 'sky-apply', 'sky' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($app, [StringComparison]::OrdinalIgnoreCase) } |
    Stop-Process -Force -ErrorAction SilentlyContinue
if ((Test-Path $sky) -and (Test-Path $previous)) {
    & $sky restore $previous
}
if (Test-Path $app) {
    Remove-Item -Path $app -Recurse -Force
}
Write-Host 'Sky wallpaper removed.'
