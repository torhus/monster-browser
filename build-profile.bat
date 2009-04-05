@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -profile -O -release -g -J. -Jres -Xjava -Xorg -Xtango -odprofile -L/subsystem:console:4 -L/rc:dwt.res -L/rc:mb.res tango-user-dmd.lib dwt-base.lib dwt.lib %*
