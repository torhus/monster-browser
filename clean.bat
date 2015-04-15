del MonsterBrowser.exe *.obj *.map *.def *.rsp
rmdir /q /s debug debug-gui release release-console profile
if exist revision.txt del revision.txt
