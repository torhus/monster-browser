@svnversion -n . trunk > svnversion.txt
xfbuild main.d +oMonsterBrowser +Odebug +Ddebug/.deps -debug -g -J. -Jflags -Jicons -Jres +xstd +xcore -L/subsystem:console:4 -L/rc:dwt.res -L/rc:mb.res %*
