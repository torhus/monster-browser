@svnversion -n . trunk > svnversion.txt
xfbuild src/main.d +oMonsterBrowser +Oprofile +Dprofile/.deps -profile -O -release -J. -Jflags -Jicons -Jres +xstd +xcore -L/subsystem:console:4 -L/rc:dwt.res -L/rc:mb.res +full %*
