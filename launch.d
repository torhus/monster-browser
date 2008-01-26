module launch;

/* Launch the game, etc. */

private {
	import std.string;
	import std.path;
	import std.conv;

	version (Windows)
		import dwt.all;
	else
		import dwt.DWT;
		
	version (Windows)
		import lib.process;
	else
		import tango.sys.Process;

	import main;
	import common;
	import settings;
	import dialogs;
	import serverlist;
}

version (Windows) {
	private PROCESS_INFORMATION *info = null;
}

void JoinServer(ServerData *sd)
{
	char[] argv;
	char[] path = activeMod.exePath;
	char[] dir = getDirName(path);
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
	else if (toInt(sd.cvars[findString(sd.cvars, "sv_privateClients", 0)][1]) > 0) {
		showDialog = true;
		msg = "This server has got private slots, so type your\n"
		      "password if you have one.  Otherwise just click OK.";
	}

	if (showDialog) {
		scope JoinDialog dialog = new JoinDialog(mainWindow, sd.server[ServerColumn.NAME],
		                                   msg);

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
			STARTUPINFOA startup;

			GetStartupInfoA(&startup);
			startup.dwFlags = STARTF_USESTDHANDLES;
			info = new PROCESS_INFORMATION();

			int r = CreateProcessA(null, toStringz(path ~ " " ~ argv),
			                     null, null, true, 0/*DETACHED_PROCESS*/, null,
			                     toStringz(dir),&startup,info);
			if (!r) {
				int e = GetLastError();
				db("CreatProcessA returned " ~ std.string.toString(r));
				db("GetLastError returned " ~ std.string.toString(e));
			}
			else if (getSetting("minimizeOnGameLaunch") == "true") {
				mainWindow.setMinimized(true);
			}
		}
		else {
			// Need a platform specific way of launching the game.
			error("Not implemented on linux");
		}
	}
}
