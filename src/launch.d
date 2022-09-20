/** Launch the game. */

module launch;

import std.path;
import std.string;
version (Windows) {
	import std.windows.charset;
	import std.windows.syserror;
	import core.sys.windows.windows;
}

import org.eclipse.swt.SWT;

import colorednames;
import common;
import dialogs;
import mainwindow;
import messageboxes;
import serverdata;
import settings;


/**
 * Launch the game, connecting to a server.
 *
 * If needed, shows a dialog asking for a password to enter the server.
 *
 * Displays an error message if the game executable was not found.
 */
void joinServer(in char[] gameName, ServerData sd)
{
	string argv;
	string address = sd.server[ServerColumn.ADDRESS];
	GameConfig game = getGameConfig(gameName.idup);
	string pathString = game.exePath;
	bool launch = true;
	int i;

	if (!pathString) {
		error("No path found for " ~ gameName ~
		                                      ", please check your settings.");
		return;
	}

	i = findString(sd.cvars, "game", 0);
	if (i != -1) {
		string s = sd.cvars[i][1];
		if (s.length > 0)
			argv = "+set fs_game " ~ s;
	}

	argv ~= "+connect " ~ address;

	i = findString(sd.cvars, "g_needpass", 0);
	if (i != -1 && sd.cvars[i][1] == "1" && getPassword(address).length == 0) {
		string message = "Join \"" ~ sd.server[ServerColumn.NAME] ~ "\"\n\n" ~
		                          "You need a password to join this server.\n";
		scope dialog = new ServerPasswordDialog(mainWindow.handle,
		                          "Join Server", message, address, true, true);

		if (!dialog.open() || dialog.password.length == 0)
			launch = false;
	}

	if (launch) {
		string pw = getPassword(address);
		if (pw.length > 0)
			argv ~= " +set password " ~ pw;

		log("Launching game: " ~ pathString ~ " " ~ argv);

		version (Windows) {
			const char* ansiPath = toMBSz(pathString);
			const char* ansiDir = toMBSz(dirName(pathString));

			int r = cast(int)ShellExecuteA(null, "open", ansiPath,
			                                toStringz(argv), ansiDir, SW_SHOW);
			if (r <= 32) {
				auto code = GetLastError();
				error("Unable to execute \"%s\".\n\nError %s: %s",
				                       pathString, code, sysErrorString(code));
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
