@echo off
setlocal

(
    git rev-parse --abbrev-ref HEAD
    echo :
    git describe --always --dirty
) > revision.txt

if "%1" == "" goto usage
if "%1" == "debug" (set DEBUG=true & goto build)
if "%1" == "debug-console" (set DEBUG=true & set CONSOLE=true & goto build)
if "%1" == "release" (set RELEASE=true & goto build)
if "%1" == "release-console" (set RELEASE=true & set CONSOLE=true & goto build)
if "%1" == "release-final" (set RELEASE=true & set FINAL=true & goto build)
if "%1" == "profile" (set PROFILE=true & set CONSOLE=true & goto build)
goto usage

:build
if defined DEBUG set FLAGS=-debug -g
if defined RELEASE set FLAGS=-O -release -inline
if defined FINAL set FLAGS=%FLAGS% -version=Final
if defined PROFILE set FLAGS=-profile -O -release
if defined CONSOLE (
    set SUBSYSTEM=-version=console -L/subsystem:console:4
) else (
    set SUBSYSTEM=-L/subsystem:windows:4
)

echo on
xfbuild src/main.d -Isrc +oMonsterBrowser +Obuild +Dbuild/.deps %FLAGS% -J. -Jflags -Jicons -Jres +xtango %SUBSYSTEM% -L/rc:misc\dwt.res -L/rc:misc\mb.res +full %2 %3 %4 %5
@echo off
goto end:

:usage
echo Please specify a build type, valid choices are:
echo debug, debug-console, release, release-console, release-final, and profile.
exit /b 1

:end
