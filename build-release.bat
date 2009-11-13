@svnversion -n . trunk > svnversion.txt
xfbuild main.d +oMonsterBrowser +Orelease +Drelease/.deps -O -release -inline -J. -Jflags -Jicons -Jres +xtango -L/subsystem:windows:4 -L/rc:dwt.res -L/rc:mb.res -version=TANGOSVN tango-user-dmd.lib %*
