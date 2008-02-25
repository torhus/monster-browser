@svnversion -n . trunk > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -profile -O -release -g -J. -Xdwt -Xstd -Xtango -odprofile tangobos.lib tango-user-dmd.lib DD-dwt.lib %*
