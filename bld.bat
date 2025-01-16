setlocal enableextensions enabledelayedexpansion

set NINJAFLAGS="-j3"

set LIBRARY_PATHS=-I %LIBRARY_INC%

pushd %LIBRARY_INC%
for /F "usebackq delims=" %%F in (`dir /b /ad-h`) do (
    set LIBRARY_PATHS=!LIBRARY_PATHS! -I %LIBRARY_INC%\%%F
)
popd
endlocal

:: Chromium requires Python 2.7 to generate compilation outputs.
cmd /c "conda create -y -q --prefix "%SRC_DIR%\win_python" python=2.7 -c pkgs/main"
set PATH=%SRC_DIR%\win_python;%PATH%

pushd qtwebengine

set PATH=%cd%\jom;%PATH%
:: CALL :NORMALIZEPATH "..\gnuwin32"
set GNUWIN32_PATH=%SRC_DIR%\gnuwin32
SET PATH=%SRC_DIR%\gnuwin32\gnuwin32\bin;%SRC_DIR%\gnuwin32\bin;%PATH%

perl.exe "%LIBRARY_BIN%"/syncqt.pl -version 5.15.9

mkdir b2
pushd b2

where jom

:: Set QMake prefix to LIBRARY_PREFIX
qmake -set prefix %LIBRARY_PREFIX%

qmake QMAKE_LIBDIR=%LIBRARY_LIB% ^
      QMAKE_BINDIR=%LIBRARY_BIN% ^
      INCLUDEPATH+="%LIBRARY_INC%" ^
      ..

echo on

jom
jom install
