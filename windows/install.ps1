<#
.SYNOPSIS
  Installs the dynamic sky wallpaper for the current user.

.DESCRIPTION
  Compiles the helper with the C# compiler that ships with Windows, saves
  your current wallpaper, and runs `sky tick` once: it renders today's frames
  for each monitor size, registers the SkyWallpaper scheduled task, and sets
  the current frame. Nothing stays running: the task starts a windowless
  helper at each switch time, and at 00:05 to render the new day.

  With -Latitude/-Longitude, sunrise and sunset follow your location every
  day, and the hourly forecast comes from Open-Meteo (one request a day,
  carrying the date and your coordinates rounded to 0.1 degrees, about
  10 km) unless -NoWeather. Without them, the fixed -Sunrise/-Sunset apply.

  No admin rights needed. uninstall.ps1 undoes everything and puts your
  previous wallpaper back.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File windows\install.ps1 -Latitude 48.2 -Longitude 16.4

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File windows\install.ps1 -Sunrise 07:20 -Sunset 17:55
#>
param(
    [double]$Latitude = [double]::NaN,
    [double]$Longitude = [double]::NaN,
    [switch]$NoWeather,
    [ValidatePattern('^\d{2}:\d{2}$')][string]$Sunrise = '07:20',
    [ValidatePattern('^\d{2}:\d{2}$')][string]$Sunset = '17:55',
    [int]$Seed = 7
)
$ErrorActionPreference = 'Stop'

$app = Join-Path $env:LOCALAPPDATA 'SkyWallpaper'
$sky = Join-Path $app 'sky.exe'
$located = -not ([double]::IsNaN($Latitude) -and [double]::IsNaN($Longitude))
if ($located -and ([double]::IsNaN($Latitude) -or [double]::IsNaN($Longitude))) { throw 'Give both -Latitude and -Longitude.' }

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

# What `sky tick` reads.
$inv = [Globalization.CultureInfo]::InvariantCulture
$config = @("seed=$Seed")
if ($located) {
    $config += 'lat=' + [Math]::Round($Latitude, 1).ToString($inv)
    $config += 'lon=' + [Math]::Round($Longitude, 1).ToString($inv)
    $config += 'weather=' + $(if ($NoWeather) { 'no' } else { 'yes' })
} else {
    $config += "sunrise=$Sunrise", "sunset=$Sunset"
}
Set-Content -Path (Join-Path $app 'config.txt') -Value $config -Encoding ASCII

# Remember the wallpapers from before the first install, for uninstall.ps1.
$previous = Join-Path $app 'previous.txt'
if (-not (Test-Path $previous)) {
    & $sky save $previous
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the current wallpapers.' }
}

# Render today, register the task, set the frame. --force: settings may have changed.
Remove-Item -Path (Join-Path $app 'task.txt') -ErrorAction SilentlyContinue
& $sky tick --force
if ($LASTEXITCODE -ne 0) { throw "Setting up failed; see $app\sky.log." }

Write-Host ''
Write-Host "Installed: task 'SkyWallpaper'. Frames and helper: $app"
if ($located) { Write-Host 'Sunrise and sunset follow your location; the day renders at 00:05.' }
