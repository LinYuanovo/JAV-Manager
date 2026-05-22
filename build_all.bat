@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

echo ========================================
echo   JAV-Manager Build Tool
echo ========================================
echo.

:: Step 1: Check Python
echo [1/5] Checking Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found!
    pause
    exit /b 1
)
for /f "tokens=2 delims= " %%v in ('python --version 2^>^&1') do set PYTHON_VERSION=%%v
echo [OK] Python %PYTHON_VERSION%

:: Step 2: Check Flutter (use 'where' instead of 'flutter --version' to avoid exit code issue)
echo.
echo [2/5] Checking Flutter...
where flutter >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter not found in PATH!
    echo Please install Flutter: https://docs.flutter.dev/get-started/install
    pause
    exit /b 1
)
for /f "tokens=*" %%f in ('where flutter') do set FLUTTER_PATH=%%f
echo [OK] Flutter found at %FLUTTER_PATH%

:: Step 3: Install Python dependencies
echo.
echo [3/5] Installing Python dependencies...
pip install -r python_scraper\requirements.txt --quiet >nul 2>&1
pip install pyinstaller --quiet >nul 2>&1
echo [OK] Dependencies installed

:: Step 4: Build Flutter app
echo.
echo [4/5] Building Flutter app...
call flutter build windows --release
if errorlevel 1 (
    echo [ERROR] Flutter build failed!
    pause
    exit /b 1
)
echo [OK] Flutter build success

:: Step 5: Build Python scraper and copy
echo.
echo [5/5] Building Python scraper...
pyinstaller python_scraper\scraper.spec --clean --noconfirm
if errorlevel 1 (
    echo [ERROR] PyInstaller build failed!
    pause
    exit /b 1
)

if exist dist\javsp_scraper.exe (
    copy /y dist\javsp_scraper.exe build\windows\x64\runner\Release\ >nul
    echo [OK] Scraper copied to release directory
) else (
    echo [WARNING] javsp_scraper.exe not generated
)

echo.
echo ========================================
echo   BUILD COMPLETE!
echo ========================================
echo.
echo Output: build\windows\x64\runner\Release\
echo Files:
dir /b build\windows\x64\runner\Release\*.exe build\windows\x64\runner\Release\*.dll 2>nul
echo.
pause
