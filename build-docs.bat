@echo off
rem bud main.d -Dddocs -J. -Jflags -Jicons -Jres -full -obj -o- -clean -Xdwt -Xtango -Xphobos -Xlib -Xini -Xlink %*
rem xfbuild main.d -Dddocs +Oddocs +Ddocs/.deps -o- -J. -Jflags -Jicons -Jres +xtango +xdwt +xini %*

setlocal
set files=src/colorednames.d src/common.d src/cvartable.d src/dialogs.d src/flagdata.d misc/genflagdata.d src/geoip.d src/launch.d src/main.d src/mainwindow.d src/masterlist.d src/messageboxes.d src/playertable.d src/qstat.d src/rcon.d src/runtools.d src/serveractions.d src/serverdata.d src/serverlist.d src/serverqueue.d src/servertable.d src/set.d src/settings.d src/threadmanager.d src/mswindows/taskbarlist.d src/mswindows/taskbarprogress.d src/mswindows/util.d
dmd -Isrc -o- -op -Dddocs -J. -Jflags -Jicons -Jres %files%
