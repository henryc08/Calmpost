# Starts the backend, the Arduino bridge and the camera, each in its own window.
#
#     powershell -ExecutionPolicy Bypass -File start_all.ps1
#
# The app (emulator or APK) is run separately. Close a window to stop that
# service. Secrets are read from backend\.env at run time, never stored here.

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$backend = Join-Path $root 'backend'
$vision  = Join-Path $root 'vision'

function Test-Running($pattern) {
    [bool](Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
        Where-Object { $_.CommandLine -like $pattern })
}

# 1. Backend
if (Test-Running '*uvicorn*') {
    Write-Host 'backend already running'
} else {
    Start-Process powershell -WorkingDirectory $backend -ArgumentList '-NoExit', '-Command',
        "`$host.UI.RawUI.WindowTitle='Calmpost backend'; .\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000"
    Write-Host 'started backend  -> http://localhost:8000'
    Start-Sleep -Seconds 8   # let it apply migrations before the others connect
}

# 2. Sensor bridge (usually already started at login by the autostart)
if (Test-Running '*serial_bridge*') {
    Write-Host 'bridge already running'
} else {
    Start-Process powershell -WorkingDirectory $backend -ArgumentList '-NoExit', '-Command',
        ("`$host.UI.RawUI.WindowTitle='Calmpost bridge'; " +
         "`$tok = ((Get-Content .env | Select-String '^DEVICE_TOKEN=') -split '=',2)[1].Trim(); " +
         ".\.venv\Scripts\python.exe scripts\serial_bridge.py --api http://127.0.0.1:8000 --token `$tok")
    Write-Host 'started bridge'
}

# 3. Camera
if (Test-Running '*main.py*') {
    Write-Host 'vision already running'
} else {
    Start-Process powershell -WorkingDirectory $vision -ArgumentList '-NoExit', '-Command',
        "`$host.UI.RawUI.WindowTitle='Calmpost vision'; .\.venv\Scripts\python.exe main.py"
    Write-Host 'started vision   -> http://localhost:8081'
}
