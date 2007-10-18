module qstat;

/* What's specific for qstat */

private {
	import std.file;
	import std.string;
	import std.stream;
	import std.conv;

	import common;
	import runtools;
	import serverlist;	
	import main;
	import settings;
	
	import gui.dialogs;
	import gui.mainwindow;  // FIXME: remove
	import gui.servertable;	
}

const char[] FIELDSEP = "\x1e"; // \x1e = ascii record separator



/**
 * Parse Qstat's output.
 *
 * Throws: when outputFileName is given: OpenException and WriteException.
 */
bool parseOutput(void delegate(Object) countDg, char[] delegate() readLine,
                 bool delegate() eof=null, char[] outputFileName=null)
{
	char[][] gtypes;
	BufferedFile outfile;
	debug scope timer = new Timer;
	int count = 0;
	scope countWrapper = new IntWrapper(-1);

	assert(countDg);

	if (outputFileName) {
		try {
			outfile = new BufferedFile(outputFileName, FileMode.OutNew);
		}
		catch (OpenException e) {
			error("Unable to open \'" ~ outputFileName~ "\', the\n"
			      "server list will not be saved to disk.");
			outfile = null;
		}
	}

	scope (exit) {
		if (outfile) {
			outfile.close();
			delete outfile;
		}
		debug log("	qstat.parseOutput took " ~
		                  std.string.toString(timer.secs) ~ " seconds.");
	}

	if (activeMod.name in gameTypes) {
		gtypes = gameTypes[activeMod.name];
	}
	else {
		gtypes = defaultGameTypes;
	}

	volatile abortParsing = false;

each_server:
	while (true) {
		volatile if (abortParsing || (eof && eof()))
			break;

		char[] line = readLine();
		if (outfile)
			outfile.writeLine(line);

		if (line && line.length >= 3 && line[0..3] == "Q3S") {
			char[][] fields = split(line, FIELDSEP);
			ServerData sd;

			assert(fields.length == 9 || fields.length == 3);
			count++;
			countWrapper.value = count;
			syncExec(countWrapper, countDg);

			if (fields.length >= 9) {
				bool keep_server = false;

				if (!MOD_ONLY)
					keep_server = true;

				if (icmp(fields[8], activeMod.name) == 0)
					keep_server = true;

				/*if (activeMod.name != "baseq3" &&
				             MOD_ONLY &&
				             icmp(fields[8], activeMod.name) != 0) {
					debug printf("skipped %.*s\n", line);
					debug line = readLine();
					debug printf("        %.*s\n", line);
					continue each_server;
				}*/

				sd.server.length = ServerColumn.max + 1;

				sd.server[ServerColumn.PASSWORDED] = "";
				sd.server[ServerColumn.NAME] = fields[2];
				sd.server[ServerColumn.PING] = fields[6];
				sd.server[ServerColumn.PLAYERS] = "";
				sd.server[ServerColumn.GAMETYPE] = "";
				sd.server[ServerColumn.MAP] = fields[3];
				sd.server[ServerColumn.ADDRESS] = fields[1];

				// parse cvars
				line = readLine();
				if (outfile) {
					outfile.writeLine(line);
				}
				char[][] temp = split(line, FIELDSEP);
				foreach (char[] s; temp) {
					char[][] cvar = split(s, "=");
					switch (cvar[0]) {
						case "gametype":
							int gt = toInt(cvar[1]);
							if (gt < gtypes.length) {
								sd.server[ServerColumn.GAMETYPE] = gtypes[gt];
							}
							else {
								sd.server[ServerColumn.GAMETYPE] =
								                  std.string.toString(gt);
							}
							break;
						case "game":  // not sure if this is right, risk getting too many servers
							if (!keep_server && icmp(cvar[1], activeMod.name) == 0) {
								keep_server = true;
							}
							break;
						case "gamename":  // has to come after case "game"
							if (!keep_server && icmp(cvar[1], activeMod.name) == 0) {
								keep_server = true;
							}

							// Since qstat's 'game' pseudo cvar always is listed before
							// 'gamename', it's safe to abort parsing here in the case
							// that keep_server still is false.
							if (!keep_server)
								continue each_server;
							break;
						case "g_needpass":
							if (cvar[1] == "1")
								sd.server[ServerColumn.PASSWORDED] = "X";
							break;
						default:
							break;
					}
					sd.cvars ~= cvar;
				}

				if (!keep_server)
					continue each_server;

				sortStringArray(sd.cvars);

				// parse players
				int humans = 0;
				while ((line = readLine()) !is null && line.length) {
					if (outfile) {
						outfile.writeLine(line);
					}
					char[][] s = split(line, FIELDSEP);
					sd.players ~= s;
					if (s[PlayerColumn.PING] != "0") {
						humans++;
					}
				}

				// 'Players' column contents
				int bots = toInt(fields[5]) - humans;
				if (bots < 0) {
					bots = 0;
				}
				sd.server[ServerColumn.PLAYERS] = std.string.toString(humans) ~
				                  "+" ~ (std.string.toString(bots)) ~
				                  "/" ~ fields[4];

				getActiveServerList.add(&sd);
			}
			else /*if (!MOD_ONLY)*/ { // server didn't respond
				/*sd.server.length = servertable.serverHeaders.length;
				sd.server[ServerColumn.ADDRESS] = fields[1]; // ip
				getActiveServerList.add(sd);*/
			}
			if (outfile) {
				outfile.writeLine("");
			}
		}
	}

	return !abortParsing;
}


/**
 * Parses a server list file and outputs the IP and port number for all servers
 * for the currently active mod to another file.
 *
 * Params:
 *     readFrom = File to read from.  The format is taken to be
 *                qstat's raw output.
 *     writeTo  = File to write to. The format is one IP:PORT combo per line.
 *
 * Throws: OpenException, WriteException.
 */
void filterServerFile(char[] readFrom, char writeTo[])
{
	scope BufferedFile infile = new BufferedFile(readFrom);
	scope BufferedFile outfile = new BufferedFile(writeTo, FileMode.OutNew);

	while (!infile.eof()) {
		char[] line = infile.readLine();

		if (line && line.length >= 3 && line[0..3] == "Q3S") {
			char[][] fields = split(line, FIELDSEP);
			ServerData sd;

			assert(fields.length == 9 || fields.length == 3);

			if (fields.length < 9)
				continue;  // server probably timed out

			if (!MOD_ONLY) {
				outfile.writeLine(fields[1]);
			}
			else if (/*activeMod.name != "baseq3" &&*/
			                                   icmp(fields[8], activeMod.name) == 0) {
				outfile.writeLine(fields[1]);
			}
			else { // need to parse cvars to find out which mod this server runs
				line = infile.readLine();
				char[][] temp = split(line, FIELDSEP);
				foreach (char[] s; temp) {
					char[][] cvar = split(s, "=");
					// Not sure if it's right to check 'game' or not.  Might end up
					// including too many servers.
					if (cvar[0] == "game" && icmp(cvar[1], activeMod.name) == 0) {
						outfile.writeLine(fields[1]);
						break;
					}
					if (cvar[0] == "gamename" && icmp(cvar[1], activeMod.name) == 0) {
						outfile.writeLine(fields[1]);
						break;
					}
				}
			}
		}
	}

	infile.close();
	outfile.close();
}


/**
 * Save the server list so that qstat can refresh servers
 *
 * Throws: OpenException, WriteException, FileException.
 */
void saveRefreshList()
{
	if (exists(activeMod.serverFile)/* && exists(REFRESHFILE)*/) {
		filterServerFile(activeMod.serverFile, REFRESHFILE);
	}

	/*foreach (address; getActiveServerList.extraServers) {
		append(REFRESHFILE, address ~ newline);
	}*/

	/*scope BufferedFile f = new BufferedFile(runtools.REFRESHFILE, FileMode.OutNew);
	scope(exit) f.close();

	foreach (ServerData sd; getActiveServerList) {
		f.writeLine(sd.server[ServerColumn.ADDRESS]);
	}*/
}


/**
 * Count how many servers in the file qstat reads when it refreshes the
 * server list.
 *
 * Useful for getting the number of servers before qstat has started
 * to retrieve them.
 *
 * Throws: OpenException.
 */
int countServersInRefreshList()
{
	if (!exists(runtools.REFRESHFILE))
		return 0;

	scope BufferedFile f = new BufferedFile(runtools.REFRESHFILE);
	scope(exit) f.close();

	int count = 0;
	foreach (char[] line; f) {
		count++;
	}

	return count;
}
