/** Launch the game. */

module launch;

import std.file;
import std.path;
version (Windows) {
	import std.utf : toUTF16z;
	import std.windows.syserror;
	import core.sys.windows.windows;
}

import common;
import dialogs;
import gameconfig;
import mainwindow;
import messageboxes;
import serverdata;
import settings;


/**
 * Launch the game, connecting to a server.
 *
 * If needed, shows a dialog asking for a password to enter the server.
 *
 * Will ask for the file to run if it's missing from the settings, or not
 * found.
 */
void joinServer(in char[] gameName, ServerData sd)
{
	GameConfig game = getGameConfig(gameName.idup);

	if (!checkPath(game))
		return;

	string address = sd.server[ServerColumn.ADDRESS];
	string pathString = game.exePath;
	string[] cvar = sd.cvars.getCvar("game");
	string argv;
	bool ok = true;

	if (cvar && cvar[1].length > 0)
		argv = "+set fs_game " ~ cvar[1];

	argv ~= " +connect " ~ address;

	cvar = sd.cvars.getCvar("g_needpass");
	if (cvar && cvar[1] == "1" && getPassword(address).length == 0) {
		string message = "Join \"" ~ sd.server[ServerColumn.NAME] ~ "\"\n\n" ~
		                          "You need a password to join this server.\n";
		scope dialog = new ServerPasswordDialog(mainShell, "Join Server",
		                                         message, address, true, true);

		if (!dialog.open() || dialog.password.length == 0)
			ok = false;
	}

	if (ok) {
		string pw = getPassword(address);
		if (pw.length > 0)
			argv ~= " +set password " ~ pw;

		log("Launching game: " ~ pathString ~ " " ~ argv);
		launch(pathString, argv);
	}
}


/**
 * Launch the game without connecting to a server.
 *
 * Will ask for the file to run if it's missing from the settings, or not
 * found.
 */
void launchGame(in char[] gameName)
{
	GameConfig game = getGameConfig(gameName.idup);

	if (!checkPath(game))
		return;

	string argv = game.mod.length ? "+set fs_game " ~ game.mod : null;
	log("Launching without connecting: " ~ game.exePath ~ " " ~ argv);
	launch(game.exePath, argv);
}


private bool checkPath(GameConfig game)
{
	string pathString = game.exePath;

	if (!pathString || !exists(pathString)) {
		askForGamePath(game.name);
		pathString = game.exePath;
		if (!pathString || !exists(pathString))
			return false;
	}
	return true;
}


private void launch(string pathString, string argv=null)
{
	version (Windows) {
		int r = cast(int)ShellExecuteW(null, "open", toUTF16z(pathString),
					toUTF16z(argv), toUTF16z(dirName(pathString)), SW_SHOW);
		if (r <= 32) {
			auto code = GetLastError();
			log("Launch error %s: %s", code, sysErrorString(code));
			error("Unable to execute \"%s\".", pathString);
		}
		else if (getSetting("minimizeOnGameLaunch") == "true") {
			mainWindow.minimized = true;
		}
	}
	else {
		error("Launching a game is not implemented on this platform.");
	}
}
