@svnversion -n . trunk > svnversion.txt
xfbuild src/main.d -Isrc +oMonsterBrowser +Oprofile +Dprofile/.deps -profile -O -release -J. -Jflags -Jicons -Jres +xtango -version=console -L/subsystem:console:4 -L/rc:misc\dwt.res -L/rc:misc\mb.res %*
