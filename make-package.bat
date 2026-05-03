@if "%~1"=="" (set BITS=32) else (set BITS=%~1)
@if %BITS%==32 goto ok
@if %BITS%==64 goto ok
@echo Error: argument must be 32 or 64. It defaults to 32 if missing.
@goto end
:ok

@set VERSION=10b

@set FILES=^
CHANGELOG.TXT ^
GeoLite2-Country.mmdb ^
libcurl.dll ^
maxminddb%BITS%.dll ^
MonsterBrowser.exe ^
portable.txt ^
qstat.exe ^
qstat_mb.cfg ^
README.TXT

md package\MonsterBrowser\
unix2dos -k CHANGELOG.TXT portable.txt qstat_mb.cfg README.TXT
for %%f in (%FILES%) do copy %%f package\MonsterBrowser\
cd package
del ..\MonsterBrowser%VERSION%.zip
7z a ..\MonsterBrowser%VERSION%.zip MonsterBrowser
cd ..
rd /S /Q package

:end
