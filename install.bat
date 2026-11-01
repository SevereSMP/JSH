@echo off
title JSH_Installer

:start
echo ====== JSH ======
if %jsh_installed% equ true (
    echo 1. Uninstall JSH
    echo 2. Veiw HELP.md
    echo 3. Verify Install
    set "numls=3"
) else (
    set "numls=1"
    echo 1. Install JSH
)
echo ====== JSH ======
set /p "ans=Enter One Of The Above [1-%numls%]: "

if %ans% equ 1 (
    if %jsh_installed% equ true (
        goto uninstall
    ) else (
        goto install
    )
)

echo Thats Not A Valid Option
cls
goto start

:install
cls
title JSH_Installer_The_Install_Part

echo ====== JSH ======
set /p "ans=Do You Have GIT installed? [Y/N]: "

if %ans% equ y (
    echo cloning Git Repo...
    git clone -q https://github.com/SevereSMP/JSH.git "C:\Program Files\JSH" >nul 2>&1
    echo Done.
    echo Configureing ENVs
    setx jsh_installed true
    setx /M PATH "%PATH%;C:\Program Files\JSH\core"
    echo Done Installing!
    echo Continuing Will Exit The Script.
    pause
    exit
) else (
    echo You Must Have GIT Installed To Continue!
    pause
    cls
    goto start
)