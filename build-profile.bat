@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -version=TANGOSVN -profile -O -release -g -J. -Xdwt -Xtango -odprofile -L/rc:dwt.res -L/rc:mb.res tango-user-dmd.lib DD-dwt.lib %*
