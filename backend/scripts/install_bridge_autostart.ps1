# ---------------------------------------------------------------------------
# Makes the Arduino bridge start by itself at login, with no terminal window.
#
#     powershell -ExecutionPolicy Bypass -File install_bridge_autostart.ps1
#     powershell -ExecutionPolicy Bypass -File install_bridge_autostart.ps1 -Uninstall
#
# Uses the per-user Startup folder rather than Task Scheduler or a service,
# because those need an administrator and this does not. A tiny .vbs launches
# run_bridge.bat with the window hidden, so nothing flashes up at login and
# there is no console anyone can close by accident.
#
# Readings stop the moment the bridge stops, and it had been a manual command
# in a terminal that nobody restarts after a reboot.
# ---------------------------------------------------------------------------

param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'

$scripts  = Split-Path -Parent $MyInvocation.MyCommand.Path
$bat      = Join-Path $scripts 'run_bridge.bat'
$startup  = [Environment]::GetFolderPath('Startup')
$launcher = Join-Path $startup 'CalmpostBridge.vbs'

if ($Uninstall) {
    if (Test-Path $launcher) {
        Remove-Item $launcher -Force
        Write-Host "Removed autostart: $launcher"
    } else {
        Write-Host "Nothing to remove; $launcher does not exist."
    }
    Write-Host "Any bridge already running keeps running until you close it."
    return
}

if (-not (Test-Path $bat)) { throw "run_bridge.bat not found next to this script ($bat)" }

# 0 = hidden window, $false = do not wait. The quoting matters: the repo path
# contains spaces.
$vbs = @"
' Launches the Calmpost Arduino bridge at login with no visible window.
' Created by backend\scripts\install_bridge_autostart.ps1 -- remove it with
' that same script's -Uninstall switch, or just delete this file.
CreateObject("WScript.Shell").Run """$bat""", 0, False
"@

Set-Content -Path $launcher -Value $vbs -Encoding ASCII
Write-Host "Installed autostart:"
Write-Host "  launcher : $launcher"
Write-Host "  runs     : $bat"
Write-Host "  log      : $(Join-Path (Split-Path -Parent $scripts) 'bridge.log')"
Write-Host ""
Write-Host "It starts at every login. To start it now without logging out:"
Write-Host "  wscript `"$launcher`""
