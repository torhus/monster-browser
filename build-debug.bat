@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -oddebug -debug -g -J. -Xdwt -Xtango -L/subsystem:console:4.0 -version=Tango tango-user-dmd.lib debug-DD-dwt.lib %*
