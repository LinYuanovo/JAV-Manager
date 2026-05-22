@echo off
chcp 65001 >nul
echo ============================================================
echo  JavSP 刮削器 - 打包脚本
echo ============================================================
echo.

cd /d "%~dp0"

echo [1/4] 检查 Python 环境...
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ 错误: 未检测到 Python，请先安装 Python 3.10+
    pause
    exit /b 1
)
python --version

echo.
echo [2/4] 安装依赖包...
pip install -r requirements.txt --quiet
if errorlevel 1 (
    echo ❌ 错误: 依赖安装失败
    pause
    exit /b 1
)
echo ✅ 依赖安装完成

echo.
echo [3/4] 清理旧的构建文件...
if exist "build" rmdir /s /q "build"
if exist "dist" rmdir /s /q "dist"
if exist "*.spec" del /q "*.spec" 2>nul
echo ✅ 清理完成

echo.
echo [4/4] 开始打包...
pyinstaller scraper.spec --clean --noconfirm
if errorlevel 1 (
    echo ❌ 打包失败！
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  ✅ 打包成功！
echo ============================================================
echo.
echo 输出文件位置:
echo   %CD%\dist\scraper.exe
echo.
echo 文件大小:
for %%A in ("dist\scraper.exe") do echo   %%~zA bytes (%%~nxA)
echo.
echo 下一步操作:
echo   1. 将 dist\scraper.exe 复制到 JAV-Manager 的运行目录
echo.

pause
