@echo off


:start
title JSH_Installer
echo ====== JSH ======
if %jsh_installed% equ true (
    echo 1. Uninstall JSH
    echo 2. Veiw README.md/Help
    echo 3. Verify Install
    echo 4. Exit
    set "numls=4"
) else (
    set "numls=2"
    echo 1. Install JSH
    echo 2. Exit
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

if %ans% equ 2 (
    if %jsh_installed% equ true (
        notepad "C:\Program Files\JSH\README.md"
    ) else (
        exit
    )
)

if %ans% equ 3 goto verify

if %ans% equ 4 exit

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
    echo Tip: Use jsh.bat YOUR_ARGS or jsh.ps1 YOUR_ARGS to use JSH
    echo Tip: Relaunch This Installed To Uninstall
    echo Continuing Will Exit The Script.
    pause
    exit
) else (
    echo You Must Have GIT Installed To Continue!
    pause
    cls
    goto start
)

:uninstall
cls
title JSH_Installer_The_Uninstall_Part
echo ====== JSH ======
set /p "ans=Are You Sure You Want To Uninstall JSH? [Y/N]: "
echo Uninstalling JSH
rmdir /s /q "C:\Program Files\JSH"
setx jsh_installed no
echo Done Uninstalling!
echo ====== JSH ======
pause
cls
goto start

:verify
for /f "delims=" %%i in ('jsh.bat -tst') do set "res=%%i"
if %res% equ true (
    echo JSH Seems to be woring
    pause
    cls
    goto start
) else (
    title JSH_Error!
    echo JSH did not respond as expected
    echo Please try re-installing JSH and if the issue
    echo still parsists try opening an issue on the GitHub page
    echo Here: https://github.com/SevereSMP/JSH/issues/new
    echo Continuing Will Send You To The Main Menu
    pause
    cls
    goto start
)