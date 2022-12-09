@set FILES=^
CHANGELOG.TXT ^
GeoLite2-Country.mmdb ^
libcurl.dll ^
libmaxminddb.dll ^
mods-default.ini ^
MonsterBrowser.exe ^
portable.txt ^
qstat.exe ^
qstat_mb.cfg ^
README.TXT

md package\MonsterBrowser\
unix2dos -k CHANGELOG.TXT mods-default.ini portable.txt qstat_mb.cfg README.TXT
for %%f in (%FILES%) do copy %%f package\MonsterBrowser\
cd package
7z a ..\MonsterBrowser09i.zip MonsterBrowser
cd ..
rd /S /Q package
