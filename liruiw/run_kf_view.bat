@echo off
rem ===========================================================================
rem  Run the KF LAW99 test case from the reference project with post-processing
rem  output enabled, so the results can be opened in HyperView.
rem
rem  Uses view_kf\kf_law99_0000.rad (byte-identical copy of the project's
rem  starter deck) and view_kf\kf_law99_0001.rad (the project's engine deck plus
rem  /ANIM/VECT/DIS and /H3D cards).  Model and material are unchanged.
rem
rem  Pure ASCII on purpose (cmd.exe reads .bat in the OEM codepage).
rem  Run from cmd.exe or by double-clicking, not from Git Bash.
rem ===========================================================================
setlocal
cd /d "%~dp0"

rem  ---- CONFIG - edit these when moving to a new machine --------------------
if not defined KF_MINGW set "KF_MINGW=G:\x86_64-15.2.0-release-win32-seh-ucrt-rt_v13-rev0\mingw64"
if not defined KF_REPO  set "KF_REPO=%~dp0.."
if not defined HW14_HOME set "HW14_HOME=G:\Program Files\hyperwork"
rem  HyperWorks 14 (2015) mishandles non-ASCII paths - it fails to load results
rem  that live under a folder whose name has Chinese characters.  Results are
rem  therefore mirrored to this ASCII-only folder for viewing.
if not defined KF_VIEW_OUT set "KF_VIEW_OUT=%USERPROFILE%\kf_view_out"
rem  -------------------------------------------------------------------------

for %%I in ("%KF_REPO%") do set "REPO=%%~fI"
set "NINJA=%REPO%\extlib\build_mingw64\bin\ninja.exe"
set "KFSRC=%~dp0examples\userlib\kf_law99"

if not exist "%KF_MINGW%\bin\gcc.exe" (
  echo [ERROR] MinGW toolchain not found: "%KF_MINGW%\bin\gcc.exe"
  exit /b 1
)

set "PATH=%REPO%\extlib\build_mingw64;%KF_MINGW%\bin;%PATH%"
set "RAD_CFG_PATH=%REPO%\hm_cfg_files"
rem  H3D writer library (Altair-proprietary), needed by the /H3D cards.
set "RAD_H3D_PATH=%REPO%\extlib\h3d\lib\win64"
set "PATH=%RAD_H3D_PATH%;%PATH%"

set "OUT=%~dp0build_local"
set "DLLDIR=%OUT%\kf_dll"
set "DLL=%DLLDIR%\libraduser_win64.dll"
set "RUN=%OUT%\view_kf"

echo ============================================================
echo  Step 1/3  Build KF LAW99 user library
echo ============================================================
if not exist "%DLL%" (
  cmake -S "%KFSRC%" -B "%DLLDIR%" -G Ninja -DCMAKE_MAKE_PROGRAM="%NINJA%" -DCMAKE_BUILD_TYPE=Release
  if errorlevel 1 exit /b 1
  cmake --build "%DLLDIR%"
  if errorlevel 1 exit /b 1
)
copy /y "%KF_MINGW%\bin\libgcc_s_seh-1.dll" "%DLLDIR%" >nul
if not exist "%DLL%" (
  echo [ERROR] user library not produced: "%DLL%"
  exit /b 1
)

if not exist "%RUN%" mkdir "%RUN%"
copy /y "%~dp0view_kf\kf_law99_0000.rad" "%RUN%" >nul
copy /y "%~dp0view_kf\kf_law99_0001.rad" "%RUN%" >nul
cd /d "%RUN%"
del /q kf_law99_0000_0001.rst kf_law99_0001_0001.rst 2>nul
del /q kf_law99A* kf_law99.h3d kf_law99T01 2>nul

echo.
echo ============================================================
echo  Step 2/3  Starter
echo ============================================================
"%REPO%\exec\starter_win64_gf.exe" -i kf_law99_0000.rad -dylib "%DLL%" > starter.log 2>&1
echo STARTER_EXIT=%errorlevel%
if not exist kf_law99_0000_0001.rst (
  echo [ERROR] no restart file - see "%RUN%\starter.log"
  goto :done
)

echo.
echo ============================================================
echo  Step 3/3  Engine
echo ============================================================
"%REPO%\exec\engine_win64_gf.exe" -i kf_law99_0001.rad -dylib "%DLL%" -nthread 2 > engine.log 2>&1
echo ENGINE_EXIT=%errorlevel%

echo.
echo ============================================================
echo  Step 4/4  Mirror results to an ASCII-only path
echo ============================================================
rem  HyperWorks 14 cannot load results from a path containing Chinese
rem  characters, so copy them somewhere ASCII-clean for viewing.
if not exist "%KF_VIEW_OUT%" mkdir "%KF_VIEW_OUT%"
copy /y kf_law99A* "%KF_VIEW_OUT%" >nul
copy /y kf_law99.h3d "%KF_VIEW_OUT%" >nul 2>&1
copy /y kf_law99T01 "%KF_VIEW_OUT%" >nul 2>&1
echo Mirrored to: %KF_VIEW_OUT%

echo.
echo  Run dir   : %RUN%
echo  OPEN THIS : %KF_VIEW_OUT%\kf_law99A001
echo              (HyperView: File ^> Open ^> Results; pick RADIOSS (A) Result Reader)
echo  H3D       : kf_law99.h3d (needs a newer HyperWorks; v24 format)
echo  Logs      : %RUN%\starter.log / engine.log

:done
if /i not "%~1"=="nopause" pause
endlocal
