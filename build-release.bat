@svnversion -n . trunk > svnversion.txt
xfbuild src/main.d -Isrc +oMonsterBrowser +Orelease +Drelease/.deps -O -release -inline -J. -Jflags -Jicons -Jres +xtango -L/subsystem:windows:4 -L/rc:misc\dwt.res -L/rc:misc\mb.res +full %*
