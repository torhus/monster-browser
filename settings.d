/** Load and store settings, stored passwords, etc. */

module settings;

import core.stdc.stdio;
import std.conv;
import std.file;
import std.string;

import common;
import ini;

version (Windows) {
	import std.string;
	import tango.sys.win32.CodePage;
	import tango.sys.win32.SpecialPath;
	import tango.sys.win32.UserGdi;

	const HKEY_CLASSES_ROOT  = cast(HKEY)0x80000000;
	const HKEY_CURRENT_USER  = cast(HKEY)0x80000001;
	const HKEY_LOCAL_MACHINE = cast(HKEY)0x80000002;
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

	string masterServer() const  /// Like "master3.idsoftware.com".
	{		
		return section.getValue("masterServer", "master3.idsoftware.com");
	}

	string protocolVersion() const  /// Defaults to 68.
	{
		return section.getValue("protocolVersion", "68");
	}

	string extraServersFile() const /// Like "baseq3.extra".
	{
		return appDir ~ mod ~ ".extra";  // FIXME: check dataDir too?
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

	/// Use gslist instead of qstat when querying master?
	bool useGslist() const
	{
		string r = section["useGslist"];
		return r ? (r == "true") : true;
	}

	/// Enable Enemy Territory-style extended color codes (31 colors)?
	bool useEtColors() const
	{
		// just testing for now
		return arguments.colortest && mod == "smokinguns";
	}

	private string name_;
	private IniSection section;
}


/// The names of all games loaded from the config file.
__gshared string[] gameNames;
/// Name of the file containing options for each game.
__gshared string gamesFileName;

private {
	__gshared string settingsFileName;

	enum defaultGamesFile =
`; Monster Browser game configuration
;
; Just put each game in square brackets, then you can list options under it.
;
; Available options:
;
; mod     - defaults to being the same as the section name
; regKey  - need to set exeName too if using this
; exeName - combined with the value found through regKey to form the full path
; exePath - Only used if regKey or exeName are missing. If exePath is missing
;           too, gamePath from the global settings is used instead.
;           example: exePath=C:\Program Files\My Game\mygame.exe
; masterServer    - defaults to master3.idsoftware.com
; protocolVersion - defaults to 68
;
; Lines beginning with a ";" are comments.

[Smokin' Guns]
mod=smokinguns
regKey=HKEY_LOCAL_MACHINE\SOFTWARE\Smokin' Guns Productions\Smokin' Guns\InstallPath
exeName=smokinguns.exe
exePath=%ProgramFiles%\Smokin' Guns\smokinguns.exe

[World of Padman]
mod=wop
regKey=HKEY_LOCAL_MACHINE\SOFTWARE\World of Padman\Path
exeName=wop.exe
exePath=%ProgramFiles%\World of Padman\wop.exe
useGslist=false
masterServer=wopmaster.kickchat.com:27955

[Urban Terror]
mod=q3ut4
masterServer=master.urbanterror.net

[Tremulous]
mod=base
regKey=HKEY_LOCAL_MACHINE\SOFTWARE\Tremulous\InstallDir
exeName=tremulous.exe
exePath=%ProgramFiles%\Tremulous\tremulous.exe
masterServer=master.tremulous.net:30710
protocolVersion=69
useGslist=false

[baseq3]

[osp]

[cpma]

[InstaUnlagged]
`;

	__gshared Ini settingsIni;
	__gshared Ini gamesIni;

	struct Setting {
		string name;
		string value;
	}
	enum Setting[] defaults = [{"coloredNames", "true"},
	                      {"lastMod", "Smokin' Guns"},
	                      {"maxTimeouts", "3"},
	                      {"minimizeOnGameLaunch", "true"},
	                      {"showFlags", "true"},
	                      {"simultaneousQueries", "10"},
	                      {"startWithLastMod", "true"},
	                      {"windowMaximized", "false"},
	                      {"windowSize", "800x568"},
	                     ];

	enum Setting[] defaultSessionState = [{"filterState", "0"},
	                                 {"playerSortOrder", "0"},
	                                 {"resolution", "0, 0"},
	                                 {"serverSortOrder", "1"},
	                                 {"middleWeights", "16,5"},
	                                 {"rightWeights", "1,1"},
	                                 {"cvarColumnWidths", "90,90"},
	                                 {"playerColumnWidths", "100,40,40"},
	                                 {"serverColumnWidths",
	                                              "27,250,21,32,50,40,90,130"},
	                                 {"windowPosition", "150, 150"},
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

	delete gamesIni;
	gamesIni = new Ini(gamesFileName);

	// remove the nameless section caused by comments
	gamesIni.remove("");

	if (gamesIni.sections.length < 1) {
		// Invalid format, probably the old version.  Just overwrite with
		// defaults and try again.
		writeDefaultGamesFile();
		delete gamesIni;
		gamesIni = new Ini(gamesFileName);
		gamesIni.remove("");
	}

	foreach (sec; gamesIni)
		gameNames ~= sec.name;
}


private void writeDefaultGamesFile()
{
	string text = defaultGamesFile;

	version (Windows)
		text = replace(text, "%ProgramFiles%", getProgramFilesDirectory());

	// Use C IO to get line ending translation.
	FILE* f = fopen((gamesFileName ~ '\0').ptr, "w");
	fwrite(text.ptr, 1, text.length, f);
	fclose(f);
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
	loadGamesFile();
}


/**
 * Save program settings and session state.
 */
void saveSettings()
{
	if (settingsIni.modified) {
		settingsIni.save();
	}
}


/**
 * Returns the setting's value, or a default if not set.
 *
 * Will assert in debug mode if a non-existent key is given.
 */
string getSetting(in char[] key)
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
void setSetting(string key, string value)
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
 *
 * Will assert in debug mode if a non-existent key is given.
 */
string getSessionState(in char[] key)
{
	IniSection sec = settingsIni.section("Session");
	assert(sec !is null);
	assert(sec[key], key ~ " not found.\n\n"
	                  "All settings need to have a default.");
	return sec[key];
}


/**
 * Set a session state setting.
 *
 * Will assert in debug mode if a non-existent key is given.
 */
void setSessionState(in char[] key, string value)
{
	assert(settingsIni && settingsIni.sections.length > 0);
	IniSection sec = settingsIni.section("Session");

	assert(sec[key]);
	sec[key] = value;
}


private string autodetectQuake3Path()
{
	version (Windows) {
		string q3path = getRegistryStringValue("HKEY_LOCAL_MACHINE\\"
		                      "SOFTWARE\\Id\\Quake III Arena\\INSTALLEXEPATH");
		if (!q3path) {
			log("Quake 3's installation path was not found in the registry, "
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

/**
 * Get the default program files directory, or an educated guess if not
 * found.
 *
 * Sample return: "C:\Program Files".
 */
version (Windows) private string getProgramFilesDirectory()
{
	string path = getSpecialPath(CSIDL_PROGRAM_FILES);
	assert(path.length);
	return path.length ? path : "C:\\Program Files";
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
	BYTE buf[255] = void;
	LPBYTE lpData = buf.ptr;
	DWORD dwSize = buf.length;
	LONG status;
	char[] retval;

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
		status = RegQueryValueExA(hKey, cast(char*)toStringz(name), NULL,
		                                             &dwType, lpData, &dwSize);

		if (status == ERROR_MORE_DATA) {
			lpData = (new BYTE[dwSize]).ptr;
			status = RegQueryValueExA(hKey, cast(char*)toStringz(name), NULL,
			                                         &dwType, lpData, &dwSize);
		}

		if (status == ERROR_SUCCESS) {
			retval.length = dwSize * 2;
			retval = CodePage.from(to!string(cast(char*)lpData), retval);
		}

		if (dwSize > buf.length)
			delete lpData;

		RegCloseKey(hKey);
	}

	return (status == ERROR_SUCCESS) ? cast(string)retval : null;
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
