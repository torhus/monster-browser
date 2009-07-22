/** Launch the game. */

module launch;

import tango.io.FilePath;
import tango.stdc.stringz;
version (Windows) {
	import tango.sys.win32.CodePage;
	import tango.sys.win32.UserGdi;
}
import tango.text.Util : replace;
import Integer = tango.text.convert.Integer;

import dwt.DWT;

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
	char[] argv;
	char[] address = sd.server[ServerColumn.ADDRESS];
	GameConfig game = getGameConfig(gameName);
	char[] pathString = game.exePath;
	FilePath path;
	bool launch = true;
	bool showDialog = false;

	if (!pathString) {
		error("No path found for " ~ gameName ~
		                                      ", please check your settings.");
		return;
	}

	path = FilePath(replace(pathString, '\\', '/'));
	if (!path.exists || path.isFolder) {
		error(path.toString ~ " was not found or is not a file,\n"
		                                        "please check your settings.");
		return;
	}

	if (MOD_ONLY) {
		argv = "+set fs_game " ~ game.mod;
	}
	argv ~= " +connect " ~ address;

	int i = findString(sd.cvars, "g_needpass", 0);
	if (i != -1 && sd.cvars[i][1] == "1" && getPassword(address).length == 0) {
		char[] message = "Join \"" ~ sd.server[ServerColumn.NAME] ~ "\"\n\n" ~
		                          "You need a password to join this server.\n";
		scope dialog = new ServerPasswordDialog(mainWindow.handle,
		                          "Join Server", message, address, true, true);

		if (dialog.open()) {
			if (dialog.password.length)
				argv ~= " +set password " ~ dialog.password;
		}
		else {
			launch = false;
		}
	}

	if (launch) {
		version (Windows) {
			PROCESS_INFORMATION info;
			STARTUPINFO startup;

			GetStartupInfoA(&startup);
			startup.dwFlags = STARTF_USESTDHANDLES;

			char buf[MAX_PATH];
			char[] ansiDir = CodePage.into(path.path, buf);
			char[] ansiPath = ansiDir ~ path.file;

			int r = CreateProcessA(null, toStringz(ansiPath ~ " " ~ argv),
			                     null, null, true, 0, null, toStringz(ansiDir),
			                                                  &startup, &info);
			if (!r) {
				int e = GetLastError();
				db("CreatProcessA returned " ~ Integer.toString(r));
				db("GetLastError returned " ~ Integer.toString(e));
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
