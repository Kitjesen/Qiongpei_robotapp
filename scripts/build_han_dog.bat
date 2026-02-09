@echo off
REM ========================================
REM  汉狗控制端 - 原生可执行文件编译脚本
REM ========================================
echo.
echo [汉狗] 开始编译机器人端可执行文件...
echo.

REM 确保 Dart 在 PATH 中
set PATH=D:\flutter\bin;%PATH%
where dart >nul 2>nul
if errorlevel 1 (
    echo [错误] Dart 不在 PATH 中，请先配置 Flutter/Dart SDK 路径
    echo        例: set PATH=D:\flutter\bin;%%PATH%%
    exit /b 1
)

REM ========================================
REM  中文路径兼容处理
REM ========================================
set JUNCTION_PATH=D:\QiongPei
set REAL_PATH=%~dp0..\..

if not exist "%JUNCTION_PATH%\han_dog\pubspec.yaml" (
    echo [信息] 创建 junction: %JUNCTION_PATH% -^> %REAL_PATH%
    if exist "%JUNCTION_PATH%" rmdir "%JUNCTION_PATH%"
    mklink /J "%JUNCTION_PATH%" "%REAL_PATH%"
    if errorlevel 1 (
        echo [错误] junction 创建失败，请以管理员身份运行
        exit /b 1
    )
)

REM 项目路径 (han_dog 包)
set HAN_DOG_DIR=%JUNCTION_PATH%\han_dog
set OUTPUT_DIR=%JUNCTION_PATH%\qiongpei_app\build\han_dog_release

REM 检查入口文件
if not exist "%HAN_DOG_DIR%\example\mini\2\real1.dart" (
    echo [错误] 找不到入口文件: han_dog\example\mini\2\real1.dart
    exit /b 1
)

REM 创建输出目录
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

REM 获取依赖
echo [1/4] 获取依赖...
cd /d "%HAN_DOG_DIR%"
call dart pub get
if errorlevel 1 (
    echo [错误] 依赖获取失败
    exit /b 1
)

REM 编译
echo [2/4] 编译原生可执行文件...
call dart compile exe example\mini\2\real1.dart -o "%OUTPUT_DIR%\han_dog.exe"
if errorlevel 1 (
    echo [错误] 编译失败
    exit /b 1
)

REM 复制模型文件
echo [3/4] 复制 ONNX 模型文件...
if exist "model" (
    xcopy /E /I /Y "model" "%OUTPUT_DIR%\model"
)

REM 完成
echo [4/4] 编译完成!
echo.
echo ========================================
echo  输出目录: %OUTPUT_DIR%
echo  可执行文件: han_dog.exe
echo  模型文件: model\
echo ========================================
echo.
echo [注意] 运行时需要确保以下动态库在同目录或 PATH 中:
echo   - onnxruntime.dll (ONNX Runtime)
echo   - PCANBasic.dll (PCAN 驱动, 如使用 CAN 总线)
echo.

explorer "%OUTPUT_DIR%"
