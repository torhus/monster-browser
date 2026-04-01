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
	string argv;
	string address = sd.server[ServerColumn.ADDRESS];
	GameConfig game = getGameConfig(gameName.idup);
	string pathString = game.exePath;
	bool launch = true;
	string[] cvar;

	if (!pathString || !exists(pathString)) {
		askForGamePath(game.name);
		pathString = game.exePath;
		if (!pathString || !exists(pathString))
			return;
	}

	cvar = sd.cvars.getCvar("game");
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
			launch = false;
	}

	if (launch) {
		string pw = getPassword(address);
		if (pw.length > 0)
			argv ~= " +set password " ~ pw;

		log("Launching game: " ~ pathString ~ " " ~ argv);

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
}
