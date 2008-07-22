/** Load and store settings, stored passwords, etc. */

module settings;

import Path = tango.io.Path;
import tango.text.Util;
import Integer = tango.text.convert.Integer;
import tango.stdc.stdio;

import common;
import ini;
import mainwindow;
import serverlist;


version (Windows) {
	import tango.stdc.stringz;
	import tango.sys.win32.Types;
	enum { CSIDL_PROGRAM_FILES = 38 }
	extern (Windows) BOOL SHGetSpecialFolderPathA(HWND, LPSTR, int, BOOL);
}


/// Access to mod-specific configuration.
struct Mod
{
	char[] name; ///

	char[] masterServer()  ///
	{
		return section.getValue("masterServer", "master3.idsoftware.com");
	}

	char[] serverFile() ///
	{
		return appDir ~ replace(masterServer.dup, ':', '_') ~ ".lst";
	}

	char[] extraServersFile() { return appDir ~ name ~ ".extra"; }  ///

	char[] exePath()  ///
	{
		char[] r = section["exePath"];
		return r ? r : getSetting("gamePath");
	}

	bool useGslist()
	{
		char[] r = section["useGslist"];
		return r ? (r == "true") : true;
	}

	private IniSection section;
}


char[][] modNames;  /// The mod names shown in the mod selection pull-down.
Mod activeMod; /// Configuration for the active mod.
char[] modFileName;  ///

private {
	char[] settingsFileName;

	const char[] defaultModsFile =
	    "; Monster Browser mods configuration\n"
	    ";\n"
	    "; Just put each mod in square brackets, then you can list options under it, \n"
	    "; like this example:\n"
	    ";\n"
	    "; [mymod]\n"
	    "; exePath=%ProgramFiles%\\My Mod Directory\\mymod.exe\n"
	    "; masterServer=master.mymod.com\n"
	    ";\n"
	    "; Lines beginning with a \";\" are comments.\n"
	    "\n"
	    "[westernq3]\n"
	    "\n"
	    "[wop]\n"
	    "exePath=%ProgramFiles%\\World of Padman\\wop.exe\n"
		"useGslist=false\n"
	    "masterServer=wopmaster.kickchat.com:27955\n"
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
	                              r"%ProgramFiles%\Quake III Arena\quake3.exe"},
	                      {"lastMod", "westernq3"},
	                      {"minimizeOnGameLaunch", "true"},
	                      {"showFlags", "true"},
	                      {"startWithLastMod", "true"},
	                      {"windowMaximized", "false"},
	                      {"windowSize", "800x568"},
	                     ];

	Setting[] defaultSessionState = [{"filterState", "0"},
	                                 {"playerSortOrder", "0"},
	                                 {"serverSortOrder", "1"},
	                                 {"middleWeights", "16,5"},
	                                 {"rightWeights", "1,1"},
	                                 {"cvarColumnWidths", "90,90"},
	                                 {"playerColumnWidths", "100,40,40"},
	                                 {"serverColumnWidths",
									              "27,250,21,32,50,40,90,130"},
	                                ];
}


/**
 * Update the activeMod global to contain data for a new mod.
 */
void setActiveMod(char[] name)
{
	if (modsIni[name] is null)
		modsIni.addSection(name);

	activeMod.name = name;
	activeMod.section = modsIni[name];
}


void loadModFile()  ///
{
	assert(modFileName.length);

	if (!Path.exists(modFileName))
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


private void writeDefaultModsFile()
{
	char[] text = defaultModsFile;

	version (Windows)
		text = substitute(text, "%ProgramFiles%", getProgramFilesDirectory());

	// Use C IO to get line ending translation.
	FILE* f = fopen((modFileName ~ '\0').ptr, "w");
	fwrite(text.ptr, 1, text.length, f);
	fclose(f);
}


/**
 * Load program settings, mod configuration, and saved session state.
 */
void loadSettings()
{
	assert(appDir !is null);
	settingsFileName = appDir ~ "settings.ini";

	settingsIni = new Ini(settingsFileName);
	IniSection sec = settingsIni.addSection("Settings");

	settingsIni.remove(""); // Remove nameless section from v0.1

	// merge the loaded settings with the defaults
	foreach(Setting s; defaults) {
		if (!sec.getValue(s.name)) {
			sec.setValue(s.name, s.value);
		}
	}

	// ugly way of guessing q3 install directory
	version (Windows) {
		IniSection sec2 = settingsIni["Settings"];
		char[] value = sec2.getValue("gamePath");
		if (value.length >= 14 && value[0..14] == "%ProgramFiles%") {
			char[] dir = getProgramFilesDirectory();
			value = substitute(value, "%ProgramFiles%", dir);
			sec2.setValue("gamePath", value);
		}
	}

	loadSessionState();

	modFileName = appDir ~ "mods.ini";
	loadModFile();
}


/**
 * Save program settings and session state.
 */
void saveSettings()
{
	if (!mainWindow.maximized && !mainWindow.minimized) {
		char[] width  = Integer.toString(mainWindow.size.x);
		char[] height = Integer.toString(mainWindow.size.y);
		setSetting("windowSize", width ~ "x" ~ height);
	}
	setSetting("windowMaximized", mainWindow.maximized ?
	                                                 "true" : "false");

	setSetting("lastMod", activeMod.name);

	gatherSessionState();

	if (settingsIni.modified) {
		settingsIni.save();
	}
}


char[] getSetting(char[] key) ///
{
	assert(settingsIni && settingsIni.sections.length > 0);
	IniSection sec = settingsIni["Settings"];

	assert(sec[key], key ~ " not found.\n\n"
	                  "All settings need to have a default.");
	return sec[key];
}


void setSetting(char[] key, char[] value) ///
{
	assert(settingsIni && settingsIni.sections.length > 0);
	IniSection sec = settingsIni["Settings"];

	assert(sec[key]);
	sec[key] = value;
}


char[] getPassword(char[] ip) ///
{
	IniSection sec = settingsIni.section("Passwords");
	if (sec is null)
		return "";
	return sec.getValue(ip, "");
}


void setPassword(char[] ip, char[] password) ///
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


char[] getSessionState(in char[] key) ///
{
	IniSection sec = settingsIni.section("Session");
	assert(sec !is null);
	assert(sec[key], key ~ " not found.\n\n"
	                  "All settings need to have a default.");
	return sec[key];
}


/**
 * Get the default program install directory, or an educated guess if not
 * found.
 * 
 * Sample return: "C:\Program Files".
 */
private char[] getProgramFilesDirectory()
{
	char buf[MAX_PATH] = void;
	auto r = SHGetSpecialFolderPathA(null, buf.ptr, CSIDL_PROGRAM_FILES,
																	false);
	assert(r);
	return r ? fromStringz(buf.ptr).dup : "C:\\Program Files".dup;
}
