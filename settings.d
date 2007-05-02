module settings;

/* Load and store settings, and saved passwords. */

private {
	import std.string;
	import std.file;

	import lib.process;
	import ini;
	import common;
	import main;
}

char[][] mods;
char[] modName;
const char[] modFileName = "mods.ini";

private {
	const char[] settingsFileName = "settings.ini";

	const char[][] defaultMods = ["westernq3", "baseq3", "osp", "cpma",
	                              "InstaUnlagged", "q3ut4", "wop"];

	Ini settingsIni;

	struct Setting {
		char[] name;
		char[] value;
	}
	Setting[] defaults = [{"gamePath",
	                           r"C:\Program Files\Quake III Arena\quake3.exe"},
	                      {"windowSize", "800x568"},
	                      {"windowMaximized", "false"},
	                      {"minimizeOnGameLaunch", "true"},
	                      {"lastMod", "westernq3"},
	                      {"startWithLastMod", "true"},
	                     ];
}


void loadModFile()
{
	if (!exists(modFileName)) {
		write(modFileName, std.string.join(defaultMods, std.string.newline) ~
		                                   std.string.newline);
	}

	mods = splitlines(cast(char[])read(modFileName));
	if (!modName) {
		modName = mods[0];
	}
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

	loadModFile();
}


void saveSettings()
{
	if (!mainWindow.getMaximized() && !mainWindow.getMinimized()) {
		setSetting("windowSize", std.string.format(mainWindow.getSize().x, "x",
		                                              mainWindow.getSize().y));
	}
	setSetting("windowMaximized", mainWindow.getMaximized() ?
	                                                 "true" : "false");

	setSetting("lastMod", modName);

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
		return null;
	return sec.getValue(ip);
}


void setPassword(char[] ip, char[] password)
{
	IniSection sec = settingsIni.addSection("Passwords");
	sec.setValue(ip, password);
}
