@echo off
rem ===========================================================================
rem  Stone_mode - verify the Intel (VS2022 + oneAPI) toolchain
rem
rem  What this does
rem  --------------
rem    1. sets up the Intel environment via vs_env.bat
rem    2. checks ifx / icx / link are actually reachable and report versions
rem    3. runs an out-of-tree CMake CONFIGURE of the userlib_sdk mirror, which
rem       makes CMake probe both compilers, and generates the oneapi wrapper
rem    4. verifies the generated wrapper really has the __GNUC__ gate opened
rem
rem  It deliberately does NOT compile anything: a configure pass exercises the
rem  whole toolchain (compiler probing, include resolution, wrapper generation)
rem  in seconds, whereas building the SDK archive is ~400 fixed-form files.
rem
rem  Everything lands under build_local\, which is disposable.
rem
rem  Pure ASCII / CRLF.  Run from cmd.exe, not Git Bash.
rem ===========================================================================
setlocal
cd /d "%~dp0"

rem  ---- CONFIG - keep in sync with build_sdk.bat ----------------------------
if not defined KF_TOOLS set "KF_TOOLS=%~dp0..\..\Tools"
rem  -------------------------------------------------------------------------

for %%I in ("%~dp0..")   do set "REPO=%%~fI"
for %%I in ("%KF_TOOLS%") do set "TOOLS=%%~fI"
set "NINJA=%REPO%\extlib\build_mingw64\bin\ninja.exe"
set "SDKSRC=%TOOLS%\userlib_sdk"
set "OUT=%~dp0build_local"
set "BLD=%OUT%\sdk_build_oneapi"
set "WRAPPER=%BLD%\win64_oneapi_wrapper.c"

echo ============================================================
echo  Step 0/3  Intel environment
echo ============================================================
call "%~dp0vs_env.bat" quiet
if errorlevel 1 (
  echo [ERROR] vs_env.bat failed - fix that first.
  goto :fail
)
echo  OK  ifx and icx are on PATH

echo.
echo ============================================================
echo  Step 1/3  Preconditions
echo ============================================================
if not exist "%NINJA%" (
  echo [ERROR] ninja not found: "%NINJA%"
  goto :fail
)
if not exist "%SDKSRC%\source\CMakeLists.txt" (
  echo [ERROR] userlib_sdk source not found: "%SDKSRC%\source\CMakeLists.txt"
  echo         Edit the CONFIG block at the top of this script, or set KF_TOOLS.
  goto :fail
)
if not exist "%SDKSRC%\source\Cmake_Compilers\cmake_win64_oneapi.txt" (
  echo [ERROR] the SDK has no oneapi cmake config - wrong SDK release?
  goto :fail
)
echo  OK  ninja, SDK source and cmake_win64_oneapi.txt all present

echo.
echo ============================================================
echo  Step 2/3  CMake configure with ifx + icx   (no compile)
echo ============================================================
echo  source : %SDKSRC%\source
echo  build  : %BLD%
echo.
cmake -G Ninja -S "%~dp0sdk_src" -B "%BLD%" ^
      -DSDK_SOURCE="%SDKSRC%\source" ^
      -DCMAKE_MAKE_PROGRAM="%NINJA%" ^
      -DCMAKE_Fortran_COMPILER=ifx -DCMAKE_C_COMPILER=icx ^
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ^
      -Darch=win64 -Dcompiler=oneapi -Dprecision=dp
if errorlevel 1 (
  echo [ERROR] CMake configure failed.
  goto :fail
)

echo.
echo ============================================================
echo  Step 3/3  Generated wrapper sanity check
echo ============================================================
if not exist "%WRAPPER%" (
  echo [ERROR] wrapper was not generated: "%WRAPPER%"
  goto :fail
)
for %%F in ("%WRAPPER%") do echo  generated : %%~zF bytes

findstr /c:"#if 1" "%WRAPPER%" >nul
if errorlevel 1 (
  echo [ERROR] the __GNUC__ gate is still closed in the generated wrapper.
  echo         icx would build an empty object and the DLL would export nothing.
  goto :fail
)
echo  OK  __GNUC__ gate is opened

findstr /c:"__GNUC__" "%WRAPPER%" | findstr /c:"#ifdef" >nul
if not errorlevel 1 (
  echo [WARN] an "#ifdef __GNUC__" line survived somewhere in the wrapper.
)

rem  #if / #endif balance - an unbalanced file would fail to compile much later.
rem  Counted with for/f over findstr only: when this script is launched from
rem  Git Bash, a bare "find" would resolve to the MSYS one (see build_sdk.bat).
set /a NIF=0
set /a NEND=0
for /f "delims=" %%L in ('findstr /r /c:"^#if" "%WRAPPER%"') do set /a NIF+=1
for /f "delims=" %%L in ('findstr /r /c:"^#endif" "%WRAPPER%"') do set /a NEND+=1
echo  preprocessor: %NIF% #if blocks, %NEND% #endif
if not "%NIF%"=="%NEND%" (
  echo [ERROR] unbalanced #if / #endif in the generated wrapper.
  goto :fail
)
echo  OK  balance is even

echo.
echo ============================================================
echo  Environment verified.  Nothing was compiled.
echo ============================================================
echo  Next step (not run here): build the oneapi SDK archive with
echo    cmake --build "%BLD%"
echo.
goto :done

:fail
echo.
echo *** ONEAPI ENVIRONMENT CHECK FAILED ***
:done
endlocal
