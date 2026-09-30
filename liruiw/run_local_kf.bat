@echo off
rem ===========================================================================
rem  KF LAW99 local runner - MinGW gfortran toolchain (this machine)
rem
rem  The original project (see KF_LAW99_Guide.md) was built with Visual Studio
rem  2022 and ran against a prebuilt MSVC OpenRadioss runtime.  This machine has
rem  no Visual Studio; the solver here is the MinGW gfortran build
rem  (exec\starter_win64_gf.exe / engine_win64_gf.exe).  This script adapts the
rem  workflow to that toolchain without modifying any project source.
rem
rem  Run it from cmd.exe or by double-clicking.  Must NOT be launched from
rem  Git Bash: MSYS mangles the G:\ PATH entries and the solver dies silently.
rem ===========================================================================
setlocal
cd /d "%~dp0"

rem ===========================================================================
rem  >>> CONFIG - edit only this block when moving to a new machine <<<
rem  (this file is intentionally pure ASCII: cmd.exe reads .bat in the OEM
rem   codepage, so non-ASCII comments can be mis-parsed as commands)
rem ===========================================================================
rem  Root of the MinGW-w64 toolchain (must contain bin\gcc.exe, bin\gfortran.exe).
rem  Can also be overridden by an environment variable of the same name.
if not defined KF_MINGW set "KF_MINGW=G:\x86_64-15.2.0-release-win32-seh-ucrt-rt_v13-rev0\mingw64"
rem  Source of th_to_csv (single C file; lives in the Tools repo, not in OpenRadioss).
if not defined KF_TH_SRC set "KF_TH_SRC=G:\Postgraduate_Researching\openSource_soft\Tools\output_converters\th_to_csv\src\th_to_csv.c"

rem  ---- Everything below is derived from this script's location; usually no edits ----
for %%I in ("%~dp0..") do set "REPO=%%~fI"
set "NINJA=%REPO%\extlib\build_mingw64\bin\ninja.exe"

rem  Config sanity check: fail with a clear message instead of a confusing error later.
if not exist "%KF_MINGW%\bin\gcc.exe" (
  echo [ERROR] MinGW toolchain not found: "%KF_MINGW%\bin\gcc.exe"
  echo         Edit the CONFIG block at the top of this script, or set KF_MINGW.
  exit /b 1
)
if not exist "%KF_TH_SRC%" (
  echo [ERROR] th_to_csv source not found: "%KF_TH_SRC%"
  echo         Edit the CONFIG block at the top of this script, or set KF_TH_SRC.
  exit /b 1
)

set "PATH=%REPO%\extlib\build_mingw64;%KF_MINGW%\bin;%PATH%"
set "RAD_CFG_PATH=%REPO%\hm_cfg_files"

set "OUT=%~dp0build_local"
set "DLLDIR=%OUT%\kf_dll"
set "DLL=%DLLDIR%\libraduser_win64.dll"
set "RT=%OUT%\runtime"

echo ============================================================
echo  Step 1/5  Build KF LAW99 user library  (MinGW + ninja)
echo ============================================================
cmake -S "%~dp0examples\userlib\kf_law99" -B "%DLLDIR%" -G Ninja ^
      -DCMAKE_MAKE_PROGRAM="%NINJA%" -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 exit /b 1
cmake --build "%DLLDIR%"
if errorlevel 1 exit /b 1

rem  Python 3.8+ ctypes no longer resolves dependent DLLs through PATH, so the
rem  MinGW runtime has to sit next to the user library.
copy /y "%KF_MINGW%\bin\libgcc_s_seh-1.dll" "%DLLDIR%" >nul
if not exist "%DLLDIR%\libgcc_s_seh-1.dll" (
  echo [ERROR] failed to copy libgcc_s_seh-1.dll from "%KF_MINGW%\bin"
  exit /b 1
)
if not exist "%DLL%" (
  echo [ERROR] user library was not produced: %DLL%
  exit /b 1
)

echo.
echo ============================================================
echo  Step 2/5  Build runtime mirror  (solver + th_to_csv)
echo ============================================================
rem  run_step11_validation.py looks for starter_win64.exe / engine_win64.exe
rem  (no _gf suffix), so mirror the gfortran executables under those names.
rem  Hard links keep it free; hm_cfg_files is junctioned in read-only.
if not exist "%RT%\exec" mkdir "%RT%\exec"
if not exist "%RT%\exec\starter_win64.exe" mklink /H "%RT%\exec\starter_win64.exe" "%REPO%\exec\starter_win64_gf.exe" >nul
if not exist "%RT%\exec\engine_win64.exe" mklink /H "%RT%\exec\engine_win64.exe" "%REPO%\exec\engine_win64_gf.exe" >nul
if not exist "%RT%\hm_cfg_files" mklink /J "%RT%\hm_cfg_files" "%REPO%\hm_cfg_files" >nul
if not exist "%RT%\exec\th_to_csv_win64.exe" gcc -O2 -w -o "%RT%\exec\th_to_csv_win64.exe" "%KF_TH_SRC%"
if not exist "%RT%\exec\th_to_csv_win64.exe" (
  echo [ERROR] th_to_csv build failed
  exit /b 1
)

echo.
echo ============================================================
echo  Step 3/5  DLL material-point matrix
echo ============================================================
python "%~dp0examples\userlib\kf_law99\validate_kf_law99.py" --dll "%DLL%" --out "%OUT%\validation"
if errorlevel 1 (
  echo [ERROR] material-point matrix reported failures
  exit /b 1
)

echo.
echo ============================================================
echo  Step 4/5  Section 11 checklist (one-brick FE + T01 CSV)
echo ============================================================
rem  --skip-build: build_library() targets the Visual Studio project, which
rem  does not exist here.  Step 1 above already built the DLL.
python "%~dp0examples\userlib\kf_law99\run_step11_validation.py" --runtime "%RT%" --dll "%DLL%" --out "%OUT%\step11" --skip-build
if errorlevel 1 (
  echo [ERROR] Section 11 checklist reported failures
  exit /b 1
)

echo.
echo ============================================================
echo  Step 5/5  Done
echo ============================================================
echo  DLL            : %DLL%
echo  Material point : %OUT%\validation\validation_report.md
echo  Section 11     : %OUT%\step11\step11_verification_report.md
echo  One-brick logs : %OUT%\step11\fe_one_brick\starter.log / engine.log

rem  Double-clicked runs get a fresh console that closes on exit, so pause to
rem  let the summary above be read.  Automated/scripted runs pass "nopause".
if /i not "%~1"=="nopause" pause

endlocal
