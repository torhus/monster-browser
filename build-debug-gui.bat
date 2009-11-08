@svnversion -n . trunk > svnversion.txt 
bud -TMonsterBrowser main.d -oddebug-gui -debug -g -gui -J. -Jflags -Jicons -Jres -Xdwt -Xtango -version=Tango -version=TANGOSVN -version=redirect -L/rc:dwt.res -L/rc:mb.res tango-user-dmd.lib debug-DD-dwt.lib %*
