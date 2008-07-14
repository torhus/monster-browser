@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -gui -O -release -inline -J. -full -Xdwt -Xtango -odrelease -L/rc:dwt.res -L/rc:mb.res tango-user-dmd.lib DD-dwt.lib  %*
