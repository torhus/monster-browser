@set FILES=^
CHANGELOG.TXT ^
GeoLite2-Country.mmdb ^
libmaxminddb.dll ^
MonsterBrowser.exe ^
portable.txt ^
qstat.exe ^
qstat_mb.cfg ^
README.TXT

md package\MonsterBrowser\
for %%f in (%FILES%) do copy %%f package\MonsterBrowser\
cd package
7z a ..\MonsterBrowser09d.zip MonsterBrowser
cd ..
rd /S /Q package
