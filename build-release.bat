@svnversion -n . trunk > svnversion.txt
xfbuild main.d +oMonsterBrowser +Orelease +Drelease/.deps -O -release -inline -J. -Jflags -Jicons -Jres +xstd +xcore -L/subsystem:windows:4 -L/rc:dwt.res -L/rc:mb.res +full %*
