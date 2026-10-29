# One-line install of the sky wallpaper. In PowerShell:
#
#   irm https://raw.githubusercontent.com/corpaci/sky-wallpaper/main/windows/get.ps1 | iex
#
# Downloads the repository from GitHub into a temporary folder, runs
# windows\install.ps1 (which asks for your town), then deletes the download.
# Everything installed lives in %LOCALAPPDATA%\SkyWallpaper; to remove it:
#
#   powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\SkyWallpaper\uninstall.ps1"

& {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('sky-wallpaper-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $zip = Join-Path $tmp 'sky-wallpaper.zip'
        Write-Host 'Downloading sky-wallpaper from GitHub...'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/corpaci/sky-wallpaper/archive/refs/heads/main.zip' -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $tmp
        # A child PowerShell, so the execution policy can't block the installer.
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tmp 'sky-wallpaper-main\windows\install.ps1')
        if ($LASTEXITCODE -ne 0) { Write-Host 'The install did not finish; see the messages above.' }
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}
