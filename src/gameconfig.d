/**
 * Game/mod configuration handling.
 */

module gameconfig;

import std.exception : ErrnoException;
import std.file;
import std.stdio;
import std.string;

import common;
import ini;
import messageboxes;
import settings;
version (Windows) import mswindows.util;


/// Configuration for a game.
struct GameConfig
{
    string name() const => name_; /// Section name in the game config file.

    /// Quake 3 gamename, like "baseq3".  Defaults to name.
    string mod() const => section.getValue("mod", name);

    /// Like "master3.idsoftware.com".
    string masterServer() const =>
              section.getValue("masterServer", "master.quake3arena.com:27950");

    /// Defaults to 68.
    string protocolVersion() const =>
                                     section.getValue("protocolVersion", "68");

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
    string qstatConfigFile() const =>
                                     section.getValue("qstatConfigFile", null);

    /// Qstat master server type.
    string qstatMasterServerType() const =>
                              section.getValue("qstatMasterServerType", "q3m");

    private string name_;
    private IniSection section;
}


/// The names of all games loaded from the config file.
__gshared string[] gameNames;

/// Name of the file containing options for each game.
shared string gamesFilePath;
shared string backupGamesFilePath;  /// ditto

private
{
    enum defaultGamesFileName = "mods-default.ini";
    enum defaultGamesFileContents = import(defaultGamesFileName);

    __gshared Ini gamesIni;
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


///
void initGameConfig()
{
    gamesFilePath = dataDir ~ "mods.ini";
    backupGamesFilePath = gamesFilePath ~ ".autobackup";
    loadGamesFile();

    if (getSessionState("programVersion") != FINAL_VERSION)
        createDefaultGamesFile();
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


///
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
    string path = dataDir ~ defaultGamesFileName;

    try {
        File(path, "w").write(defaultGamesFileContents);
        log("Created %s.", path);
    }
    catch (ErrnoException e) {
        error("Creating \"%s\" failed.\n\n\"%s\"", path, e);
    }
}
