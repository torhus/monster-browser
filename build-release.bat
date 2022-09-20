@svnversion -n . trunk > svnversion.txt
xfbuild src/main.d -Isrc +oMonsterBrowser +Orelease +Drelease/.deps -O -release -inline -J. -Jflags -Jicons -Jres +xstd +xcore -L/subsystem:windows:4 -L/rc:dwt.res -L/rc:mb.res +full %*
