@echo off
REM =============================================================================
REM EzMAP2 — Build from source (Windows)
REM Requires: Java 11+, Maven 3.6+
REM =============================================================================

title EzMAP2 Build

set "SCRIPT_DIR=%~dp0"

echo.
echo  ========================================
echo   EzMAP2 — Building from source
echo  ========================================
echo.

REM Check Maven
mvn --version >nul 2>&1
if errorlevel 1 (
    echo  ERROR: Maven is not installed or not in PATH.
    echo.
    echo  Download Maven from:
    echo    https://maven.apache.org/download.cgi
    echo.
    pause
    exit /b 1
)

REM Build
cd /d "%SCRIPT_DIR%src-build"
echo Building EzMAP2...
mvn clean package -q

if errorlevel 1 (
    echo.
    echo  BUILD FAILED. Check errors above.
    pause
    exit /b 1
)

REM Copy JAR to distribution root
copy /Y "target\EzMAP2.jar" "%SCRIPT_DIR%EzMAP2.jar" >nul

echo.
echo  ========================================
echo   BUILD SUCCESSFUL
echo   JAR: %SCRIPT_DIR%EzMAP2.jar
echo  ========================================
echo.
pause
