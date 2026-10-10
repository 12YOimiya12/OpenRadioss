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

call "%~dp0vs_env.bat" quiet
if errorlevel 1 goto :fail
if not exist "%NINJA%" (
  echo [ERROR] Ninja not found: "%NINJA%"
  goto :fail
)
if not exist "%SDK_SOURCE%\CMakeLists.txt" (
  echo [ERROR] userlib_sdk source not found: "%SDK_SOURCE%"
  goto :fail
)
if not exist "%SDK_SOURCE%\Cmake_Compilers\cmake_win64_oneapi.txt" (
  echo [ERROR] oneAPI SDK compiler configuration not found.
  goto :fail
)

"%CMAKE%" -G Ninja -S "%~dp0sdk_src" -B "%BUILD%" ^
  -DSDK_SOURCE="%SDK_SOURCE%" -DCMAKE_MAKE_PROGRAM="%NINJA%" ^
  -DCMAKE_Fortran_COMPILER=ifx -DCMAKE_C_COMPILER=icx ^
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ^
  -Darch=win64 -Dcompiler=oneapi -Dprecision=dp
if errorlevel 1 goto :fail
if not exist "%BUILD%\build.ninja" (
  echo [ERROR] CMake configure produced no build tree.
  goto :fail
)
echo oneAPI environment and SDK configure check passed.
echo.
echo   SDK archive  : %~dp0build_local\sdk\win64_oneapi\libraduser_win64_oneapi.lib
echo   User library : %~dp0build_local\userlib_oneapi\libraduser_win64.dll
echo.
echo Next: build_sdk.bat  then  build_userlib.bat  then  check_exports.bat
exit /b 0

:fail
echo oneAPI environment check failed.
exit /b 1
