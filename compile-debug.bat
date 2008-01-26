call clean.bat

@echo off
rem set args = -L/subsystem:windows:5 

dmd -debug -version=OLE_COM -ofMonsterBrowser main.d cvartable.d dialogs.d ini.d qstat.d settings.d lib/process.d lib/pipestream.d monitor.d parselist.d playertable.d serverlist.d servertable.d common.d  launch.d dwtd.lib advapi32.lib comctl32.lib gdi32.lib shell32.lib comdlg32.lib ole32.lib uuid.lib user32_dwt.lib imm32_dwt.lib shell32_dwt.lib msimg32_dwt.lib gdi32_dwt.lib kernel32_dwt.lib usp10_dwt.lib olepro32_dwt.lib oleaut32_dwt.lib oleacc_dwt.lib
MonsterBrowser.exe
