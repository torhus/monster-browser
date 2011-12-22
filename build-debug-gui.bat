@svnversion -n . trunk > svnversion.txt 
xfbuild main.d +oMonsterBrowser +Odebug-gui +Ddebug-gui/.deps -debug -g -J. -Jflags -Jicons -Jres +xtango -L/subsystem:windows:4 -L/rc:dwt.res -L/rc:mb.res %*
