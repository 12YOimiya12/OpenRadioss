@echo off
rem ===========================================================================
rem  Build  build_local\userlib_oneapi\libraduser_win64.dll
rem
rem  This does NOT delegate to userlib_sdk\userlib_sdk\win64_oneapi\
rem  build_userlib.bat. Two reasons, both explained at length in
rem  sdk_src\CMakeLists.txt:
rem
rem    * the SDK's C dispatch shim is GCC-only and must not be part of the
rem      Intel build at all - under ifx the interface routines export
rem      themselves, in uppercase, which is what the solver looks up on Windows;
rem    * that script also compiles the user sources with /assume:underscore,
rem      which does not match the spelling the dispatch routines call them by,
rem      and links /FORCE:UNRESOLVED, which would hide the resulting mismatch.
rem
rem  Steps
rem    1. make sure the SDK archive exists        (build_sdk.bat)
rem    2. unpack the archive into _obj_win64
rem    3. drop the stub object for each routine the user supplies
rem    4. compile the user routines with the SDK's own naming convention
rem    5. link every object into libraduser_win64.dll
rem
rem  Usage:  build_userlib.bat [starter.f] [engine.f]
rem
rem  Pure ASCII / CRLF.  Run from cmd.exe, not Git Bash.
rem ===========================================================================
setlocal
cd /d "%~dp0"

rem  ---- CONFIG - keep in sync with build_sdk.bat ----------------------------
if not defined KF_TOOLS set "KF_TOOLS=%~dp0..\..\Tools"
rem  -------------------------------------------------------------------------

set "SDK_DIR=%~dp0build_local\sdk"
set "SDK_ARCH=win64_oneapi"
set "DEST=%SDK_DIR%\%SDK_ARCH%"
set "SDK_LIB=%DEST%\libraduser_win64_oneapi.lib"
set "OUT=%~dp0build_local\userlib_oneapi"
set "OBJ=%OUT%\_obj_win64"
set "DLL=%OUT%\libraduser_win64.dll"

rem  Sources: default to the two files that ship with this folder.
set "STARTER_SRC=%~dp0LECMUSER01.f"
set "ENGINE_SRC=%~dp0LUSER01.f"
if not "%~1"=="" set "STARTER_SRC=%~1"
if not "%~2"=="" set "ENGINE_SRC=%~2"

echo ============================================================
echo  Step 1/5  SDK archive
echo ============================================================
call "%~dp0build_sdk.bat"
if errorlevel 1 exit /b 1

rem  build_sdk.bat is isolated with setlocal, so initialize the toolchain again
rem  before using lib.exe / ifx directly.
call "%~dp0vs_env.bat" quiet
if errorlevel 1 exit /b 1

if not exist "%SDK_LIB%" (
  echo [ERROR] SDK archive not found: "%SDK_LIB%"
  exit /b 1
)
if not exist "%STARTER_SRC%" (
  echo [ERROR] starter source not found: "%STARTER_SRC%"
  exit /b 1
)
if not exist "%ENGINE_SRC%" (
  echo [ERROR] engine source not found: "%ENGINE_SRC%"
  exit /b 1
)

echo.
echo ============================================================
echo  Step 2/5  Unpack the SDK archive
echo ============================================================
if exist "%OBJ%" rmdir /s /q "%OBJ%"
mkdir "%OBJ%"
pushd "%OBJ%"
lib -list "%SDK_LIB%" | findstr /c:.obj > liblist.txt
if errorlevel 1 (
  echo [ERROR] lib -list produced nothing - is "%SDK_LIB%" a real archive?
  popd
  exit /b 1
)
for /f "delims=" %%f in (liblist.txt) do lib /NOLOGO /EXTRACT:%%f "%SDK_LIB%" >nul
del /q liblist.txt
set /a NOBJ=0
for %%o in (*.obj) do set /a NOBJ+=1
popd
echo  extracted %NOBJ% objects

echo.
echo ============================================================
echo  Step 3/5  Drop the stubs the user replaces
echo ============================================================
rem  The archive carries a stub for every law number, and linking ours on top of
rem  the stub would redefine the same symbol. NTFS is case insensitive, so
rem  "LECMUSER01.F.obj" deletes the extracted "lecmuser01.F.obj".
for %%F in ("%STARTER_SRC%") do set "STARTER_BASE=%%~nF"
for %%F in ("%ENGINE_SRC%")  do set "ENGINE_BASE=%%~nF"
for %%B in ("%STARTER_BASE%" "%ENGINE_BASE%") do (
  if exist "%OBJ%\%%~B.F.obj" (
    del /q "%OBJ%\%%~B.F.obj"
    echo  dropped SDK stub: %%~B.F.obj
  ) else (
    echo  [WARN] no SDK stub named %%~B.F.obj - unexpected law number?
  )
)

echo.
echo ============================================================
echo  Step 4/5  Compile the user routines
echo ============================================================
rem  These flags must match the SDK archive exactly. The dispatch routines reach
rem  the user routines as  lecmuser01 / luser01 / arret  - lowercase, no
rem  trailing underscore. Compiling with anything else produces a DLL that links
rem  only because the symbols happen to be unresolved.
pushd "%OBJ%"
ifx /nologo /c /names:lowercase /assume:nounderscore /fpp /DMYREAL8 /DR8 ^
    /module:"%DEST%" /Qaxsse3 /Qimf-use-svml:true /align:array64byte /Qopenmp /O2 ^
    /fp:precise /Qftz /extend-source "%STARTER_SRC%"
if errorlevel 1 ( popd & exit /b 1 )
ifx /nologo /c /names:lowercase /assume:nounderscore /fpp /DMYREAL8 /DR8 ^
    /module:"%DEST%" /Qaxsse3 /Qimf-use-svml:true /align:array64byte /Qopenmp /O3 ^
    /fp:precise /Qftz /extend-source "%ENGINE_SRC%"
if errorlevel 1 ( popd & exit /b 1 )
popd

echo.
echo ============================================================
echo  Step 5/5  Link libraduser_win64.dll
echo ============================================================
if not exist "%OUT%" mkdir "%OUT%"
if exist "%DLL%" del /q "%DLL%"
pushd "%OUT%"
ifx /nologo /DLL /MT -o libraduser_win64.dll _obj_win64\*.obj
set "RC=%errorlevel%"
popd
if not "%RC%"=="0" exit /b %RC%

if not exist "%DLL%" (
  echo [ERROR] user library DLL was not produced.
  exit /b 1
)

echo.
echo User library: "%DLL%"
exit /b 0
