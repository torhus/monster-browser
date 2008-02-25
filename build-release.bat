@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -gui -O -release -inline -J. -full -Xdwt -Xstd -Xtango -odrelease tangobos.lib tango-user-dmd.lib DD-dwt.lib %*
