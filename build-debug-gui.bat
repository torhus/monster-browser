@svnversion -n . trunk > svnversion.txt 
bud -TMonsterBrowser main.d -oddebug-gui -debug -g -gui -J. -Jres -Xjava -Xorg -Xtango -version=Tango -version=redirect -L/rc:dwt.res -L/rc:mb.res tango-user-dmd.lib dwt-base-debug.lib dwt-debug.lib %*
