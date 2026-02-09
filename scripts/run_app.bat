@echo off
chcp 65001 >nul 2>nul
REM 启动穹沛控制面板（通过英文路径 junction 避免 MSBuild 中文路径报错）
set "PATH=D:\flutter\bin;C:\Program Files\Git\cmd;%PATH%"
set "JUNCTION_PATH=D:\QiongPei"
set "REAL_PATH=%~dp0..\.."

REM 若 junction 指向的目录缺少 han_dog_message，则删除并重建 junction
if exist "%JUNCTION_PATH%\qiongpei_app\pubspec.yaml" (
    if not exist "%JUNCTION_PATH%\han_dog_message\dart\pubspec.yaml" (
        echo [信息] junction 不完整，正在重建...
        rmdir "%JUNCTION_PATH%" 2>nul
    )
)
if not exist "%JUNCTION_PATH%\han_dog_message\dart\pubspec.yaml" (
    echo [信息] 创建 junction: %JUNCTION_PATH% -^> %REAL_PATH%
    if exist "%JUNCTION_PATH%" rmdir "%JUNCTION_PATH%"
    mklink /J "%JUNCTION_PATH%" "%REAL_PATH%"
    if errorlevel 1 (
        echo [错误] junction 创建失败，请以管理员运行或开启开发者模式
        pause
        exit /b 1
    )
)

cd /d "%JUNCTION_PATH%\qiongpei_app"

REM 清理旧的 build 缓存和 ephemeral 文件（避免路径残留）
if exist "build\windows" (
    echo [信息] 清理旧 build 缓存...
    REM 先终止可能正在运行的进程
    taskkill /F /IM qiongpei_app.exe >nul 2>nul
    taskkill /F /IM flutter_windows.dll >nul 2>nul
    REM 等待文件释放
    timeout /t 1 /nobreak >nul 2>nul
    REM 尝试删除，如果失败则提示用户手动关闭应用
    rmdir /s /q "build\windows" 2>nul
    if exist "build\windows" (
        echo [警告] 无法删除 build 缓存，请手动关闭正在运行的 qiongpei_app.exe
        echo [提示] 按任意键继续尝试构建...
        pause >nul
        REM 再次尝试删除
        taskkill /F /IM qiongpei_app.exe >nul 2>nul
        timeout /t 2 /nobreak >nul 2>nul
        rmdir /s /q "build\windows" 2>nul
    )
)

REM 确保 Windows 平台文件存在
if not exist "windows\runner" (
    echo [信息] 添加 Windows 平台支持...
    call flutter create . --platforms=windows
)

REM 获取依赖
echo [1/2] 获取依赖...
call flutter pub get
if errorlevel 1 (
    echo [错误] 依赖获取失败
    pause
    exit /b 1
)

REM 启动应用
echo [2/2] 启动应用...
call flutter run -d windows
pause
