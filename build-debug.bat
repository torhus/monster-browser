@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -oddebug -debug -g -J. -Jflags -Jicons -Jres -Xdwt -Xtango -L/subsystem:console:4 -L/rc:dwt.res -L/rc:mb.res -version=Tango -version=TANGOSVN tango-user-dmd.lib debug-DD-dwt.lib %*
