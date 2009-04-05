@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -O -release -inline -J. -Jres -full -Xjava -Xorg -Xtango -odrelease-console -L/subsystem:console:4 -L/rc:dwt.res -L/rc:mb.res tango-user-dmd.lib dwt-base.lib dwt.lib %*
