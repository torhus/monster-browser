@svnversion -n . trunk > svnversion.txt
xfbuild main.d +oMonsterBrowser +Odebug +Ddebug/.deps -debug -g -J. -Jflags -Jicons -Jres +xtango -L/subsystem:console:4 -L/rc:dwt.res -L/rc:mb.res -version=TANGOSVN tango-user-dmd.lib %*
