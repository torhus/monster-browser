@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -profile -O -release -g -J. -Xdwt -Xtango -odprofile -L/rc:dwt.res tango-user-dmd.lib DD-dwt.lib %*
