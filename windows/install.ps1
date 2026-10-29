<#
.SYNOPSIS
  Installs the dynamic sky wallpaper for the current user.

.DESCRIPTION
  Compiles the helper with the C# compiler that ships with Windows, saves
  your current wallpaper, and runs `sky tick` once: it renders today's frames
  for each monitor size, registers the SkyWallpaper scheduled task, and sets
  the current frame. Nothing stays running: the task starts a windowless
  helper at each switch time, and at 00:05 to render the new day.

  With a location, sunrise and sunset follow it every day, and the hourly
  forecast comes from Open-Meteo (one request a day, carrying the date and
  your coordinates rounded to 0.1 degrees, about 10 km) unless -NoWeather.
  Without one, the fixed -Sunrise/-Sunset apply. Run with no parameters and
  it asks for your town instead.

  No admin rights needed. uninstall.ps1 (also kept in
  %LOCALAPPDATA%\SkyWallpaper) undoes everything and puts your previous
  wallpaper back.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File windows\install.ps1

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
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# With nothing given on the command line, ask where you are, so sunrise,
# sunset and weather can follow it. The town is looked up once at
# open-meteo.com; only its coordinates, rounded to 0.1 degree, are kept.
$bound = $PSBoundParameters  # inside Where-Object, $PSBoundParameters would be the block's own
$given = @('Latitude', 'Longitude', 'Sunrise', 'Sunset') | Where-Object { $bound.ContainsKey($_) }
if (-not $given) {
    Write-Host 'Sky wallpaper: sunrise, sunset and weather can follow where you are.'
    Write-Host 'Your town is looked up once at open-meteo.com; only rounded coordinates are kept.'
    while ($true) {
        $town = Read-Host 'Your town or city (Enter to skip and use 07:20 / 17:55)'
        if (-not $town) { break }
        $found = $null
        try {
            $found = (Invoke-RestMethod -UseBasicParsing -Uri ('https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name=' + [uri]::EscapeDataString($town))).results
        } catch {
            Write-Host "Could not reach open-meteo.com: $($_.Exception.Message)"
        }
        if (-not $found) { Write-Host 'Not found. Try another spelling, or press Enter to skip.'; continue }
        $place = @($found)[0]
        $name = (@($place.name, $place.admin1, $place.country) | Where-Object { $_ } | Select-Object -Unique) -join ', '
        $answer = Read-Host ('Use {0} ({1:0.0}, {2:0.0})? [Y/n]' -f $name, $place.latitude, $place.longitude)
        if ($answer -notmatch '^[nN]') { $Latitude = $place.latitude; $Longitude = $place.longitude; break }
    }
    if (-not [double]::IsNaN($Latitude) -and -not $NoWeather) {
        $answer = Read-Host 'Show the hourly weather (one small request to open-meteo.com a day)? [Y/n]'
        if ($answer -match '^[nN]') { $NoWeather = $true }
    }
}

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
Copy-Item -Path (Join-Path $PSScriptRoot 'uninstall.ps1') -Destination $app -Force  # removal without the download

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
