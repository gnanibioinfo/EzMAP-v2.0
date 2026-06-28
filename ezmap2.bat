@echo off
REM =============================================================================
REM EzMAP2 — Windows Launcher (double-click to run)
REM =============================================================================

title EzMAP2

REM Locate the script directory
set "SCRIPT_DIR=%~dp0"

REM Check for JAR in target\ (development) or same dir (deployed)
if exist "%SCRIPT_DIR%target\EzMAP2.jar" (
    set "JAR=%SCRIPT_DIR%target\EzMAP2.jar"
) else if exist "%SCRIPT_DIR%EzMAP2.jar" (
    set "JAR=%SCRIPT_DIR%EzMAP2.jar"
) else (
    echo.
    echo  ERROR: EzMAP2.jar not found!
    echo.
    echo  Build it first with:
    echo    cd %SCRIPT_DIR%
    echo    mvn clean package
    echo.
    pause
    exit /b 1
)

REM Check if Java is installed
java -version >nul 2>&1
if errorlevel 1 (
    echo.
    echo  ERROR: Java is not installed or not in PATH.
    echo.
    echo  Download Java 11+ from:
    echo    https://adoptium.net/
    echo.
    pause
    exit /b 1
)

REM Launch EzMAP2
echo Starting EzMAP2...
start "" javaw -Xmx2g -jar "%JAR%"
