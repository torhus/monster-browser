@svnversion -n . trunk > svnversion.txt 
bud -TMonsterBrowser main.d -oddebug-gui -debug -g TangoTrace2.d -gui -J. -Xdwt -Xtango -version=Tango -version=redirect -L/rc:dwt.res -L/rc:mb.res tango-user-dmd.lib debug-DD-dwt.lib %*
