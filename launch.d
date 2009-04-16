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
	GameConfig game = getGameConfig(gameName);
	char[] pathString = game.exePath;
	FilePath path;
	bool launch = true;
	bool showDialog = false;
	char[] msg;

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
	argv ~= " +connect " ~ sd.server[ServerColumn.ADDRESS];

	if (sd.cvars[findString(sd.cvars, "g_needpass", 0)][1] == "1") {
		showDialog = true;
		msg = "You need a password to join this server.";
	}
	else if (Integer.convert(
	          sd.cvars[findString(sd.cvars, "sv_privateClients", 0)][1]) > 0) {
		showDialog = true;
		msg = "This server has got private slots, so type your\n"
		      "password if you have one.  Otherwise just click OK.";
	}

	if (showDialog) {
		scope JoinDialog dialog = new JoinDialog(mainWindow.handle,
		                                    sd.server[ServerColumn.NAME], msg);

		dialog.password = getPassword(sd.server[ServerColumn.ADDRESS]);

		int res = dialog.open();
		if (res == DWT.OK && dialog.password.length) {
			argv ~= " +set password " ~ dialog.password;
			setPassword(sd.server[ServerColumn.ADDRESS], dialog.password);
		}
		if (res != DWT.OK)
			launch = false;
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
			error("joinServer() not implemented on this platform.");
		}
	}
}
