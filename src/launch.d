/** Launch the game. */

module launch;

import tango.io.FilePath;
import tango.stdc.stringz;
import tango.sys.Common;
version (Windows) {
	import tango.sys.win32.CodePage;
	import tango.sys.win32.UserGdi;
}

import dwt.DWT;

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
	char[] argv;
	char[] address = sd.server[ServerColumn.ADDRESS];
	GameConfig game = getGameConfig(gameName);
	char[] pathString = game.exePath;
	bool launch = true;
	int i;

	if (!pathString) {
		error("No path found for " ~ gameName ~
		                                      ", please check your settings.");
		return;
	}

	i = findString(sd.cvars, "game", 0);
	if (i != -1) {
		char[] s = sd.cvars[i][1];
		if (s.length > 0)
			argv = "+set fs_game " ~ s;
	}

	argv ~= " +connect " ~ address;

	i = findString(sd.cvars, "g_needpass", 0);
	if (i != -1 && sd.cvars[i][1] == "1" && getPassword(address).length == 0) {
		char[] message = "Join \"" ~ sd.server[ServerColumn.NAME] ~ "\"\n\n" ~
		                          "You need a password to join this server.\n";
		scope dialog = new ServerPasswordDialog(mainWindow.handle,
		                          "Join Server", message, address, true, true);

		if (!dialog.open() || dialog.password.length == 0)
			launch = false;
	}

	if (launch) {
		char[] pw = getPassword(address);
		if (pw.length > 0)
			argv ~= " +set password " ~ pw;

		log("Launching game: " ~ pathString ~ " " ~ argv);

		version (Windows) {
			FilePath path = FilePath(pathString);
			char buf[MAX_PATH];
			char[] ansiDir = CodePage.into(path.path, buf).dup;
			char[] ansiPath = ansiDir ~ CodePage.into(path.file, buf);

			int r = cast(int)ShellExecuteA(null, "open", toStringz(ansiPath),
			                     toStringz(argv), toStringz(ansiDir), SW_SHOW);
			if (r <= 32) {
				error("Unable to execute \"{}\".\n\nError {}: {}",
				                  path, SysError.lastCode, SysError.lastMsg());
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
