@echo off
rem ===========================================================================
rem  Stone_mode  -  build and run the KF concrete user material in OpenRadioss
rem
rem  This is the Fortran *userlib_sdk* route (starter routine LECMUSER01 +
rem  engine routine LUSER01), NOT the dynamic C user library route used by the
rem  sibling liruiw project.  See the step-by-step document in this folder.
rem
rem  Five steps:
rem    1/5  build the userlib_sdk static library      (skipped if already built)
rem    2/5  generate the two decks                    (make_deck.py)
rem    3/5  build the user library DLL                (build_userlib.bat)
rem    4/5  starter, both models
rem    5/5  engine, both models
rem
rem  Everything is written under Stone_mode\build_local\.  The Tools repository
rem  is read, never written.
rem
rem  Pure ASCII on purpose (cmd.exe reads .bat in the OEM codepage).
rem  Run from cmd.exe or by double-clicking, not from Git Bash.
rem ===========================================================================
setlocal
cd /d "%~dp0"

rem  ---- CONFIG - edit these when moving to a new machine --------------------
rem  Root of the MinGW-w64 toolchain (must contain bin\gcc.exe, bin\gfortran.exe).
rem  Same variable names as the sibling project, so one machine-wide setting
rem  serves both.  Overridable by environment variables of the same name.
if not defined KF_MINGW set "KF_MINGW=G:\x86_64-15.2.0-release-win32-seh-ucrt-rt_v13-rev0\mingw64"
rem  Root of the Tools repository (the sibling of the OpenRadioss repository).
if not defined KF_TOOLS set "KF_TOOLS=%~dp0..\..\Tools"
rem  -------------------------------------------------------------------------

for %%I in ("%~dp0..")    do set "REPO=%%~fI"
for %%I in ("%KF_TOOLS%") do set "TOOLS=%%~fI"
set "NINJA=%REPO%\extlib\build_mingw64\bin\ninja.exe"
rem  The SDK repository root is %TOOLS%\userlib_sdk.  Inside it there is ANOTHER
rem  userlib_sdk\ directory holding the per-arch build scripts and the prebuilt
rem  library slot (which ships empty).  Hence the doubled name in this path.
set "BUILDUSERLIB=%TOOLS%\userlib_sdk\userlib_sdk\win64_gfortran\build_userlib.bat"

set "OUT=%~dp0build_local"
set "SDKDIR=%OUT%\sdk"
set "DLLDIR=%OUT%\stone_dll"
set "DLL=%DLLDIR%\libraduser_win64.dll"

rem  ---- config sanity check -------------------------------------------------
if not exist "%KF_MINGW%\bin\gcc.exe" (
  echo [ERROR] MinGW toolchain not found: "%KF_MINGW%\bin\gcc.exe"
  echo         Edit the CONFIG block at the top of this script, or set KF_MINGW.
  exit /b 1
)
if not exist "%BUILDUSERLIB%" (
  echo [ERROR] build_userlib.bat not found: "%BUILDUSERLIB%"
  echo         Edit the CONFIG block at the top of this script, or set KF_TOOLS.
  exit /b 1
)

set "PATH=%KF_MINGW%\bin;%REPO%\extlib\build_mingw64;%PATH%"
set "RAD_CFG_PATH=%REPO%\hm_cfg_files"
rem  H3D writer library, needed by the /H3D cards in the engine deck.
set "RAD_H3D_PATH=%REPO%\extlib\h3d\lib\win64"
set "PATH=%RAD_H3D_PATH%;%PATH%"

echo ============================================================
echo  Step 1/5  userlib_sdk static library
echo ============================================================
call "%~dp0build_sdk.bat" nopause
if errorlevel 1 exit /b 1

echo.
echo ============================================================
echo  Step 2/5  Generate decks
echo ============================================================
python "%~dp0make_deck.py"
if errorlevel 1 exit /b 1

echo.
echo ============================================================
echo  Step 3/5  Build user library DLL
echo ============================================================
if not exist "%DLLDIR%" mkdir "%DLLDIR%"
pushd "%DLLDIR%"
rem  build_userlib.bat unpacks the static library into _obj_win64\, then compiles
rem  the user sources to SAME-NAMED .obj files in the same folder, so the user's
rem  routines replace the SDK's empty stubs of the same name.  That is why the
rem  file names must stay lecmuser01.f / luser01.f.
set "RAD_USERLIB_SDK_PATH=%SDKDIR%"
set "RAD_USERLIB_ARCH=win64_gfortran"
call "%BUILDUSERLIB%" /STARTER "..\..\LECMUSER01.f" /ENGINE "..\..\LUSER01.f"
if errorlevel 1 (
  popd
  echo [ERROR] user library build failed.
  exit /b 1
)
popd
if not exist "%DLL%" (
  echo [ERROR] user library was not produced: "%DLL%"
  exit /b 1
)
rem  Python/ctypes and any non-PATH loader need the MinGW runtime beside the DLL.
copy /y "%KF_MINGW%\bin\libgcc_s_seh-1.dll" "%DLLDIR%" >nul

call :run_model stone_kf    view_kf    "one brick"
if errorlevel 1 exit /b 1
call :run_model stone_axial view_axial "160 bricks"
if errorlevel 1 exit /b 1

echo.
echo ============================================================
echo  Done
echo ============================================================
echo  DLL        : %DLL%
echo.
echo  One brick  : %OUT%\view_kf\stone_kfA001
echo                (HyperView: File ^> Open ^> Results, RADIOSS (A) Result Reader)
echo  Axial      : %OUT%\view_axial\stone_axialA001
echo  Logs       : ^<rundir^>\starter.log , ^<rundir^>\engine.log
echo.
echo  Acceptance keywords:
echo    starter.log - "0 ERROR(S)" and "user01 solid kf concrete law"
echo    engine.log  - "NORMAL TERMINATION"
goto :done

rem ===========================================================================
rem  :run_model  <deck stem>  <output dir name>  <label>
rem ===========================================================================
:run_model
setlocal
set "STEM=%~1"
set "RUN=%OUT%\%~2"
echo.
echo ============================================================
echo  Starter + Engine  :  %STEM%  (%~3)
echo ============================================================
if not exist "%RUN%" mkdir "%RUN%"
copy /y "%~dp0deck\%STEM%_0000.rad" "%RUN%" >nul
copy /y "%~dp0deck\%STEM%_0001.rad" "%RUN%" >nul
pushd "%RUN%"
rem  Clean previous run: restart/screen files, animations, time histories, the
rem  starter scratch file, and the logs.
del /q *A[0-9][0-9][0-9] 2>nul
del /q *.rst *.h3d *T01 SI*.scr *.log *.out 2>nul

"%REPO%\exec\starter_win64_gf.exe" -i %STEM%_0000.rad -dylib "%DLL%" > starter.log 2>&1
echo  starter exit code : %errorlevel%
if not exist "%STEM%_0000_0001.rst" (
  echo  [ERROR] no restart file produced - see "%RUN%\starter.log"
  popd
  endlocal
  exit /b 1
)

"%REPO%\exec\engine_win64_gf.exe" -i %STEM%_0001.rad -dylib "%DLL%" -nthread 2 > engine.log 2>&1
echo  engine  exit code : %errorlevel%
echo  run dir           : %RUN%
popd
endlocal
exit /b 0

:done
rem  Double-clicked runs get a fresh console that closes on exit, so pause to
rem  let the summary above be read.  Automated runs pass "nopause".
set "NOPAUSE="
for %%A in (%*) do if /i "%%A"=="nopause" set "NOPAUSE=1"
if not defined NOPAUSE pause
endlocal
