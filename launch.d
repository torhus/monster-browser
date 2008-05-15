/** Launch the game. */

module launch;

import tango.io.FilePath;
import tango.stdc.stringz;
version (Windows)
	import tango.sys.win32.UserGdi;
import Integer = tango.text.convert.Integer;

import dwt.DWT;

import colorednames;
import common;
import dialogs;
import main;
import serverlist;
import settings;


version (Windows)
	private PROCESS_INFORMATION *info = null;


/**
 * Launch the game, connecting to a server.
 *
 * If needed, shows a dialog asking for a password to enter the server.
 */
void joinServer(ServerData *sd)
{
	char[] argv;
	char[] path = activeMod.exePath;
	char[] dir = FilePath(path).path;
	bool launch = true;
	bool showDialog = false;
	char[] msg;

	if (MOD_ONLY) {
		argv = "+set fs_game " ~ activeMod.name;
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
		scope JoinDialog dialog = new JoinDialog(mainWindow,
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
		version (Posix) {
			// Need a platform specific way of launching the game.
			error("Not implemented on Unix.");
		}
		else {
			STARTUPINFO startup;

			GetStartupInfoA(&startup);
			startup.dwFlags = STARTF_USESTDHANDLES;
			info = new PROCESS_INFORMATION();

			int r = CreateProcessA(null, toStringz(path ~ " " ~ argv),
			                     null, null, true, 0/*DETACHED_PROCESS*/, null,
			                     toStringz(dir),&startup,info);
			if (!r) {
				int e = GetLastError();
				db("CreatProcessA returned " ~ Integer.toString(r));
				db("GetLastError returned " ~ Integer.toString(e));
			}
			else if (getSetting("minimizeOnGameLaunch") == "true") {
				mainWindow.setMinimized(true);
			}
		}
	}
}
