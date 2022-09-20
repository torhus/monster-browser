@svnversion -n . trunk > svnversion.txt
xfbuild src/main.d +oMonsterBrowser +Orelease-console +Drelease-console/.deps -O -release -inline -J. -Jflags -Jicons -Jres +xstd +xcore -version=console -L/subsystem:console:4 -L/rc:dwt.res -L/rc:mb.res +full %*
