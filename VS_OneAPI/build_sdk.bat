@echo off
setlocal
cd /d "%~dp0"
if not defined KF_TOOLS set "KF_TOOLS=%~dp0..\..\Tools"
if not defined KF_VS2022 set "KF_VS2022=G:\Program Files\visualStudio"
for %%I in ("%~dp0..") do set "REPO=%%~fI"
set "NINJA=%REPO%\extlib\build_mingw64\bin\ninja.exe"
set "CMAKE=%KF_VS2022%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if not exist "%CMAKE%" set "CMAKE=cmake"
set "SDK_SOURCE=%KF_TOOLS%\userlib_sdk\source"
set "BUILD=%~dp0build_local\sdk_build_oneapi"
set "DEST=%~dp0build_local\sdk\win64_oneapi"
set "SDK_LIB=%DEST%\libraduser_win64_oneapi.lib"

call "%~dp0vs_env.bat" quiet
if errorlevel 1 exit /b 1
if not exist "%NINJA%" (
  echo [ERROR] Ninja not found: "%NINJA%"
  exit /b 1
)
if not exist "%SDK_SOURCE%\CMakeLists.txt" (
  echo [ERROR] userlib_sdk source not found: "%SDK_SOURCE%"
  exit /b 1
)

if exist "%SDK_LIB%" if /i not "%~1"=="/FORCE" (
  echo SDK library already exists: "%SDK_LIB%"
  exit /b 0
)

"%CMAKE%" -G Ninja -S "%~dp0sdk_src" -B "%BUILD%" ^
  -DSDK_SOURCE="%SDK_SOURCE%" -DCMAKE_MAKE_PROGRAM="%NINJA%" ^
  -DCMAKE_Fortran_COMPILER=ifx -DCMAKE_C_COMPILER=icx ^
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ^
  -Darch=win64 -Dcompiler=oneapi -Dprecision=dp
if errorlevel 1 exit /b 1
"%CMAKE%" --build "%BUILD%"
if errorlevel 1 exit /b 1

if not exist "%DEST%" mkdir "%DEST%"
copy /y "%BUILD%\*.lib" "%DEST%" >nul
copy /y "%BUILD%\*.mod" "%DEST%" >nul
if not exist "%SDK_LIB%" (
  echo [ERROR] SDK library was not produced: "%SDK_LIB%"
  exit /b 1
)
echo SDK library: "%SDK_LIB%"
exit /b 0
