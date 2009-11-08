@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -version=TANGOSVN -profile -O -release -g -J. -Jflags -Jicons -Jres -Xdwt -Xtango -odprofile -L/subsystem:console:4 -L/rc:dwt.res -L/rc:mb.res tango-user-dmd.lib DD-dwt.lib %*
