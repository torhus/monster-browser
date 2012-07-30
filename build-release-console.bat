@svnversion -n . trunk > svnversion.txt
xfbuild src/main.d  -Isrc +oMonsterBrowser +Orelease-console +Drelease-console/.deps -O -release -inline -J. -Jflags -Jicons -Jres +xtango -version=console -L/subsystem:console:4 -L/rc:misc\dwt.res -L/rc:misc\mb.res +full %*
