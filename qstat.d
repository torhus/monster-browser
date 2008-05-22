/** What's specific for qstat */

module qstat;

import tango.core.Exception;
import tango.io.FileConduit;
import tango.io.stream.BufferStream;
import tango.io.stream.TextFileStream;
import tango.stdc.ctype : isdigit;
import tango.text.Ascii;
import tango.text.Util;
import Float = tango.text.convert.Float;
import tango.text.convert.Integer;
import tango.text.stream.LineIterator;

import dwt.dwthelper.Runnable;
import dwt.widgets.Display;

import colorednames;
import common;
import main;
import runtools;
import serverlist;
import servertable;
import set;
import settings;


const char[] FIELDSEP = "\x1e"; // \x1e = ascii record separator



/**
 * Parse Qstat's output.
 *
 * Throws: when outputFileName is given: IOException.
 */
bool parseOutput(void delegate(Object) countDg, LineIterator!(char) iter,
                 char[] outputFileName=null)
{
	char[][] gtypes;
	BufferOutput outfile;
	debug scope timer = new Timer;
	int count = 0;
	scope countWrapper = new IntWrapper(-1);
	Display display = Display.getDefault;

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
		                  Float.toString(timer.seconds) ~ " seconds.");
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
		volatile if (abortParsing)
			break;

		char[] line = iter.next();
		if (line is null)
			break;

		if (outfile) {
			outfile.write(line);
			outfile.write(newline);
		}

		if (line.length >= 3 && line[0..3] == "Q3S") {
			char[][] fields = split(line.dup, FIELDSEP);
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
				line = iter.next();
				if (outfile) {
					outfile.write(line);
					outfile.write(newline);
				}
				if (!parseCvars(line, &sd, gtypes) && !keep_server)
					continue each_server;
				sortStringArray(sd.cvars);

				// parse players
				int humans = 0;
				while ((line = iter.next()) !is null && line.length) {
					if (outfile) {
						outfile.write(line);
						outfile.write(newline);
					}
					char[][] s = split(line.dup, FIELDSEP);
					char player[][];
					player.length = PlayerColumn.max + 1;
					player[PlayerColumn.RAWNAME] = s[0];
					player[PlayerColumn.SCORE]   = s[1];
					player[PlayerColumn.PING]    = s[2];
					player[PlayerColumn.NAME]    = null;
					sd.players ~= player;

					if (player[PlayerColumn.PING] != "0") {
						humans++;
					}
				}

				// 'Players' column contents
				uint ate;
				int total = parse(fields[5], 10, &ate);

				if (ate < fields[5].length)
					invalidInteger(sd.rawName, fields[5]);

				int bots = total - humans;
				if (bots < 0)
					bots = 0;

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
 * Parses a line of cvars, each cvar of the form "name=value".  If there's more
 * than one cvar, FIELDSEP is expected to separate each name/value pair.  The
 * cvars are appended to sd.cvars.  The gametype and password fields of
 * sd.server are also set.
 *
 * If this function discovers that a server does not run the currently active
 * mod, it aborts parsing and returns immediately.  It checks this by parsing
 * the 'game' and 'gamename' cvars.
 *
 * The strings that are the output of this function will be slices into an
 * heap-allocated copy of the line parameter.
 *
 * Params:
 *     line   = String to parse.
 *     sd     = Output, only sd.cvars and sd.server are changed.  sd.rawName
 *              is used for error reporting, but not written to.
 *     gtypes = Game type names, indexed with the value of the 'gametype' cvar
 *              to find the value of sd.server's Game type column.  If
 *              gametype >= gtypes.length, the number is used instead.
 *
 * Returns: false if this server is found to belong to a different mod than the
 *          active one, otherwise true.
 *
 */
private bool parseCvars(in char[] line, ServerData* sd, in char[][] gtypes)
in {
	assert(ServerColumn.GAMETYPE < sd.server.length &&
	                               ServerColumn.PASSWORDED < sd.server.length);
}
body {
	char[][] temp = split(line.dup, FIELDSEP);
	bool keepServer = MOD_ONLY ? false : true;

	foreach (char[] s; temp) {
		char[][] cvar = split(s, "=");
		switch (cvar[0]) {
			case "gametype":
				uint ate;
				int gt = parse(cvar[1], 10, &ate);
				if (ate < cvar[1].length) {
					invalidInteger(sd.rawName, cvar[1]);
					sd.server[ServerColumn.GAMETYPE] = "???";
				}
				else if (gt < gtypes.length) {
					sd.server[ServerColumn.GAMETYPE] = gtypes[gt];
				}
				else {
					sd.server[ServerColumn.GAMETYPE] = toString(gt);
				}
				break;
			case "game":  // not sure if this is right, risk getting too many servers
				if (!keepServer &&
				          icompare(cvar[1], activeMod.name) == 0) {
					keepServer = true;
				}
				break;
			case "gamename":  // has to come after case "game"
				if (!keepServer &&
				          icompare(cvar[1], activeMod.name) == 0) {
					keepServer = true;
				}

				// Since qstat's 'game' pseudo cvar always is listed before
				// 'gamename', it's safe to abort parsing here in the case
				// that keep_server still is false.
				if (!keepServer)
					return false;
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

	return keepServer;
}


private void invalidInteger(in char[] serverName, in char[] badValue)
{
	char[] msg = "Invalid value reading server \"" ~ serverName ~ "\", " ~
	             "\"" ~ badValue ~ "\" doesn't parse as an integer.";

	debug db(msg);
	else log(msg);
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
 * Returns: A set of strings containing the IP and port of each server that was
 *          output to the file.
 *
 * Throws: IOException.
 */
Set!(char[]) filterServerFile(in char[] readFrom, in char writeTo[])
{
	scope infile = new TextFileInput(readFrom);
	scope outfile = new BufferOutput(
	                        new FileConduit(writeTo, FileConduit.WriteCreate));
	Set!(char[]) keptServers;

	void outputServer(in char[] address)
	{
		outfile.write(address);
		outfile.write(newline);
		assert(address.length == 0 || isdigit(address[0]));
		keptServers.add(address);
	}

	while (infile.next()) {
		char[] line = infile.get();

		if (line.length >= 3 && line[0..3] == "Q3S") {
			char[][] fields = split(line.dup, FIELDSEP);

			// FIXME: workaround for tango split() bug, issue #942
			if (fields.length == 8)
				fields ~=  "";

			assert(fields.length == 9 || fields.length == 3);

			if (fields.length < 9)
				continue;  // server probably timed out

			if (!MOD_ONLY) {
				outputServer(fields[1]);
			}
			else if (/*activeMod.name != "baseq3" &&*/
			                        icompare(fields[8], activeMod.name) == 0) {
				outputServer(fields[1]);
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
						outputServer(fields[1]);
						break;
					}
					if (cvar[0] == "gamename" &&
					                  icompare(cvar[1], activeMod.name) == 0) {
						outputServer(fields[1]);
						break;
					}
				}
			}
		}
	}

	infile.close();
	outfile.flush().close();

	return keptServers;
}
