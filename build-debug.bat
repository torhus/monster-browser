@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -oddebug -debug -g TangoTrace2.d -J. -Jres -Xdwt -Xtango -L/subsystem:console:4.0 -L/rc:dwt.res -L/rc:mb.res -version=Tango -version=TANGOSVN tango-user-dmd.lib debug-DD-dwt.lib %*
