@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -O -release -inline -J. -full -Xdwt -Xtango -odrelease-console -L/subsystem:console:4 -L/rc:dwt.res -L/rc:mb.res tango-user-dmd.lib DD-dwt.lib %*
