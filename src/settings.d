/**
 * Load and store settings, session state, and stored passwords.
 */

module settings;

import std.conv;

import common;
import ini;
version (Windows) import mswindows.util;


private {
	shared string settingsFilePath;

	__gshared Ini settingsIni;

	struct Setting {
		string name;
		string value;
	}

	enum Setting[] defaults = [
		{"checkForUpdates", "1"},
		{"coloredNames", "true"},
		{"geoIpDatabase", "GeoLite2-Country.mmdb"},
		{"lastMod", ""},
		{"maxTimeouts", "3"},
		{"minimizeOnGameLaunch", "true"},
		{"showFlags", "true"},
		{"simultaneousQueries", "10"},
		{"startWithLastMod", "true"},
		{"startupAction", "1"},
		{"windowMaximized", "false"},
	];

	enum Setting[] defaultSessionState = [
		{"programVersion", "0.0"},
		{"filterState", "0"},
		{"searchType", "0"},
		{"playerSortOrder", "0"},
		{"resolution", "0, 0"},
		{"serverSortOrder", "1"},
		{"middleWeights", "16, 5"},
		{"rightWeights", "1, 1"},
		{"cvarColumnWidths", "90, 90"},
		{"playerColumnWidths", "100, 40, 40"},
		{"serverColumnWidths", "27, 250, 21, 32, 50, 40, 30, 90, 130, 80, 80"},
		{"serverColumnsShown", "1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0"},
		{"serverColumnOrder", "0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10"},
		{"windowPosition", "150, 150"},
		// No default width, calculated on first startup.
		{"windowSize", "-1, 640"},
		{"rconWindowPosition", "100, 100"},
		{"rconWindowSize", "640, 480"},
		{"addServersAsPersistent", "true"},
		{"saveRconPasswords", "true"},
		{"saveServerPasswords", "true"},
	];
}


/**
 * Load program settings, games configuration, and saved session state.
 *
 * Missing settings are replaced by defaults, this also happens if the config
 * file is missing altogether.
 *
 * If the "gamePath" setting is missing, attempts to find quake3.exe by looking
 * in the registry.  If that fails, a sensible default is used.
 */
void loadSettings()
{
	assert(dataDir.length);
	settingsFilePath = dataDir ~ "settings.ini";

	settingsIni = new Ini(settingsFilePath);
	IniSection sec = settingsIni.addSection("Settings");

	settingsIni.remove(""); // Remove nameless section from v0.1

	// merge the loaded settings with the defaults
	foreach(Setting s; defaults) {
		if (!sec.getValue(s.name)) {
			sec.setValue(s.name, s.value);
		}
	}

	// make sure we have a path for quake3.exe
	if (!sec.getValue("gamePath")) {
		string path;
		version (Windows) {	
			path = autodetectQuake3Path();			
		}
		else {
			// FIXME: need linux default
			path = "~/dev/test";
		}
		sec.setValue("gamePath", path);
		log("Set gamePath to '" ~ path ~ "'.");
	}

	loadSessionState();
}


/**
 * Save program settings and session state.
 */
void saveSettings()
{
	if (getSessionState("programVersion") != FINAL_VERSION)
		setSessionState("programVersion", FINAL_VERSION);

	if (settingsIni.modified) {
		settingsIni.save();
	}
}


/**
 * Returns the setting's value, or a default if not set.
 */
string getSetting(in char[] key)
{
	return getSetting("Settings", key);
}


/**
 * Returns the setting's value, or a default if not set.
 *
 * Throws: IllegalArgumentException if the value is not an int.
 */
int getSettingInt(in char[] key)
{
	return getSettingInt("Settings", defaults, key);
}


/**
 * Set a setting.
 *
 * Will assert in debug mode if a non-existent key is given.
 */
void setSetting(string key, string value)
{
	setSetting("Settings", key, value);
}


/**
 * Retrieve a stored password.
 *
 * ip is an IP address, with an optional colon and port number at the end.
 *
 * Returns: The password, or an empty string if none was found.
 */
string getPassword(in char[] ip)
{
	IniSection sec = settingsIni.section("Passwords");
	if (sec is null)
		return "";
	return sec.getValue(ip, "");
}


/// Stores server passwords for later retrieval by getPassword().
void setPassword(string ip, string password)
{
	IniSection sec = settingsIni.addSection("Passwords");
	sec.setValue(ip, password);
}


/// Removes the password stored for a server.
void removePassword(in char[] ip)
{
	IniSection sec = settingsIni.section("Passwords");
	if (sec !is null)
		sec.remove(ip);
}


/**
 * Retrieve a stored rcon password.
 *
 * ip is an IP address, with an optional colon and port number at the end.
 *
 * Returns: The password, or an empty string if none was found.
 */
string getRconPassword(in char[] ip)
{
	IniSection sec = settingsIni.section("RconPasswords");
	if (sec is null)
		return "";
	return sec.getValue(ip, "");
}


/// Stores rcon passwords for later retrieval by getRconPassword().
void setRconPassword(string ip, string password)
{
	IniSection sec = settingsIni.addSection("RconPasswords");
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


/**
 * Returns the setting's value, or a default if not set.
 */
string getSessionState(in char[] key)
{
	return getSetting("Session", key);
}


/**
 * Set a session state setting.
 *
 * Will assert in debug mode if a non-existent key is given.
 */
void setSessionState(in char[] key, string value)
{
	setSetting("Session", key, value);
}


/**
 * Returns the setting's value, or a default if not set.
 *
 * Throws: IllegalArgumentException if the value is not an int.
 */
int getSessionStateInt(in char[] key)
{
	return getSettingInt("Session", defaultSessionState, key);
}


private string autodetectQuake3Path()
{
	version (Windows) {
		string q3path = getRegistryStringValue("HKEY_LOCAL_MACHINE\\" ~
		                      "SOFTWARE\\Id\\Quake III Arena\\INSTALLEXEPATH");
		if (!q3path) {
			log("Quake 3's installation path was not found in the registry, " ~
		                                   "falling back to a default value.");
			// use a sensible default value
			q3path = getProgramFilesDirectory();
			q3path ~= "\\Quake III Arena\\quake3.exe";
		}
		return q3path;
	}
	else {
		assert(0, "autodetectQuake3Path");
	}
}


private string getDefault(in Setting[] defaults, in char[] key)
{
	foreach (s; defaults)
	{
		if (s.name == key)
			return s.value;
	}
	assert(0);
}


private string getSetting(in char[] section, in char[] key)
{
	assert(settingsIni && settingsIni.sections.length > 0);
	IniSection sec = settingsIni[section];

	assert(sec !is null);
	assert(sec[key], key ~ " not found in section " ~ section ~ ".\n\n" ~
	                  "All settings need to have a default.");
	return sec[key];
}


private int getSettingInt(in char[] section, in Setting[] defaults,
                                                                 in char[] key)
{
	try {
		return to!int(getSetting(section, key));
	}
	catch (ConvException e)
	{
		return to!int(getDefault(defaults, key));
	}
}


private void setSetting(in char[] section, in char[] key, string value)
{
	assert(settingsIni && settingsIni.sections.length > 0);
	IniSection sec = settingsIni[section];

	assert(sec[key]);
	sec[key] = value;
}
