module settings;

/* Load and store settings, and saved passwords. */

private {
	import tango.io.FilePath;
	import tango.text.Util;
	import Integer = tango.text.convert.Integer;
	import tango.stdc.stdio;

	import ini;
	import common;
	import main;
	import serverlist;
}


struct Mod
{
	private IniSection section;

	char[] name;

	char[] masterServer()
	{
		char[] r = section["masterServer"];
		return r ? r : "master3.idsoftware.com";
	}

	char[] serverFile() { return replace(masterServer.dup, ':', '_') ~ ".lst"; }

	char[] extraServersFile() { return name ~ ".extra"; }

	char[] exePath()
	{
		char[] r = section["exePath"];
		return r ? r : getSetting("gamePath");
	}
}


char[][] modNames;
Mod activeMod;
const char[] modFileName = "mods.ini";

private {
	const char[] settingsFileName = "settings.ini";

	const char[] defaultModsFile =
	    "; Monster Browser mods configuration\n"
	    ";\n"
	    "; Just put each mod in square brackets, then you can list options under it, \n"
	    "; like this example:\n"
	    ";\n"
	    "; [mymod]\n"
	    "; masterServer=master.mymod.com\n"
	    "; exePath=C:\\Program Files\\My Mod Directory\\mymod.exe\n"
	    ";\n"
	    "; Lines beginning with a \";\" are comments.\n"
	    "\n"
	    "[westernq3]\n"
	    "\n"
	    "[wop]\n"
	    "masterServer=wopmaster.kickchat.com:27955\n"
	    "exePath=C:\\Program Files\\World of Padman\\wop.exe\n"
	    "\n"
	    "[q3ut4]\n"
	    "masterServer=master.urbanterror.net\n"
	    "\n"
	    "[baseq3]\n\n"
	    "[osp]\n\n"
	    "[cpma]\n\n"
	    "[InstaUnlagged]\n\n";

	Ini settingsIni;
	Ini modsIni;

	struct Setting {
		char[] name;
		char[] value;
	}
	Setting[] defaults = [{"coloredNames", "true"},
	                      {"gamePath",
	                           r"C:\Program Files\Quake III Arena\quake3.exe"},
	                      {"lastMod", "westernq3"},
	                      {"minimizeOnGameLaunch", "true"},
	                      {"startWithLastMod", "true"},
	                      {"windowMaximized", "false"},
	                      {"windowSize", "800x568"},
	                     ];

	Setting[] defaultSessionState = [{"filterState", "0"},
	                                 {"playerSortOrder", "0"},
	                                 {"serverSortOrder", "0"},
	                                 {"middleWeights", "16,5"},
	                                 {"rightWeights", "1,1"},
	                                 {"cvarColumnWidths", "90,90"},
	                                 {"playerColumnWidths", "100,40,40"},
	                                 {"serverColumnWidths", "250,25,32,50,40,90,130"},
	                                ];
}


void setActiveMod(char[] name)
{
	if (modsIni[name] is null)
		modsIni.addSection(name);

	activeMod.name = name;
	activeMod.section = modsIni[name];
}


void loadModFile()
{
	if (!FilePath(modFileName).exists)
		writeDefaultModsFile();

	delete modsIni;
	modsIni = new Ini(modFileName);

	// remove the nameless section caused by comments
	modsIni.remove("");

	if (modsIni.sections.length < 1) {
		// Invalid format, probably the old version.  Just overwrite with defaults
		// and try again.
		writeDefaultModsFile();
		delete modsIni;
		modsIni = new Ini(modFileName);
		modsIni.remove("");
	}

	foreach (sec; modsIni)
		modNames ~= sec.name;

	if (activeMod.name)
		setActiveMod(activeMod.name);
	else
		setActiveMod(modNames[0]);

}


void writeDefaultModsFile()
{
	// Use C IO to get line ending translation.
	FILE* f = fopen((modFileName ~ '\0').ptr, "w");
	fwrite(defaultModsFile.ptr, 1, defaultModsFile.length, f);
	fclose(f);
}

void loadSettings()
{
	settingsIni = new Ini(settingsFileName);
	IniSection sec = settingsIni.addSection("Settings");

	settingsIni.remove(""); // Remove nameless section from v0.1

	// merge the loaded settings with the defaults
	foreach(Setting s; defaults) {
		if (!sec.getValue(s.name)) {
			sec.setValue(s.name, s.value);
		}
	}

	loadSessionState();
	loadModFile();
}


void saveSettings()
{
	if (!mainWindow.getMaximized() && !mainWindow.getMinimized()) {
		char[] width  = Integer.toString(mainWindow.getSize().x);
		char[] height = Integer.toString(mainWindow.getSize().y);
		setSetting("windowSize", width ~ "x" ~ height);
	}
	setSetting("windowMaximized", mainWindow.getMaximized() ?
	                                                 "true" : "false");

	setSetting("lastMod", activeMod.name);

	gatherSessionState();

	if (settingsIni.modified) {
		settingsIni.save();
	}
}


char[] getSetting(char[] key)
{
	assert(settingsIni && settingsIni.sections.length > 0);
	IniSection sec = settingsIni["Settings"];

	assert(sec[key], key ~ " not found.\n\n"
	                  "All settings need to have a default.");
	return sec[key];
}


void setSetting(char[] key, char[] value)
{
	assert(settingsIni && settingsIni.sections.length > 0);
	IniSection sec = settingsIni["Settings"];

	assert(sec[key]);
	sec[key] = value;
}


char[] getPassword(char[] ip)
{
	IniSection sec = settingsIni.section("Passwords");
	if (sec is null)
		return "";
	return sec.getValue(ip, "");
}


void setPassword(char[] ip, char[] password)
{
	IniSection sec = settingsIni.addSection("Passwords");
	sec.setValue(ip, password);
}


private void loadSessionState()
{
	IniSection sec = settingsIni.addSection("Session");

	// merge the loaded settings with the defaults
	foreach(Setting s; defaultSessionState) {
		if (!sec.getValue(s.name)) {
			sec.setValue(s.name, s.value);
		}
	}
}


private void gatherSessionState()
{
	char[] value;
	IniSection sec = settingsIni.section("Session");

	assert(sec !is null);

	// state of filters
	sec.setValue("filterState",
	                       Integer.toString(getActiveServerList.getFilters()));

	// server sort order
	value = Integer.toString(serverTable.sortColumn);
	if (serverTable.sortReversed)
		value ~= "r";
	sec.setValue("serverSortOrder", value);

	// player sort order
	value = Integer.toString(playerTable.sortColumn);
	if (playerTable.sortReversed)
		value ~= "r";
	sec.setValue("playerSortOrder", value);

	// middle SashForm weights
	sec.setValue("middleWeights", toCsv(middleForm.getWeights()));

	// right SashForm weights
	sec.setValue("rightWeights", toCsv(rightForm.getWeights()));

	// cvarColumnWidths
	value = toCsv(getColumnWidths(cvarTable.getTable()));
	sec.setValue("cvarColumnWidths", value);

	// playerColumnWidths
	value = toCsv(getColumnWidths(playerTable.getTable()));
	sec.setValue("playerColumnWidths", value);

	// serverColumnWidths
	value = toCsv(getColumnWidths(serverTable.getTable()));
	sec.setValue("serverColumnWidths", value);
}


char[] getSessionState(in char[] key)
{
	IniSection sec = settingsIni.section("Session");
	assert(sec !is null);
	assert(sec[key], key ~ " not found.\n\n"
	                  "All settings need to have a default.");
	return sec[key];
}
