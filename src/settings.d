/** Load and store settings, stored passwords, etc. */

module settings;

import core.stdc.stdio;
import std.conv;
import std.exception : ErrnoException;
import std.file;
import std.stdio;
import std.string;

import common;
import ini;
import messageboxes;
version (Windows) import mswindows.util;


/// Configuration for a game.
struct GameConfig
{
	string name() const /// Section name in the game config file.
	{
		return name_;
	}

	string mod() const  /// Quake 3 gamename, like "baseq3".  Defaults to name.
	{
		return section.getValue("mod", name);
	}

	string masterServer() const   /// Like "master3.idsoftware.com".
	{
		return section.getValue(
		                       "masterServer", "master.quake3arena.com:27950");
	}

	string protocolVersion() const  /// Defaults to 68.
	{
		return section.getValue("protocolVersion", "68");
	}

	string[] gameTypes() const ///
	{
		string s = section.getValue("gameTypes");

		if (s is null)
			return null;

		string[] r = split(strip(s), " ");

		return r[0].length > 0 ? r : r[0..0];
	}

	string extraServersFile() /// Like "baseq3.extra".
	{
		string base = mod.length > 0 ? mod : name;
		return dataDir ~ base ~ ".extra";
	}

	/**
	 * The path to the game's executable, including the file name.
	 *
	 * The path is looked for in several places, in this order:
	 *
	 * $(OL $(LI regKey + exeName from the game configuration)
	 *      $(LI _exePath from the game configuration)
	 *      $(LI gamePath from settings.ini))
	 */
	string exePath() const
	{
		string path = null;
		string regKey = section["regKey"];
		string exeName = section["exeName"];
		bool badRegKey = false;

		version (Windows) if (regKey && exeName) {
			try {
				if (string dir = getRegistryStringValue(regKey))
					path = dir ~ '\\' ~ exeName;
				else
					log("regKey not found: " ~ regKey);
			}
			catch (Exception e) {
				log(e.toString());
				badRegKey = true;
			}
		}

		if (!path && !badRegKey)
			path = section["exePath"];

		return path ? path : !(regKey || exeName) ? getSetting("gamePath") :
		                                                                  null;
	}

	/// Enable Enemy Territory-style extended color codes (31 colors)?
	/// Off by default.
	bool useEtColors() const
	{
		string r = section["etColors"];
		return r ? (r == "true") : false;
	}

	/// Value to use for Qstat's -cfg parameter.
	string qstatConfigFile() const
	{
		return section.getValue("qstatConfigFile", null);
	}

	/// Qstat master server type.
	string qstatMasterServerType() const
	{
		return section.getValue("qstatMasterServerType", "q3m");
	}

	private string name_;
	private IniSection section;
}


__gshared string[] gameNames;  /// The names of all games loaded from the config file.
shared string gamesFilePath;  /// Name of the file containing options for each game.
shared string backupGamesFilePath;  /// ditto

private {
	shared string settingsFilePath;

	enum defaultGamesFileName = "mods-default.ini";
	enum defaultGamesFileContents = import(defaultGamesFileName);

	__gshared Ini settingsIni;
	__gshared Ini gamesIni;

	struct Setting {
		string name;
		string value;
	}

	enum Setting[] defaults = [
		{"checkForUpdates", "1"},
		{"coloredNames", "true"},
		{"lastMod", ""},
		{"maxTimeouts", "3"},
		{"minimizeOnGameLaunch", "true"},
		{"showExtraColumns", "false"},
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
		{"serverColumnWidths", "27, 250, 21, 32, 50, 40, 90, 130"},
		{"serverColumnOrder", "0, 1, 2, 3, 4, 5, 6, 7"},
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
 * Get configuration for a game.
 *
 * Throws: Exception if no config was found.
 *
 */
GameConfig getGameConfig(string name)
{
	IniSection section = gamesIni[name];

	if (section is null)
		throw new Exception("getGameConfig: non-existant game '" ~ name ~ "'");

	return GameConfig(name, section);
}


/**
 * Add configuration for a new game.
 *
 * Throws: Exception if config was already there for this game.
 *
 */
GameConfig createGameConfig(string name)
{
	if (gamesIni[name] !is null)
		throw new Exception("createGameConfig: preexistant game  '" ~
		                                                           name ~ "'");

	return GameConfig(name, gamesIni.addSection(name));
}


/**
 * Load the game-specific configuration.
 *
 * If the game config file is not found, a default file is created and used
 * instead.
 *
 * This function can be called again to reload the configuration after it has
 * been changed on disk.
 */
void loadGamesFile()
{
	assert(gamesFilePath.length);

	if (!exists(gamesFilePath))
		createGamesFile();
	else if (!gamesIni && getSessionState("programVersion") < "0.9e")
		updateGameConfiguration();

	gamesIni = new Ini(gamesFilePath);

	// remove the nameless section caused by comments
	gamesIni.remove("");

	if (gamesIni.sections.length < 1) {
		// Invalid format, probably the old version.  Just overwrite with
		// defaults and try again.
		createGamesFile();
		gamesIni = new Ini(gamesFilePath);
		gamesIni.remove("");
	}

	gameNames = null;
	foreach (sec; gamesIni) {
		if (sec.name.length > 0)
			gameNames ~= sec.name;
	}
}


private void createGamesFile()
{
	string text = defaultGamesFileContents;

	version (Windows)
		text = replace(text, "%ProgramFiles%", getProgramFilesDirectory());

	try {
		File(gamesFilePath, "w").write(text);
		log("Created %s.", gamesFilePath);
	}
	catch (ErrnoException e) {
		error("Creating \"%s\" failed.  Monster Browser will not function " ~
		      "properly without this file.\n\nError: \"%s\"",
		      gamesFilePath, e);
	}
}


private void createDefaultGamesFile()
{
	if (getSessionState("programVersion") == FINAL_VERSION)
		return;

	string path = dataDir ~ defaultGamesFileName;

	try {
		if (!exists(path)) {
			File(path, "w").write(defaultGamesFileContents);
			log("Created %s.", path);
		}
	}
	catch (ErrnoException e) {
		error("Creating \"%s\" failed.\n\n\"%s\"", path, e);
	}
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
	sec = settingsIni["Settings"];
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

	gamesFilePath = dataDir ~ "mods.ini";
	backupGamesFilePath = gamesFilePath ~ ".autobackup";
	loadGamesFile();

	createDefaultGamesFile();
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

/**
 *
 */
void updateGameConfiguration()
{
	if (exists(gamesFilePath)) {
		try {
			rename(gamesFilePath, backupGamesFilePath);
			info("The game configuration file was replaced.\n\n" ~
			     "Your old configuration was backed up to \"%s\".",
			                                    backupGamesFilePath);
			createGamesFile();
		}
		catch (FileException e) {
			warning("Renaming \"%s\" to \"%s\" failed.  The game " ~
					"configuration was not changed.\n\nError: \"%s\"",
		                         gamesFilePath, backupGamesFilePath, e);
		}
	}
	else {
		createGamesFile();
		info("Created game configuration file.");
	}
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
