@echo off
rem ===========================================================================
rem  Build the OpenRadioss userlib_sdk static library  (one-off, reusable)
rem
rem  The SDK ships NO prebuilt library: userlib_sdk\win64_gfortran\ contains
rem  only build_userlib.bat.  libraduser_win64_gfortran.a and the *.mod files
rem  must be built from userlib_sdk\source before any user library can link.
rem
rem  The official build_windows.bat would do this too, but it writes
rem  cbuild_win64_gfortran_dp_ninja\ and the products INTO the Tools repo
rem  working tree.  This script runs the equivalent CMake invocation
rem  out-of-tree, so every product lands under Stone_mode\build_local\.
rem
rem  Pure ASCII on purpose (cmd.exe reads .bat in the OEM codepage).
rem  Run from cmd.exe or by double-clicking, not from Git Bash.
rem ===========================================================================
setlocal
cd /d "%~dp0"

rem  ---- CONFIG - edit these when moving to a new machine --------------------
rem  Root of the MinGW-w64 toolchain (must contain bin\gcc.exe, bin\gfortran.exe).
rem  Same variable name as the sibling project, so one machine-wide setting
rem  serves both.  Overridable by an environment variable of the same name.
if not defined KF_MINGW set "KF_MINGW=G:\x86_64-15.2.0-release-win32-seh-ucrt-rt_v13-rev0\mingw64"
rem  Root of the Tools repository (the sibling of the OpenRadioss repository).
if not defined KF_TOOLS set "KF_TOOLS=%~dp0..\..\Tools"
rem  -------------------------------------------------------------------------

for %%I in ("%~dp0..")   do set "REPO=%%~fI"
for %%I in ("%KF_TOOLS%") do set "TOOLS=%%~fI"
set "NINJA=%REPO%\extlib\build_mingw64\bin\ninja.exe"
set "SDKSRC=%TOOLS%\userlib_sdk"
set "OUT=%~dp0build_local"
set "BLD=%OUT%\sdk_build"
set "DEST=%OUT%\sdk\win64_gfortran"
set "LIB=%DEST%\libraduser_win64_gfortran.a"

rem  ---- config sanity check -------------------------------------------------
if not exist "%KF_MINGW%\bin\gfortran.exe" (
  echo [ERROR] MinGW toolchain not found: "%KF_MINGW%\bin\gfortran.exe"
  echo         Edit the CONFIG block at the top of this script, or set KF_MINGW.
  exit /b 1
)
if not exist "%SDKSRC%\source\CMakeLists.txt" (
  echo [ERROR] userlib_sdk source not found: "%SDKSRC%\source\CMakeLists.txt"
  echo         Edit the CONFIG block at the top of this script, or set KF_TOOLS.
  exit /b 1
)
if not exist "%NINJA%" (
  echo [ERROR] ninja not found: "%NINJA%"
  exit /b 1
)

if exist "%LIB%" if /i not "%~1"=="/FORCE" (
  echo.
  echo SDK library already present, nothing to do:
  echo   %LIB%
  echo Pass /FORCE to rebuild from scratch.
  goto :done
)

set "PATH=%KF_MINGW%\bin;%REPO%\extlib\build_mingw64;%PATH%"

echo ============================================================
echo  Step 1/2  Configure userlib_sdk  (out-of-tree CMake)
echo ============================================================
echo  source : %SDKSRC%\source
echo  build  : %BLD%
echo  dest   : %DEST%
echo.

rem  -DCMAKE_POLICY_VERSION_MINIMUM=3.5: userlib_sdk's CMakeLists declares
rem  cmake_minimum_required(VERSION 3.5), which CMake 4.x rejects by default.
rem  This is the documented escape hatch and does not change the build itself.
rem
rem  -S sdk_src (not the SDK's own source dir): our project-local mirror, which
rem  includes the official compiler settings file and appends the single flag
rem  GCC 14+ needs.  See sdk_src/CMakeLists.txt for the full rationale.
cmake -G Ninja -S "%~dp0sdk_src" -B "%BLD%" ^
      -DSDK_SOURCE="%SDKSRC%\source" ^
      -DCMAKE_MAKE_PROGRAM="%NINJA%" ^
      -DCMAKE_Fortran_COMPILER=gfortran -DCMAKE_C_COMPILER=gcc ^
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ^
      -Darch=win64 -Dcompiler=gfortran -Dprecision=dp
if errorlevel 1 (
  echo [ERROR] CMake configure failed.
  exit /b 1
)

echo.
echo ============================================================
echo  Step 2/2  Build  (about 400 fixed-form Fortran files)
echo ============================================================
cmake --build "%BLD%"
if errorlevel 1 (
  echo [ERROR] build failed.
  exit /b 1
)

rem  Lay the products out the way build_userlib.bat expects to find them:
rem    %RAD_USERLIB_SDK_PATH%\%RAD_USERLIB_ARCH%\libraduser_win64_gfortran.a
rem    %RAD_USERLIB_SDK_PATH%\%RAD_USERLIB_ARCH%\*.mod
if not exist "%DEST%" mkdir "%DEST%"
copy /y "%BLD%\*.a"   "%DEST%" >nul
copy /y "%BLD%\*.mod" "%DEST%" >nul

if not exist "%LIB%" (
  echo [ERROR] SDK library was not produced: "%LIB%"
  exit /b 1
)

echo.
echo  SDK library : %LIB%
for %%F in ("%LIB%") do echo  size        : %%~zF bytes
rem  Count with pure cmd: when this script is launched from Git Bash (via
rem  cmd //c), the inherited PATH makes `find` resolve to the MSYS one.
set /a NMODS=0
for %%M in ("%DEST%\*.mod") do set /a NMODS+=1
echo  module files: %NMODS%

:done
rem  Double-clicked runs get a fresh console that closes on exit, so pause to
rem  let the summary be read.  Automated runs pass "nopause" anywhere in argv.
set "NOPAUSE="
for %%A in (%*) do if /i "%%A"=="nopause" set "NOPAUSE=1"
if not defined NOPAUSE pause
endlocal
