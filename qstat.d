module qstat;

/* What's specific for qstat */

private {
	import tango.core.Exception;
	import tango.io.FileConduit;
	import tango.io.FilePath;
	import tango.io.stream.BufferStream;
	import tango.io.stream.TextFileStream;
	import tango.text.Ascii;
	import tango.text.Util;
	import Float = tango.text.convert.Float;
	import tango.text.convert.Integer;

	version (Tango)
		import dwt.dwthelper.Runnable;

	import colorednames;
	import common;
	import runtools;
	import serverlist;
	import servertable;
	import main;
	import settings;
}

const char[] FIELDSEP = "\x1e"; // \x1e = ascii record separator



/**
 * Parse Qstat's output.
 *
 * Throws: when outputFileName is given: IOException.
 */
bool parseOutput(void delegate(Object) countDg, char[] delegate() readLine,
                 bool delegate() eof=null, char[] outputFileName=null)
{
	char[][] gtypes;
	BufferOutput outfile;
	debug scope timer = new Timer;
	int count = 0;
	scope countWrapper = new IntWrapper(-1);

	assert(countDg);

	if (outputFileName) {
		try {
			outfile = new BufferOutput(new FileConduit(
			                         outputFileName, FileConduit.WriteCreate));
		}
		catch (IOException e) {
			error("Unable to open \'" ~ outputFileName ~ "\', the\n"
			      "server list will not be saved to disk.");
			outfile = null;
		}
	}

	scope (exit) {
		if (outfile) {
			outfile.flush.close;
			delete outfile;
		}
		debug log("	qstat.parseOutput took " ~
		                  Float.toString(timer.secs) ~ " seconds.");
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
		if (outfile) {
			outfile.write(line);
			outfile.write(newline);
		}

		if (line && line.length >= 3 && line[0..3] == "Q3S") {
			char[][] fields = split(line, FIELDSEP);
			ServerData sd;

			// FIXME: workaround for tango split() bug, issue #942
			if (fields.length == 8)
				fields ~=  "";

			assert(fields.length == 9 || fields.length == 3);
			count++;
			countWrapper.value = count;
			version (Tango) {
				display.syncExec(new class Runnable {
					void run() { countDg(countWrapper); }
				});
			}
			else {
				display.syncExec(countWrapper, countDg);
			}

			if (fields.length >= 9) {
				bool keep_server = false;

				if (!MOD_ONLY)
					keep_server = true;

				if (icompare(fields[8], activeMod.name) == 0)
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

				sd.rawName = fields[2];
				sd.server[ServerColumn.PASSWORDED] = "";
				sd.server[ServerColumn.PING] = fields[6];
				sd.server[ServerColumn.PLAYERS] = "";
				sd.server[ServerColumn.GAMETYPE] = "";
				sd.server[ServerColumn.MAP] = fields[3];
				sd.server[ServerColumn.ADDRESS] = fields[1];

				// parse cvars
				line = readLine();
				if (outfile) {
					outfile.write(line);
					outfile.write(newline);
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
								sd.server[ServerColumn.GAMETYPE] = toString(gt);
							}
							break;
						case "game":  // not sure if this is right, risk getting too many servers
							if (!keep_server &&
							          icompare(cvar[1], activeMod.name) == 0) {
								keep_server = true;
							}
							break;
						case "gamename":  // has to come after case "game"
							if (!keep_server &&
							          icompare(cvar[1], activeMod.name) == 0) {
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
						outfile.write(line);
						outfile.write(newline);
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
				sd.server[ServerColumn.PLAYERS] = toString(humans) ~
				                  "+" ~ toString(bots) ~
				                  "/" ~ fields[4];

				sd.server[ServerColumn.NAME] = stripColorCodes(sd.rawName);

				getActiveServerList.add(&sd);
			}
			else /*if (!MOD_ONLY)*/ { // server didn't respond
				/*sd.server.length = servertable.serverHeaders.length;
				sd.server[ServerColumn.ADDRESS] = fields[1]; // ip
				getActiveServerList.add(sd);*/
			}
			if (outfile) {
				outfile.write(newline);
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
 * Throws: IOException.
 */
void filterServerFile(char[] readFrom, char writeTo[])
{
	scope infile = new TextFileInput(readFrom);
	scope outfile = new BufferOutput(
	                        new FileConduit(writeTo, FileConduit.WriteCreate));

	while (infile.next()) {
		char[] line = infile.get();

		if (line.length >= 3 && line[0..3] == "Q3S") {
			char[][] fields = split(line, FIELDSEP);

			// FIXME: workaround for tango split() bug, issue #942
			if (fields.length == 8)
				fields ~=  "";

			assert(fields.length == 9 || fields.length == 3);

			if (fields.length < 9)
				continue;  // server probably timed out

			if (!MOD_ONLY) {
				outfile.write(fields[1]);
				outfile.write(newline);
			}
			else if (/*activeMod.name != "baseq3" &&*/
			                        icompare(fields[8], activeMod.name) == 0) {
				outfile.write(fields[1]);
				outfile.write(newline);
			}
			else { // need to parse cvars to find out which mod this server runs
				line = infile.next();
				char[][] temp = split(line, FIELDSEP);
				foreach (char[] s; temp) {
					char[][] cvar = split(s, "=");
					// Not sure if it's right to check 'game' or not.  Might
					// end up including too many servers.
					if (cvar[0] == "game" &&
					                  icompare(cvar[1], activeMod.name) == 0) {
						outfile.write(fields[1]);
						outfile.write(newline);
						break;
					}
					if (cvar[0] == "gamename" &&
					                  icompare(cvar[1], activeMod.name) == 0) {
						outfile.write(fields[1]);
						outfile.write(newline);
						break;
					}
				}
			}
		}
	}

	infile.close();
	outfile.flush().close();
}


/**
 * Save the server list so that qstat can refresh servers
 *
 * Throws: IOException.
 */
void saveRefreshList()
{
	if (FilePath(activeMod.serverFile).exists /* && exists(REFRESHFILE)*/) {
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
 * Throws: IOException.
 */
int countServersInRefreshList()
{
	if (!FilePath(runtools.REFRESHFILE).exists)
		return 0;

	scope f = new TextFileInput(runtools.REFRESHFILE);
	scope(exit) f.close();

	int count = 0;
	foreach (char[] line; f) {
		count++;
	}

	return count;
}
