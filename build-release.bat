@svnversion . branches/linux > svnversion.txt
bud -TMonsterBrowser main.d -gui -release -O -inline -J. -Xdwt -Xstd -Xtango -full -clean tangobos.lib tango-user-dmd.lib DD-dwt.lib %*
