@echo off
rem Initialize Visual Studio 2022 and Intel oneAPI for x64 builds.
rem Override KF_VS2022 and KF_ONEAPI when installing them elsewhere.
setlocal
if not defined KF_VS2022 set "KF_VS2022=G:\Program Files\visualStudio"
if not defined KF_ONEAPI set "KF_ONEAPI=G:\One_API"
set "VS_VCVARS=%KF_VS2022%\VC\Auxiliary\Build\vcvarsall.bat"
if not exist "%VS_VCVARS%" (
  echo [ERROR] Visual Studio not found: "%VS_VCVARS%"
  exit /b 1
)
if not exist "%KF_ONEAPI%\setvars.bat" (
  echo [ERROR] oneAPI not found: "%KF_ONEAPI%\setvars.bat"
  exit /b 1
)
endlocal & set "VS2022INSTALLDIR=%KF_VS2022%" & set "KF_ONEAPI=%KF_ONEAPI%"
set "NoDefaultCurrentDirectoryInExePath="
if not exist "%~dp0build_local\tmp" mkdir "%~dp0build_local\tmp"
set "TEMP=%~dp0build_local\tmp"
set "TMP=%~dp0build_local\tmp"
if exist "%KF_VS2022%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin" (
  set "PATH=%KF_VS2022%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;%PATH%"
)
call "%KF_ONEAPI%\setvars.bat" intel64
if errorlevel 1 exit /b 1
if not defined CMPLR_ROOT (
  echo [ERROR] oneAPI environment was not initialized.
  exit /b 1
)
where ifx >nul 2>&1 || exit /b 1
where icx >nul 2>&1 || exit /b 1
if /i not "%~1"=="quiet" (
  echo Intel oneAPI environment ready
  echo   VS2022: %VS2022INSTALLDIR%
  echo   oneAPI: %ONEAPI_ROOT%
  where ifx
  where icx
)
exit /b 0
