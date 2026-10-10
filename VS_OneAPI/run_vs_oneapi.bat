@echo off
setlocal
cd /d "%~dp0"
if "%~2"=="" (
  echo Usage: run_vs_oneapi.bat starter_input.rad engine_input.rad [threads]
  exit /b 2
)
for %%I in ("%~dp0..") do set "REPO=%%~fI"
set "THREADS=%~3"
if not defined THREADS set "THREADS=1"
set "DLL=%~dp0build_local\userlib_oneapi\libraduser_win64.dll"
set "STARTER_EXE=%RAD_STARTER_EXE%"
set "ENGINE_EXE=%RAD_ENGINE_EXE%"
if not defined STARTER_EXE set "STARTER_EXE=%REPO%\exec\starter_win64.exe"
if not defined ENGINE_EXE set "ENGINE_EXE=%REPO%\exec\engine_win64.exe"
if not exist "%STARTER_EXE%" if exist "%REPO%\exec\starter_win64_gf.exe" set "STARTER_EXE=%REPO%\exec\starter_win64_gf.exe"
if not exist "%ENGINE_EXE%" if exist "%REPO%\exec\engine_win64_gf.exe" set "ENGINE_EXE=%REPO%\exec\engine_win64_gf.exe"
if not exist "%STARTER_EXE%" (
  echo [ERROR] Starter executable not found. Set RAD_STARTER_EXE.
  exit /b 1
)
if not exist "%ENGINE_EXE%" (
  echo [ERROR] Engine executable not found. Set RAD_ENGINE_EXE.
  exit /b 1
)

call "%~dp0build_userlib.bat"
if errorlevel 1 exit /b 1

rem  The repository solver in exec\ is the gfortran build, so it needs the MinGW
rem  runtime DLLs on PATH. The ifx-built user library pulls in Intel runtime DLLs
rem  the same way, so oneAPI's bin goes on PATH too - without both, the solver
rem  exits 0xC0000135 (STATUS_DLL_NOT_FOUND) before printing anything.
if not defined KF_MINGW set "KF_MINGW=G:\x86_64-15.2.0-release-win32-seh-ucrt-rt_v13-rev0\mingw64"
if not defined KF_ONEAPI set "KF_ONEAPI=G:\One_API"

set "RAD_CFG_PATH=%REPO%\hm_cfg_files"
set "RAD_H3D_PATH=%REPO%\extlib\h3d\lib\win64"
set "RAD_USERLIB_LIBPATH=%~dp0build_local\userlib_oneapi"
set "PATH=%KF_MINGW%\bin;%KF_ONEAPI%\compiler\2026.1\bin;%RAD_H3D_PATH%;%REPO%\extlib\build_mingw64;%PATH%"
for %%F in ("%~1" "%~2") do if not exist "%%~fF" (
  echo [ERROR] Input file not found: "%%~fF"
  exit /b 1
)

rem  The solver writes its output beside the current directory, so run from a
rem  dedicated folder - otherwise the restart/animation/time-history files land
rem  in the repository root. The decks are passed by absolute path, so the
rem  working directory does not have to match them.
set "RUNDIR=%~dp0build_local\run"
if not exist "%RUNDIR%" mkdir "%RUNDIR%"
pushd "%RUNDIR%"

echo Running Starter
"%STARTER_EXE%" -i "%~f1" -dylib "%DLL%"
if errorlevel 1 (
  popd
  exit /b 1
)
echo Running Engine with %THREADS% thread(s)
"%ENGINE_EXE%" -i "%~f2" -dylib "%DLL%" -nthread %THREADS%
if errorlevel 1 (
  popd
  exit /b 1
)
popd
echo OpenRadioss calculation completed.  Results in "%RUNDIR%"
exit /b 0
