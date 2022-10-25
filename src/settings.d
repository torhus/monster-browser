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

version (Windows) {
	import core.sys.windows.windows;
	import std.string;
	import std.windows.charset;
	import std.windows.syserror : WindowsException;

	import mswindows.util;
}


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
		return appDir ~ base ~ ".extra";
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
__gshared string gamesFileName;  /// Name of the file containing options for each game.
__gshared string backupGamesFileName;  /// ditto

private {
	__gshared string settingsFileName;

	enum defaultGamesFile =
`; Monster Browser game configuration
;
; Just put each game in square brackets, then you can list options under it.
;
; Available options:
;
; mod     - defaults to being the same as the section name. This is matched
;           against the game and gamename cvars. Set to empty value (mod=) to
;           disable filtering.
; regKey  - need to set exeName too if using this
; exeName - combined with the value found through regKey to form the full path
; exePath - Only used if regKey or exeName are missing. If exePath is missing
;           too, gamePath from the global settings is used instead. This can be
;           set a to shortcut (.lnk) or batch file (.bat) to get more
;           flexibility. In batch files you have to pass MB's arguments to the
;           executable on explicitly, like this: C:\TheGame\game.exe %*
; masterServer    - defaults to master.quake3arena.com:27950.
; protocolVersion - defaults to 68
; gameTypes       - List of game type names, seperated by spaces.
; etColors - Set to true to enable Enemy Territory-style extended color codes (31 colors).
;            See http://wolfwiki.anime.net/index.php/Color_Codes for more information.
; qstatMasterServerType - Defaults to q3m.
; qstatConfigFile - For setting Qstat's -cfg parameter.
;
; Lines beginning with a ";" are comments.

[Smokin' Guns]
mod=smokinguns
regKey=HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Smokin' Guns Productions\Smokin' Guns\InstallPath
exeName=smokinguns.exe
exePath=%ProgramFiles%\Smokin' Guns\smokinguns.exe
masterServer=master.smokin-guns.org
etColors=true

[World of Padman]
mod=WorldofPadman
regKey=HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Padworld Entertainment\World of Padman 1.6.2\Path
exeName=wop.x86_64.exe
exePath=%ProgramFiles%\Padworld Entertainment\World of Padman 1.6.2\wop.x86_64.exe
masterServer=master.worldofpadman.com:27955
protocolVersion=71
qstatMasterServerType=worldofpadmanm
qstatConfigFile=qstat_mb.cfg

[Urban Terror 4.3]
mod=q3ut4
exePath=%ProgramFiles%\UrbanTerror43\Quake3-UrT.exe
masterServer=master.urbanterror.info:27900
gameTypes=FFA LMS 2 TDM TS FTL C&H CTF Bomb Jump FT Gun

[OpenArena]
mod=
exePath=C:\Games\openarena-0.8.8\openarena.exe
masterServer=dpmaster.deathmask.net:27950
protocolVersion=71
gameTypes=FFA 1v1 SP TDM CTF OFC Ovl Harv Elim CTFE LMS DD Dom Pos

[Tremulous]
mod=
regKey=HKEY_LOCAL_MACHINE\SOFTWARE\Tremulous\InstallDir
exeName=tremulous.exe
exePath=%ProgramFiles%\Tremulous\tremulous.exe
masterServer=master.tremulous.net:30710
protocolVersion=69

[Quake III (all servers)]
mod=

[baseq3]

[OSP]
gameTypes=FFA 1v1 SP TDM CTF CA

[CPMA]
gameTypes=FFA 1v1 DA TDM CTF CA FTAG CTFS 2v2

[Excessive Plus]
mod=excessiveplus
gameTypes=FFA 1on1 SP TDM CTF RTF 1FCTF CA FTAG PTL

[DeFRaG]

[Q3Plus]
gameTypes=FFA 1on1 SP TDM CTF RTF 1FCTF CA FTAG PTL

[Rocket Arena 3]
mod=arena
`;

	__gshared Ini settingsIni;
	__gshared Ini gamesIni;

	struct Setting {
		string name;
		string value;
	}

	enum Setting[] defaults = [
		{"checkForUpdates", "1"},
		{"coloredNames", "true"},
		{"lastMod", "Smokin' Guns"},
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
		{"serverColumnWidths", "27, 250, 21, 32, 50, 40, 90, 130"},
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
	assert(gamesFileName.length);

	if (!exists(gamesFileName))
		writeDefaultGamesFile();
	else if (!gamesIni && getSessionState("programVersion") < "0.9e")
		updateGameConfiguration();

	gamesIni = new Ini(gamesFileName);

	// remove the nameless section caused by comments
	gamesIni.remove("");

	if (gamesIni.sections.length < 1) {
		// Invalid format, probably the old version.  Just overwrite with
		// defaults and try again.
		writeDefaultGamesFile();
		gamesIni = new Ini(gamesFileName);
		gamesIni.remove("");
	}

	gameNames = null;
	foreach (sec; gamesIni) {
		if (sec.name.length > 0)
			gameNames ~= sec.name;
	}
}


private void writeDefaultGamesFile()
{
	string text = defaultGamesFile;

	version (Windows)
		text = replace(text, "%ProgramFiles%", getProgramFilesDirectory());

	try {
		File(gamesFileName, "w").write(text);
	}
	catch (ErrnoException e) {
		error("Creating \"%s\" failed.  Monster Browser will not function " ~
		      "properly without this file.\n\nError: \"%s\"",
		      gamesFileName, e);
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
	settingsFileName = dataDir ~ "settings.ini";

	settingsIni = new Ini(settingsFileName);
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

	gamesFileName = dataDir ~ "mods.ini";
	backupGamesFileName = gamesFileName ~ ".autobackup";
	loadGamesFile();
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
private void updateGameConfiguration()
{
	assert(exists(gamesFileName));
	try {
		rename(gamesFileName, backupGamesFileName);
		info("The game configuration was updated.\n\nYour old configuration " ~
		     "was backed up to \"%s\".", backupGamesFileName);
		writeDefaultGamesFile();
	}
	catch (FileException e) {
		warning("Renaming \"%s\" to \"%s\" failed.  The game configuration " ~
		        "was not updated.\n\nError: \"%s\"",
		        gamesFileName, backupGamesFileName, e);
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


/**
 * Get the default program files directory, or an educated guess if not
 * found.
 *
 * Sample return: "C:\Program Files".
 */
version (Windows) private string getProgramFilesDirectory()
{
	try {
		return getSpecialPath!CSIDL_PROGRAM_FILES;
	}
	catch (WindowsException _) {
		return "C:\\Program Files";
	}
}


/**
 * Returns the value of a registry key, or null if there was an error.

 * Throws: Exception if the argument is not a valid key.
 *
 * BUGS: Doesn't convert arguments to ANSI.
 */
version (Windows) private string getRegistryStringValue(in char[] key)
{
	HKEY hKey;
	DWORD dwType = REG_SZ;
	BYTE[255] buf = void;
	LPBYTE lpData = buf.ptr;
	DWORD dwSize = buf.length;
	LONG status;
	const(char)[] retval = null;

	const(char)[][] parts = split(key, "\\");
	if (parts.length < 3)
		throw new Exception("Invalid registry key: " ~ cast(string)key);

	HKEY keyConst = hkeyFromString(parts[0]);
	// cast here because join takes immutable instead of const
	const(char)[] subKey = join(cast(string[])parts[1..$-1], "\\");
	const(char)[] name = parts[$-1];

	status = RegOpenKeyExA(keyConst, cast(char*)toStringz(subKey), 0,
	                                                   KEY_ALL_ACCESS, &hKey);

	if (status == ERROR_SUCCESS) {
		const(char)* namez = toStringz(name);
		status = RegQueryValueExA(hKey, namez, null, &dwType, lpData, &dwSize);

		if (status == ERROR_MORE_DATA) {
			lpData = (new BYTE[dwSize]).ptr;
			status = RegQueryValueExA(hKey, namez, null,
			                                         &dwType, lpData, &dwSize);
		}

		if (status == ERROR_SUCCESS)
			retval = fromMBSz(cast(immutable char*)lpData);

		RegCloseKey(hKey);
	}

	// FIXME: need to cast to void* because of a DMD bug
	return (cast(void*)retval.ptr == cast(void*)buf.ptr) ? retval.idup :
	                                                        cast(string)retval;
}


/// Throws: Exception.
version (Windows) private HKEY hkeyFromString(in char[] s)
{
	if (icmp(s, "HKEY_CLASSES_ROOT") == 0)
		return HKEY_CLASSES_ROOT;
	if (icmp(s, "HKEY_CURRENT_USER") == 0)
		return HKEY_CURRENT_USER;
	if (icmp(s, "HKEY_LOCAL_MACHINE") == 0)
		return HKEY_LOCAL_MACHINE;

	throw new Exception("Invalid HKEY: " ~ cast(string)s);
}
