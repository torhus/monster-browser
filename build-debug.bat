@svnversion . branches/linux > svnversion.txt
bud -TMonsterBrowser main.d -version=Tango -version=UseOldProcess -oddebug -debug -g -J. -Xdwt -Xstd -Xtango -L/subsystem:console:4.0 -version=Tango tangobos.lib tango-user-dmd.lib debug-DD-dwt.lib %*
