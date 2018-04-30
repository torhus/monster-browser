@git describe --always --dirty > revision.txt
xfbuild src/main.d -Isrc +oMonsterBrowser +Odebug-gui +Ddebug-gui/.deps -debug -g -J. -Jflags -Jicons -Jres +xtango -L/subsystem:windows:4 -L/rc:misc\dwt.res -L/rc:misc\mb.res +full %*
