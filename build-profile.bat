@svnversion -n . trunk > svnversion.txt
xfbuild main.d +oMonsterBrowser +Oprofile +Dprofile/.deps -profile -O -release -J. -Jflags -Jicons -Jres +xtango -version=console -L/subsystem:console:4 -L/rc:dwt.res -L/rc:mb.res %*
