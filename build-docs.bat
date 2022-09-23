@echo off
rem xfbuild src/main.d -Isrc -Ddocs +Odocs +Ddocs/.deps -o- -J. -Jflags -Jicons -Jres +xtango +xdwt +xini %*

setlocal
set files=^
misc/genflagdata.d ^
src/colorednames.d ^
src/common.d ^
src/cvartable.d ^
src/dialogs.d ^
src/flagdata.d ^
src/geoip.d ^
src/ini.d ^
src/launch.d ^
src/main.d ^
src/mainwindow.d ^
src/masterlist.d ^
src/maxminddb.d ^
src/messageboxes.d ^
src/playertable.d ^
src/qstat.d ^
src/rcon.d ^
src/runtools.d ^
src/serveractions.d ^
src/serverdata.d ^
src/serverlist.d ^
src/serverqueue.d ^
src/servertable.d ^
src/set.d ^
src/settings.d ^
src/threadmanager.d ^
src/mswindows/taskbarlist.d ^
src/mswindows/taskbarprogress.d

dmd -Isrc -o- -op -Dddocs -J. -Jflags -Jicons -Jres %files%
