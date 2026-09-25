echo off

setlocal
rem create OpenRadioss_GUI folder in AppData : settings and cache will be stored here
if not exist C:\Users\%USERNAME%\AppData\Local\OpenRadioss_GUI (
    mkdir C:\Users\%USERNAME%\AppData\Local\OpenRadioss_GUI
)
set PYTHONPYCACHEPREFIX=C:\Users\%USERNAME%\AppData\Local\OpenRadioss_GUI\__pycache__

set SCRIPT_DIR=%~dp0
python %SCRIPT_DIR%OpenRadioss_gui.py %*

rem Keep the console open if python failed, so the error is readable
rem instead of the window disappearing instantly.
if errorlevel 1 (
    echo.
    echo *** OpenRadioss GUI exited with an error - see the message above ***
    pause
)

set PYTHONPYCACHEPREFIX=
endlocal