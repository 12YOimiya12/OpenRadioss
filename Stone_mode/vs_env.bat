@echo off
rem ===========================================================================
rem  Stone_mode - Intel toolchain environment   (VS2022 + oneAPI)
rem
rem  Usage
rem  -----
rem    call vs_env.bat            set the environment in the calling script
rem    vs_env.bat                 run standalone, then print a summary
rem    vs_env.bat quiet           same, without the summary
rem    vs_env.bat nopause         skip the pause after a standalone run
rem
rem  Why this script exists
rem  ----------------------
rem  On this machine BOTH toolchains live outside their default locations:
rem      Visual Studio : G:\Program Files\visualStudio
rem      oneAPI        : G:\One_API
rem
rem  oneAPI's own setvars.bat only probes the standard VS locations
rem  (Program Files\Microsoft Visual Studio\2022\Professional, .Enterprise,
rem  .Community).  It never finds VS here, so it prints
rem      WARNING: Visual Studio was not found in a standard install location
rem  and then each of the 13 components fails with
rem      'vars.bat' is not recognized as an internal or external command
rem  even though every one of those vars.bat files is present.
rem
rem  The whole fix is one variable: VS2022INSTALLDIR.  Set it before calling
rem  setvars.bat and all 13 components initialise with errorlevel 0.  That is
rem  the only thing this script does beyond sanity checks.
rem
rem  Do NOT run this from Git Bash.  Use cmd.exe, or "cmd //c" from bash - the
rem  MSYS PATH rewrite breaks the toolchain.  Same rule as run_stone.bat.
rem
rem  Pure ASCII on purpose: cmd.exe reads .bat in the OEM codepage.
rem  CRLF line endings on purpose.
rem ===========================================================================

rem  ---- CONFIG - edit these when moving to a new machine --------------------
rem  Root of the Visual Studio 2022 install (must contain VC\Auxiliary\Build).
rem  Overridable by an environment variable of the same name.
if not defined KF_VS2022  set "KF_VS2022=G:\Program Files\visualStudio"
rem  Root of the oneAPI install (must contain setvars.bat).
if not defined KF_ONEAPI set "KF_ONEAPI=G:\One_API"
rem  -------------------------------------------------------------------------

set "VS_VCVARS=%KF_VS2022%\VC\Auxiliary\Build\vcvarsall.bat"
if not exist "%VS_VCVARS%" (
  echo [ERROR] Visual Studio not found: "%VS_VCVARS%"
  echo         Edit the CONFIG block at the top of this script, or set KF_VS2022.
  exit /b 1
)
if not exist "%KF_ONEAPI%\setvars.bat" (
  echo [ERROR] oneAPI not found: "%KF_ONEAPI%\setvars.bat"
  echo         Edit the CONFIG block at the top of this script, or set KF_ONEAPI.
  exit /b 1
)

rem  setvars.bat works by pushing into <component>\latest\env and then running
rem  "vars.bat" by relative name.  If the launcher inherited
rem  NoDefaultCurrentDirectoryInExePath, cmd refuses to look in the current
rem  directory and the same 'vars.bat' not found error appears for a completely
rem  unrelated reason.  Clear it defensively - it costs nothing.
set "NoDefaultCurrentDirectoryInExePath="

rem  THE fix.  oneAPI's compiler\env\vars.bat honours this instead of probing
rem  the standard VS paths.  See "if defined VS2022INSTALLDIR" in that file.
set "VS2022INSTALLDIR=%KF_VS2022%"

call "%KF_ONEAPI%\setvars.bat" intel64
if errorlevel 1 (
  echo [ERROR] oneAPI setvars.bat returned an error.
  exit /b 1
)
if not defined CMPLR_ROOT (
  echo [ERROR] oneAPI environment did not initialise - CMPLR_ROOT is unset.
  exit /b 1
)

rem  ---- summary (suppressed with the "quiet" argument) ---------------------
set "QUIET="
for %%A in (%*) do if /i "%%A"=="quiet" set "QUIET=1"
if defined QUIET goto :standalone

echo.
echo Intel toolchain ready
echo   VS2022  : %VS2022INSTALLDIR%
echo   oneAPI  : %ONEAPI_ROOT%
echo.
echo   ifx     :
where ifx
echo   icx     :
where icx
echo   link    :
where link

:standalone
rem  Pause only when this script was launched on its own (double-click, or
rem  "cmd /c vs_env.bat"), never when it was 'call'ed by another script - a
rem  stray pause would hang an automated run.
set "STANDALONE="
echo %cmdcmdline% | findstr /i /c:"vs_env.bat" >nul
if not errorlevel 1 set "STANDALONE=1"
set "NOPAUSE="
for %%A in (%*) do if /i "%%A"=="nopause" set "NOPAUSE=1"
if defined STANDALONE if not defined NOPAUSE pause

exit /b 0
