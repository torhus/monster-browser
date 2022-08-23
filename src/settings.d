/** Load and store settings, stored passwords, etc. */

module settings;

import tango.core.Exception;
import tango.io.device.File;
import Path = tango.io.Path;
import tango.text.Ascii;
import tango.text.Util;
import Integer = tango.text.convert.Integer;
import tango.stdc.stdio;

import common;
import ini;
import messageboxes;

version (Windows) {
	import tango.stdc.stringz;
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
	char[] name() /// Section name in the game config file.
	{
		return name_;
	}

	char[] mod()  /// Quake 3 gamename, like "baseq3".  Defaults to name.
	{
		return section.getValue("mod", name);
	}

	char[] masterServer()  /// Like "master3.idsoftware.com".
	{
		return section.getValue(
		                       "masterServer", "master.quake3arena.com:27950");
	}

	char[] protocolVersion()  /// Defaults to 68.
	{
		return section.getValue("protocolVersion", "68");
	}

	char[][] gameTypes() ///
	{
		char[] s = section.getValue("gameTypes");

		if (s is null)
			return null;

		char[][] r = split(trim(s), " ");

		return r[0].length > 0 ? r : r[0..0];
	}

	char[] extraServersFile() /// Like "baseq3.extra".
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
	char[] exePath()
	{
		char[] path = null;
		char[] regKey = section["regKey"];
		char[] exeName = section["exeName"];
		bool badRegKey = false;

		version (Windows) if (regKey && exeName) {
			try {
				if (char[] dir = getRegistryStringValue(regKey))
					path = Path.join(Path.standard(dir), exeName);
				else
					log("regKey not found: " ~ regKey);
			}
			catch (IllegalArgumentException e) {
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
	bool useEtColors()
	{
		char[] r = section["etColors"];
		return r ? (r == "true") : false;
	}

	/// Value to use for Qstat's -cfg parameter.
	char[] qstatConfigFile()
	{
		return section.getValue("qstatConfigFile", "qstat_mb.cfg");
	}

	/// Qstat master server type.
	char[] qstatMasterServerType()
	{
		return section.getValue("qstatMasterServerType", "quake3arenam");
	}

	private char[] name_;
	private IniSection section;
}


char[][] gameNames;  /// The names of all games loaded from the config file.
char[] gamesFileName;  /// Name of the file containing options for each game.
char[] backupGamesFileName;  /// ditto

private {
	char[] settingsFileName;

	const char[] defaultGamesFile =
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
; qstatMasterServerType - Defaults to quake3arenam.
; qstatConfigFile - For setting Qstat's -cfg parameter. Defaults to
;                   qstat_mb.cfg.
;
; Lines beginning with a ";" are comments.

[Smokin' Guns]
mod=smokinguns
regKey=HKEY_LOCAL_MACHINE\SOFTWARE\Smokin' Guns Productions\Smokin' Guns\InstallPath
exeName=smokinguns.exe
exePath=%ProgramFiles%\Smokin' Guns\smokinguns.exe
masterServer=master.smokin-guns.org
etColors=true

[World of Padman]
mod=WorldofPadman
exePath=%ProgramFiles%\Padworld Entertainment\World of Padman 1.6.2\wop.exe
masterServer=master.worldofpadman.com:27955
protocolVersion=71
qstatMasterServerType=worldofpadmanm
qstatConfigFile=qstat_mb.cfg

[Urban Terror 4.3]
mod=q3ut4
exePath=%ProgramFiles%\UrbanTerror43\Quake3-UrT.exe
masterServer=master.urbanterror.info:27900
gameTypes=FFA LMS 2 TDM TS FTL C&H CTF Bomb Jump FT Gun

[Tremulous]
mod=
regKey=HKEY_LOCAL_MACHINE\SOFTWARE\Tremulous\InstallDir
exeName=tremulous.exe
exePath=%ProgramFiles%\Tremulous\tremulous.exe
masterServer=master.tremulous.net:30710
protocolVersion=69

[baseq3]

[osp]

[cpma]

[InstaUnlagged]

[Reaction]
exePath=%ProgramFiles%\Reaction\Reaction.x86.exe
masterServer=master.rq3.com:27950
protocolVersion=71
qstatMasterServerType=reactionm
qstatConfigFile=qstat_mb.cfg
`;

	Ini settingsIni;
	Ini gamesIni;

	struct Setting {
		char[] name;
		char[] value;
	}
	Setting[] defaults = [{"coloredNames", "true"},
	                      {"lastMod", "Smokin' Guns"},
	                      {"maxTimeouts", "3"},
	                      {"minimizeOnGameLaunch", "true"},
	                      {"showFlags", "true"},
	                      {"simultaneousQueries", "10"},
	                      {"startWithLastMod", "true"},
	                      {"startupAction", "1"},
	                      {"windowMaximized", "false"},
	                      {"windowSize", "800x568"},
	                     ];

	Setting[] defaultSessionState = [{"programVersion", "0.0"},
	                                 {"filterState", "0"},
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
GameConfig getGameConfig(in char[] name)
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
GameConfig createGameConfig(in char[] name)
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

	if (!Path.exists(gamesFileName))
		writeDefaultGamesFile();
	else if (!gamesIni && getSessionState("programVersion") < "0.8a")
		updateGameConfiguration();

	// load the file now that we know it's there
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

	gameNames = null;
	foreach (sec; gamesIni) {
		if (sec.name.length > 0)
			gameNames ~= sec.name;
	}
}


private void writeDefaultGamesFile()
{
	char[] text = defaultGamesFile;

	version (Windows) {
		text = substitute(text, "%ProgramFiles%", getProgramFilesDirectory());
		text = substitute(text, "\n", "\r\n");
	}

	try {
		File.set(gamesFileName, text);
	}
	catch (IOException e) {
		error("Creating \"{}\" failed.  Monster Browser will not function "
		      "properly without this file.\n\nError: \"{}\"",
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
		char[] path;
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


/// Removes the password stored for a server.
void removePassword(char[] ip)
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
char[] getRconPassword(in char[] ip)
{
	IniSection sec = settingsIni.section("RconPasswords");
	if (sec is null)
		return "";
	return sec.getValue(ip, "");
}


/// Stores rcon passwords for later retrieval by getRconPassword().
void setRconPassword(char[] ip, char[] password)
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
char[] getSessionState(in char[] key)
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
void setSessionState(in char[] key, in char[] value)
{
	assert(settingsIni && settingsIni.sections.length > 0);
	IniSection sec = settingsIni.section("Session");

	assert(sec[key]);
	sec[key] = value;
}


/**
 *
 */
private void updateGameConfiguration()
{
	assert(Path.exists(gamesFileName));
	try {
		Path.rename(gamesFileName, backupGamesFileName);
		info("The game configuration was updated.\n\nYour old configuration "
		     "was backed up to \"{}\".", backupGamesFileName);
		writeDefaultGamesFile();
	}
	catch (IOException e) {
		warning("Renaming \"{}\" to \"{}\" failed.  The game configuration "
		        "was not updated.\n\nError: \"{}\"",
		        gamesFileName, backupGamesFileName, e);
	}
}


private char[] autodetectQuake3Path()
{
	version (Windows) {
		char[] q3path = getRegistryStringValue("HKEY_LOCAL_MACHINE\\"
		                      "SOFTWARE\\Id\\Quake III Arena\\INSTALLEXEPATH");
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
 * Get the default program files directory, or an educated guess if not
 * found.
 *
 * Sample return: "C:\Program Files".
 */
version (Windows) private char[] getProgramFilesDirectory()
{
	char[] path = getSpecialPath(CSIDL_PROGRAM_FILES);
	assert(path.length);
	return path.length ? path : "C:\\Program Files".dup;
}


/**
 * Returns the value of a registry key, or null if there was an error.

 * Throws: IllegalArgumentException if the argument is not a valid key.
 *
 * BUGS: Doesn't convert arguments to ANSI.
 */
version (Windows) private char[] getRegistryStringValue(in char[] key)
{
	HKEY hKey;
	DWORD dwType = REG_SZ;
	BYTE buf[255] = void;
	LPBYTE lpData = buf.ptr;
	DWORD dwSize = buf.length;
	LONG status;
	char[] retval;

	char[][] parts = split(key, "\\");
	if (parts.length < 3)
		throw new IllegalArgumentException("Invalid registry key: " ~ key);

	HKEY keyConst = hkeyFromString(parts[0]);
	char[] subKey = join(parts[1..$-1], "\\");
	char[] name = parts[$-1];

	status = RegOpenKeyExA(keyConst, toStringz(subKey), 0, KEY_ALL_ACCESS,
	                                                                    &hKey);

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

	return (status == ERROR_SUCCESS) ? retval : null;
}


/// Throws: IllegalArgumentException.
version (Windows) private HKEY hkeyFromString(in char[] s)
{
	if (icompare(s, "HKEY_CLASSES_ROOT") == 0)
		return HKEY_CLASSES_ROOT;
	if (icompare(s, "HKEY_CURRENT_USER") == 0)
		return HKEY_CURRENT_USER;
	if (icompare(s, "HKEY_LOCAL_MACHINE") == 0)
		return HKEY_LOCAL_MACHINE;

	throw new IllegalArgumentException("Invalid HKEY: " ~ s);
}
