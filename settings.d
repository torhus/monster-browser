/** Load and store settings, stored passwords, etc. */

module settings;

import Path = tango.io.Path;
import tango.text.Util;
import Integer = tango.text.convert.Integer;
import tango.stdc.stdio;

import common;
import cvartable;
import ini;
import playertable;
import mainwindow;
import serverlist;
import servertable;

version (Windows) {
	import tango.stdc.stringz;
	import tango.sys.win32.CodePage;
	import tango.sys.win32.UserGdi;

	enum { CSIDL_PROGRAM_FILES = 38 }
	extern (Windows) BOOL SHGetSpecialFolderPathA(HWND, LPSTR, int, BOOL);
	const HKEY HKEY_LOCAL_MACHINE = cast(HKEY)0x80000002;
}


/// Access to mod-specific configuration.
struct Mod
{
	char[] name; /// Quake 3 gamename, like "baseq3".

	char[] masterServer()  /// Like "master3.idsoftware.com".
	{
		return section.getValue("masterServer", "master3.idsoftware.com");
	}

	char[] serverFile() /// Like "master3.idsoftware.com.lst".
	{
		return appDir ~ replace(masterServer.dup, ':', '_') ~ ".lst";
	}

	char[] extraServersFile() /// Like "baseq3.extra".
	{
		return appDir ~ name ~ ".extra";
	}

	/**
	 * Returns exePath from the mod-specific configuration, or gamePath from
	 * settings.ini if the former is not set.
	 */
	char[] exePath()
	{
		char[] r = section["exePath"];
		return r ? r : getSetting("gamePath");
	}

	bool useGslist() /// Use gslist instead of qstat when querying master?
	{
		char[] r = section["useGslist"];
		return r ? (r == "true") : true;
	}

	private IniSection section;
}


char[][] modNames;  /// The names of all mods loaded from the mod config file.
char[] modFileName;  /// Name of the file containing options for each mod.

private {
	char[] settingsFileName;

	const char[] defaultModsFile =
	    "; Monster Browser mods configuration\n"
	    ";\n"
	    "; Just put each mod in square brackets, then you can list options under it, \n"
	    "; like this example:\n"
	    ";\n"
	    "; [mymod]\n"
	    "; exePath=C:\\Program Files\\My Mod Directory\\mymod.exe\n"
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
 * Get configuration for a mod.
 *
 * Throws: Exception if no config was found.
 *
 */
Mod getModConfig(in char[] name)
{
	Mod mod;
	
	mod.name = name;
	mod.section = modsIni[name];
	
	if (mod.section is null)
		throw new Exception("getModConfig: non-existant mod");
	
	return mod;
}


/**
 * Add configuration for a new mod.
 *
 * Throws: Exception if config was already there for this mod.
 *
 */
Mod createModConfig(in char[] name)
{
	Mod mod;

	if (modsIni[name] !is null)
		throw new Exception("createModConfig: preexistant mod name");

	mod.section = modsIni.addSection(name);
	mod.name = name;
	return mod;
}


/**
 * Load the mod-specific configuration.
 *
 * Updates the activeMod global, setting it to the first mod found in the
 * config file if it wasn't set already.
 *
 * If the mod config file is not found, a default file is created and used
 * instead.
 *
 * This function can be called again to reload the configuration after it has
 * been changed on disk.
 */
void loadModFile()
{
	assert(modFileName.length);

	if (!Path.exists(modFileName))
		writeDefaultModsFile();

	delete modsIni;
	modsIni = new Ini(modFileName);

	// remove the nameless section caused by comments
	modsIni.remove("");

	if (modsIni.sections.length < 1) {
		// Invalid format, probably the old version.  Just overwrite with
		// defaults and try again.
		writeDefaultModsFile();
		delete modsIni;
		modsIni = new Ini(modFileName);
		modsIni.remove("");
	}

	foreach (sec; modsIni)
		modNames ~= sec.name;
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
 *
 * Missing settings are replaced by defaults, this also happens if the config
 * file is missing altogether.
 *
 * If the "gamePath" setting is missing, attempts to find quake3.exe by looking
 * in the registry.  If that fails, a sensible default is used.
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

	version (Windows) {
		// make sure we have a path for quake3.exe
		sec = settingsIni["Settings"];
		if (!sec.getValue("gamePath")) {
			char[] path = autodetectQuake3Path();
			sec.setValue("gamePath", path);
			log("Set gamePath to '" ~ path ~ "'.");
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
	if (!mainWindow.maximized) {
		char[] width  = Integer.toString(mainWindow.size.x);
		char[] height = Integer.toString(mainWindow.size.y);
		setSetting("windowSize", width ~ "x" ~ height);
	}
	setSetting("windowMaximized", mainWindow.maximized ?
	                                                 "true" : "false");

	setSetting("lastMod", filterBar.selectedMod);

	gatherSessionState();

	if (settingsIni.modified) {
		settingsIni.save();
	}
}


/**
 * Returns the setting's value, or a default if not set.
 *
 * Will assert in debug mode if a non-existent key is given.
 */
char[] getSetting(in char[] key)
{
	assert(settingsIni && settingsIni.sections.length > 0);
	IniSection sec = settingsIni["Settings"];

	assert(sec[key], key ~ " not found.\n\n"
	                  "All settings need to have a default.");
	return sec[key];
}


/**
 * Set a setting.
 *
 * Will assert in debug mode if a non-existent key is given.
 */
void setSetting(char[] key, char[] value)
{
	assert(settingsIni && settingsIni.sections.length > 0);
	IniSection sec = settingsIni["Settings"];

	assert(sec[key]);
	sec[key] = value;
}


/**
 * Retrieve a stored password.
 *
 * ip is an IP address, with an optional colon and port number at the end.
 *
 * Returns: The password, or an empty string if none was found.
 */
char[] getPassword(in char[] ip)
{
	IniSection sec = settingsIni.section("Passwords");
	if (sec is null)
		return "";
	return sec.getValue(ip, "");
}


/// Stores server passwords for later retrieval by getPassword().
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
	                Integer.toString(serverTable.getServerList().getFilters()));

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


/**
 * Returns the setting's value, or a default if not set.
 *
 * Will assert in debug mode if a non-existent key is given.
 */
char[] getSessionState(in char[] key)
{
	IniSection sec = settingsIni.section("Session");
	assert(sec !is null);
	assert(sec[key], key ~ " not found.\n\n"
	                  "All settings need to have a default.");
	return sec[key];
}


private char[] autodetectQuake3Path()
{
	version (Windows) {
		char[] q3path = getRegistryStringValue(HKEY_LOCAL_MACHINE,
		                                       "SOFTWARE\\Id\\Quake III Arena",
		                                       "INSTALLEXEPATH");
		if (!q3path) {
			log("Quake 3's installation path was not found in the registry, "
		                                   "falling back to a default value.");
			// use a sensible default value
			q3path = getProgramFilesDirectory;
			q3path ~= "\\Quake III Arena\\quake3.exe";
		}
		return q3path;

	}
	else {
		assert(0, "autodetectQuake3Path");
	}
}

/**
 * Get the default program install directory, or an educated guess if not
 * found.
 * 
 * Sample return: "C:\Program Files".
 */
private char[] getProgramFilesDirectory()
{
	char buf[MAX_PATH];
	auto r = SHGetSpecialFolderPathA(null, buf.ptr, CSIDL_PROGRAM_FILES,
	                                                                    false);
	assert(r);
	return r ? fromStringz(buf.ptr).dup : "C:\\Program Files".dup;
}


// BUGS: Doesn't convert arguments to ANSI.
private char[] getRegistryStringValue(HKEY key, in char[] subKey,
                                                                in char[] name)
{
	HKEY hKey;
	DWORD dwType = REG_SZ;
	BYTE buf[255] = void;
	LPBYTE lpData = buf.ptr;
	DWORD dwSize = buf.length;
	LONG status;
	char[] retval = null;

	status = RegOpenKeyExA(key, toStringz(subKey), 0L, KEY_ALL_ACCESS, &hKey);

	if (status == ERROR_SUCCESS) {
		status = RegQueryValueExA(hKey, toStringz(name), NULL, &dwType, lpData,
		                                                              &dwSize);

		if (status == ERROR_MORE_DATA) {
			lpData = (new BYTE[dwSize]).ptr;
			status = RegQueryValueExA(hKey, toStringz(name), NULL, &dwType,
			                                                  lpData, &dwSize);
		}
		
		if (status == ERROR_SUCCESS) {
			retval.length = dwSize * 2;
			retval = CodePage.from(fromStringz(cast(char*)lpData), retval);
		}
		
		if (dwSize > buf.length)
			delete lpData;
		
		RegCloseKey(hKey);
	}

	return retval;
}
