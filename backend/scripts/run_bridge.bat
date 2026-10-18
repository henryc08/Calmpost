@echo off
REM ---------------------------------------------------------------------------
REM Keeps the Arduino -> backend bridge running without anyone typing a command.
REM
REM Started at login by bridge_autostart.vbs (see install_bridge_autostart.ps1),
REM so there is no terminal to leave open and nothing to remember after a
REM reboot. Readings stopped overnight once already because this was a manual
REM step; that is the whole reason this file exists.
REM
REM The loop matters as much as the autostart: the bridge exits when the board
REM is unplugged, when COM3 is held by the Arduino IDE's serial monitor, or
REM when the laptop sleeps. Restarting every few seconds means plugging the
REM board back in is enough to resume, with no human in the loop.
REM
REM The device token is read from backend/.env at run time rather than written
REM in here, so this file carries no secret and is safe to commit.
REM ---------------------------------------------------------------------------

setlocal enabledelayedexpansion

REM scripts\ -> backend\ -> repo root
set "SCRIPTS=%~dp0"
set "BACKEND=%SCRIPTS%.."
set "PY=%BACKEND%\.venv\Scripts\python.exe"
set "BRIDGE=%SCRIPTS%serial_bridge.py"
set "ENVFILE=%BACKEND%\.env"
set "LOG=%BACKEND%\bridge.log"

if not exist "%PY%" (
    echo [%date% %time%] backend venv missing at %PY% >> "%LOG%"
    exit /b 1
)
if not exist "%ENVFILE%" (
    echo [%date% %time%] backend\.env missing, cannot read DEVICE_TOKEN >> "%LOG%"
    exit /b 1
)

REM Pull DEVICE_TOKEN out of .env. tokens=1,* keeps any '=' inside the value.
set "DEVICE_TOKEN="
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ENVFILE%") do (
    if /i "%%A"=="DEVICE_TOKEN" set "DEVICE_TOKEN=%%B"
)
if not defined DEVICE_TOKEN (
    echo [%date% %time%] DEVICE_TOKEN not set in backend\.env >> "%LOG%"
    exit /b 1
)

echo [%date% %time%] bridge autostart beginning >> "%LOG%"

:loop
REM No --port: the bridge finds the board itself, so a different COM number
REM after a replug still works.
"%PY%" "%BRIDGE%" --api http://127.0.0.1:8000 --token "%DEVICE_TOKEN%" >> "%LOG%" 2>&1
echo [%date% %time%] bridge exited (code %errorlevel%), retrying in 5s >> "%LOG%"
timeout /t 5 /nobreak >nul
goto loop
