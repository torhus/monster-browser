@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -oddebug -debug -g -J. -Xdwt -Xtango -L/subsystem:console:4.0 -L/rc:dwt.res -version=Tango tango-user-dmd.lib debug-DD-dwt.lib %*
