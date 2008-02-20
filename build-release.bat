@svnversion . branches/linux > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -version=UseOldProcess -gui -O -release -inline -J. -full -Xdwt -Xstd -Xtango -odrelease tangobos.lib tango-user-dmd.lib DD-dwt.lib %*
