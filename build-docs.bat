@echo off
rem bud main.d -Dddocs -J. -Jflags -Jicons -Jres -full -obj -o- -clean -version=TANGOSVN -Xdwt -Xtango -Xphobos -Xlib -Xini -Xlink %*
rem xfbuild main.d -Dddocs +Oddocs +Ddocs/.deps -o- -J. -Jflags -Jicons -Jres +xtango +xdwt +xini -version=TANGOSVN %*

setlocal
set files=colorednames.d common.d cvartable.d dialogs.d flagdata.d genflagdata.d geoip.d launch.d link.d main.d mainwindow.d masterlist.d messageboxes.d playertable.d qstat.d rcon.d runtools.d serveractions.d serverdata.d serverlist.d serverqueue.d servertable.d set.d settings.d threadmanager.d mswindows/taskbarlist.d mswindows/taskbarprogress.d mswindows/util.d
dmd -o- -op -Dddocs -J. -Jflags -Jicons -Jres %files%
