@echo off
setlocal enabledelayedexpansion

rem 检查是否有未暂存的更改
for /f "delims=" %%i in ('git status --porcelain') do (
    set unstaged_changes=1
    goto :end_check
)
:end_check
if not defined unstaged_changes (
    echo No changes to commit.
    exit
) else (
    git add .
    git status
    echo ========= Enter commit msg, or press enter for "auto commit" =========
    set "yy=!date:~0,10! !time:~0,2!:%time:~3,2!"
    set /p "msg="
    if "!msg!"=="" (
        git commit -m "auto commit !yy!"
    ) else (
        git commit -m "!msg!"
    )
)

rem 获取远程仓库的最新更改并合并
git fetch gitee
if errorlevel 1 (
    echo Failed to fetch from gitee.
    exit
)

git merge
if errorlevel 1 (
    echo Merge conflict detected. Please resolve conflicts and try again.
    exit
)

git push gitee
if errorlevel 1 (
    echo Failed to push to gitee.
    exit
)

git push github
if errorlevel 1 (
    echo Failed to push to github.
    exit
)

pause