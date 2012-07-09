del MonsterBrowser.exe *.obj *.map *.def *.rsp
rmdir /q /s debug debug-gui release release-console profile
if exist svnversion.txt del svnversion.txt
