@svnversion . branches/linux > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -gui -profile -O -release -g -J. -Xdwt -Xstd -Xtango -odprofile tangobos.lib tango-user-dmd.lib DD-dwt.lib %*
