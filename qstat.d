module qstat;

/* What's specific for qstat */

private {
	import std.file;
	import std.string;
	import std.stream;
	import std.conv;

	import common;
	import parselist;
	import serverlist;
	import servertable;
	import main;
	import settings;
}

const char[] FIELDSEP = "\x1e"; // \x1e = ascii record separator


void parseOutput(void delegate(Object) callback, char[] delegate() readLine,
                 bool delegate() eof=null, char[] outputFileName=null)
{
	char[][] gtypes;
	BufferedFile outfile;
	debug scope timer = new Timer;
	int count = 0;
	scope countWrapper = new IntWrapper(-1);

	assert(callback);

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

	if (settings.modName in gameTypes) {
		gtypes = gameTypes[settings.modName];
	}
	else {
		gtypes = defaultGameTypes;
	}

	volatile abort = false;

each_server:
	while (true) {
		volatile if (abort || (eof && eof()))
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
			display.syncExec(countWrapper, callback);

			if (fields.length >= 9) {
				if (settings.modName != "baseq3" &&
				             MOD_ONLY &&
				             icmp(fields[8], settings.modName) != 0) {
					continue each_server;
				}

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
						//case "game":
						case "gamename":
							if (MOD_ONLY &&
							          icmp(cvar[1], settings.modName) != 0) {
								continue each_server;
							}
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

				serverList.add(&sd);
			}
			else /*if (!MOD_ONLY)*/ { // server didn't respond
				/*sd.server.length = servertable.serverHeaders.length;
				sd.server[ServerColumn.ADDRESS] = fields[1]; // ip
				serverList.add(sd);*/
			}
			if (outfile) {
				outfile.writeLine("");
			}
		}
	}
}


void filterServerFile()
{
	scope BufferedFile infile = new BufferedFile(parselist.SERVERFILE);
	scope BufferedFile outfile = new BufferedFile(parselist.REFRESHFILE, FileMode.OutNew);

	while (!infile.eof()) {
		char[] line = infile.readLine();

		if (line && line.length >= 3 && line[0..3] == "Q3S") {
			char[][] fields = split(line, FIELDSEP);
			ServerData sd;
	
			assert(fields.length == 9 || fields.length == 3);
	
			if (fields.length >= 9) {
				if (settings.modName != "baseq3" &&
				             MOD_ONLY &&
				             icmp(fields[8], settings.modName) != 0) {
					continue;
				}
				outfile.writeLine(fields[1]);
			}
		}	
	}
	
	infile.close();
	outfile.close();
}


/**
 * Save the server list so that qstat can refresh servers
 *
 * Throws: OpenException, maybe WriteException in rare cases
 */
void saveRefreshList()
{
	if (exists(SERVERFILE)) {
		filterServerFile();
	}
	
	/*scope BufferedFile f = new BufferedFile(parselist.REFRESHFILE, FileMode.OutNew);
	scope(exit) f.close();

	foreach (ServerData sd; serverList) {
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
 * Throws: OpenException, maybe WriteException in rare cases
 */
int countServersInRefreshList()
{
	int count = 0;
	scope BufferedFile f = new BufferedFile(parselist.REFRESHFILE);
	scope(exit) f.close();

	foreach (char[] line; f) {
		count++;
	}

	return count;
}
