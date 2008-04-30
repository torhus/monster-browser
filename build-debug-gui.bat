@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -oddebug-gui -debug -g -gui -J. -Xdwt -Xtango -version=Tango -version=redirect tango-user-dmd.lib debug-DD-dwt.lib %*
