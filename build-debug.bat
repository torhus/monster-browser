@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -oddebug -debug -g -J. -Jres -Xorg -Xjava -Xtango -L/subsystem:console:4.0 -L/rc:dwt.res -L/rc:mb.res -version=Tango tango-user-dmd.lib dwt-base-debug.lib dwt-debug.lib %*
