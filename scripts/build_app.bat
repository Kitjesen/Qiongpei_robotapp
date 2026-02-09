@echo off
REM ========================================
REM  穹佩控制面板 - Windows App 编译脚本
REM ========================================
echo.
echo [穹佩] 开始编译 Windows 桌面应用...
echo.

REM 确保 Flutter 在 PATH 中
set PATH=D:\flutter\bin;%PATH%
where flutter >nul 2>nul
if errorlevel 1 (
    echo [错误] Flutter 不在 PATH 中，请先配置 Flutter SDK 路径
    echo        例: set PATH=D:\flutter\bin;%%PATH%%
    exit /b 1
)

REM ========================================
REM  中文路径兼容处理
REM  MSBuild/CMake 不支持路径中的中文字符
REM  通过 junction 映射到纯英文路径来解决
REM ========================================
set JUNCTION_PATH=D:\QiongPei
set REAL_PATH=%~dp0..\..

REM 检查是否需要创建 junction
if not exist "%JUNCTION_PATH%\qiongpei_app\pubspec.yaml" (
    echo [信息] 创建 junction: %JUNCTION_PATH% -^> %REAL_PATH%
    if exist "%JUNCTION_PATH%" rmdir "%JUNCTION_PATH%"
    mklink /J "%JUNCTION_PATH%" "%REAL_PATH%"
    if errorlevel 1 (
        echo [错误] junction 创建失败，请以管理员身份运行
        exit /b 1
    )
)

REM 从 junction 路径编译 (避免中文路径问题)
cd /d "%JUNCTION_PATH%\qiongpei_app"

REM 获取依赖
echo [1/3] 获取依赖...
call flutter pub get
if errorlevel 1 (
    echo [错误] 依赖获取失败
    exit /b 1
)

REM 编译 Release 版本
echo [2/3] 编译 Release 版本...
call flutter build windows --release
if errorlevel 1 (
    echo [错误] 编译失败
    exit /b 1
)

REM 复制到原始目录
set OUTPUT=%JUNCTION_PATH%\qiongpei_app\build\windows\x64\runner\Release

REM 输出路径
echo [3/3] 编译完成!
echo.
echo ========================================
echo  输出目录: %OUTPUT%
echo  可执行文件: qiongpei_app.exe
echo ========================================
echo.

REM 打开输出目录
explorer "%OUTPUT%"
