@echo off
rem  Verify the built DLL exports every symbol dyn_userlib.c looks up on Windows.
setlocal enabledelayedexpansion
call "G:\Postgraduate_Researching\openSource_soft\OpenRadioss\VS_OneAPI\vs_env.bat" quiet
set "DLL=G:\Postgraduate_Researching\openSource_soft\OpenRadioss\VS_OneAPI\build_local\userlib_oneapi\libraduser_win64.dll"

dumpbin /exports "%DLL%" > "%~dp0build_local\dll_exports.txt" 2>&1

echo ================ required by STARTER (fatal if missing) ================
set "MISS=0"
for %%S in (ST_LECG ST_LECGUSER ST_LECM ST_LECR ST_LECM99 ST_LECSEN ST_RINIUSER ST_SINIUSR ST_USERWIS ST_USERWIS_INI ST_GET_USERBUF_VAR userlib_id set_callback) do (
  findstr /r /c:" %%S$" "%~dp0build_local\dll_exports.txt" >nul
  if errorlevel 1 ( echo    MISSING  %%S & set /a MISS+=1 ) else ( echo    ok       %%S )
)

echo.
echo ================ required by ENGINE (fatal if missing) ================
for %%S in (ENG_RUSER ENG_SIGEPS ENG_SIGEPSC ENG_FLAW ENG_FLAWC ENG_SIGEPS99 ENG_SIGEPS99C ENG_GET_LAW_USER_VAR ENG_GET_LAW_USER_VAR_2 ENG_SET_LAW_USER_VAR ENG_SET_LAW_USER_VAR_2 ENG_GET_LAWC_USER_VAR ENG_GET_LAWC_USER_VAR_2 ENG_SET_LAWC_USER_VAR ENG_SET_LAWC_USER_VAR_2 ENG_GET_UINTBUF_VAR ENG_SUSER ENG_USERINT ENG_USERWI ENG_USER_SENS) do (
  findstr /r /c:" %%S$" "%~dp0build_local\dll_exports.txt" >nul
  if errorlevel 1 ( echo    MISSING  %%S & set /a MISS+=1 ) else ( echo    ok       %%S )
)

echo.
echo ================ optional ================
for %%S in (CINI29 CINI30 CINI31 ENGINE_USER_CHECK ENGINE_USER_INITIALIZE ENGINE_USER_FINALIZE) do (
  findstr /r /c:" %%S$" "%~dp0build_local\dll_exports.txt" >nul
  if errorlevel 1 ( echo    absent   %%S ) else ( echo    present  %%S )
)

echo.
echo ================ total exports in the DLL ================
set /a N=0
for /f "delims=" %%L in ('findstr /r /c:"^ *[0-9][0-9]*  *[0-9A-F]*  *[0-9A-F]*  *[A-Za-z_]" "%~dp0build_local\dll_exports.txt"') do set /a N+=1
echo    %N% exported names

echo.
if "%MISS%"=="0" (echo    ALL REQUIRED SYMBOLS PRESENT) else (echo    %MISS% REQUIRED SYMBOLS MISSING ***)
endlocal
