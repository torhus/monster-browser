@set FILES=^
CHANGELOG.TXT ^
GeoLite2-Country.mmdb ^
libcurl.dll ^
libmaxminddb.dll ^
MonsterBrowser.exe ^
portable.txt ^
qstat.exe ^
qstat_mb.cfg ^
README.TXT

md package\MonsterBrowser\
unix2dos -k CHANGELOG.TXT portable.txt qstat_mb.cfg README.TXT
for %%f in (%FILES%) do copy %%f package\MonsterBrowser\
cd package
7z a ..\MonsterBrowser10a.zip MonsterBrowser
cd ..
rd /S /Q package
