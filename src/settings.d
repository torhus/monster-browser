/**
 * Load and store settings, session state, and stored passwords.
 */

module settings;

import std.algorithm : canFind;
import std.conv;

import common;
import ini;
version (Windows) import mswindows.util;


private {
	shared string settingsFilePath;
	__gshared string[string] exePaths;
	shared bool exePathsUpdated = false;

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
		{"showServersWithNoData", "false"}
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

	loadSessionState();

	if (auto paths = settingsIni.section("Paths")) {
		exePaths = null;
		for (int i = 1;; i++) {
			if (string name = paths[text("game", i)])
				exePaths[name] = paths[text("path", i)];
			else
				break;
		}
	}
}


/**
 * Save program settings and session state.
 */
void saveSettings()
{
	if (getSessionState("programVersion") != FINAL_VERSION)
		setSessionState("programVersion", FINAL_VERSION);

	if (exePathsUpdated) {
		settingsIni.remove("Paths");
		auto sec = settingsIni.addSection("Paths");
		int i = 0;
		foreach (name, path; exePaths) {
			i++;
			sec[text("game", i)] = name;
			sec[text("path", i)] = path;
		}
	}

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


/**
 * Returns the path to the executable for a game, or null if not found.
 *
 * Note: Use GameConfig.exePath instead of this directly.
 */
 string getExePath(string gameName)
 {
	string* path = gameName in exePaths;
	return path ? *path : null;
 }


/**
 * Sets the executable path for a game.
 */
 void setExePath(string gameName, string path)
 {
	exePaths[gameName] = path;
	exePathsUpdated = true;
 }


/**
* Removes executable paths for games not in gameNames.
*/
void pruneExePaths(string[] gameNames)
{
	assert(settingsIni);

	foreach (name; exePaths.keys) {
		if (!gameNames.canFind(name)) {
			exePaths.remove(name);
			exePathsUpdated = true;
		}
	}
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
