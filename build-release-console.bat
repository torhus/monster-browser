@svnversion -n . trunk > svnversion.txt
xfbuild main.d +oMonsterBrowser +Orelease-console +Drelease-console/.deps -O -release -inline -J. -Jflags -Jicons -Jres +xtango -L/subsystem:console:4 -L/rc:dwt.res -L/rc:mb.res -version=TANGOSVN %*
