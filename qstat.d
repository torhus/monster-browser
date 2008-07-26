/** What's specific for qstat */

module qstat;

import tango.core.Exception;
import tango.io.FileConduit;
import tango.io.model.IConduit : OutputStream;
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
import dialogs;
import main;
import runtools;
import serverlist;
import servertable;
import set;
import settings;


const char[] FIELDSEP = "\x1e"; // \x1e = ascii record separator

private enum Field {
	TYPE, ADDRESS, NAME, MAP, MAX_PLAYERS, PLAYER_COUNT, PING, RETRIES, GAME
}


/**
 * Parse Qstat's output.
 *
 * Throws: when outputFileName is given: IOException.
 */
bool parseOutput(LineIterator!(char) iter, void delegate(ServerData*) deliver,
                   void delegate(int) counter=null, char[] outputFileName=null)
{
	char[][] gtypes;
	BufferOutput outfile;
	debug scope timer = new Timer;
	int count = 0;
	Display display = Display.getDefault;

	assert(deliver);

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
			if (counter)
				counter(count);

			if (fields.length >= 9) {
				bool keep_server = false;

				if (icompare(fields[Field.GAME], activeMod.name) == 0)
					keep_server = true;

				/*if (activeMod.name != "baseq3" &&
				             MOD_ONLY &&
				             icmp(fields[Field.GAME], activeMod.name) != 0) {
					debug printf("skipped %.*s\n", line);
					debug line = readLine();
					debug printf("        %.*s\n", line);
					continue each_server;
				}*/

				sd.server.length = ServerColumn.max + 1;

				sd.rawName = fields[Field.NAME];
				sd.server[ServerColumn.COUNTRY] = "";
				sd.server[ServerColumn.PASSWORDED] = "";
				sd.server[ServerColumn.PING] = fields[Field.PING];
				sd.server[ServerColumn.PLAYERS] = "";
				sd.server[ServerColumn.GAMETYPE] = "";
				sd.server[ServerColumn.MAP] = fields[Field.MAP];
				sd.server[ServerColumn.ADDRESS] = fields[Field.ADDRESS];

				// parse cvars
				line = iter.next();
				if (outfile) {
					outfile.write(line);
					outfile.write(newline);
				}
				char[] matchMod = keep_server ? null : activeMod.name;
				if (!parseCvars(line, &sd, matchMod, gtypes))
					continue each_server;
				sortStringArray(sd.cvars);

				// parse players
				int humans;
				sd.players = parsePlayers(iter, &humans, outfile);

				// 'Players' column contents
				uint ate;
				int total = parse(fields[Field.PLAYER_COUNT], 10, &ate);

				if (ate < fields[Field.PLAYER_COUNT].length)
					invalidInteger(sd.rawName, fields[Field.PLAYER_COUNT]);

				int bots = total - humans;
				if (bots < 0)
					bots = 0;

				sd.server[ServerColumn.PLAYERS] = toString(humans) ~
				                  "+" ~ toString(bots) ~
				                  "/" ~ fields[Field.MAX_PLAYERS];

				sd.server[ServerColumn.NAME] = stripColorCodes(sd.rawName);

				deliver(&sd);
			}
			else /*if (!MOD_ONLY)*/ { // server didn't respond
				/*sd.server.length = servertable.serverHeaders.length;
				sd.server[ServerColumn.ADDRESS] = fields[Field.ADDRESS]; // ip
				deliver(sd);*/
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
 * The strings that are the output of this function will be slices into an
 * heap-allocated copy of the line parameter.
 *
 * Params:
 *     line     = String to parse.
 *     sd       = Output, only sd.cvars and sd.server are changed.  sd.rawName
 *                is used for error reporting, but not written to.
 *     matchMod = If not null, the 'game' and 'gamename' cvars are matched
 *                against this.  If they are different, the function aborts
 *                parsing and returns false immediately.
 *     gtypes   = Game type names, indexed with the value of the 'gametype'
 *                cvar to find the value of sd.server's Game type column.  If
 *                gametype >= gtypes.length, the number is used instead.
 *
 * Returns: false if the server doesn't match matchMod, otherwise true.  Always
 *          returns true when matchMod is null.
 *
 */
private bool parseCvars(in char[] line, ServerData* sd,
                        in char[] matchMod=null, in char[][] gtypes=null)
in {
	assert(ServerColumn.GAMETYPE < sd.server.length &&
	                               ServerColumn.PASSWORDED < sd.server.length);
}
body {
	char[][] temp = split(line.dup, FIELDSEP);
	bool keepServer = matchMod.length ? false : true;

	if (!MOD_ONLY)
		keepServer = true;

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
				          icompare(cvar[1], matchMod) == 0) {
					keepServer = true;
				}
				break;
			case "gamename":  // has to come after case "game"
				if (!keepServer &&
				          icompare(cvar[1], matchMod) == 0) {
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


private char[][][] parsePlayers(LineIterator!(char) lineIter,
                                int* humanCount=null, OutputStream output=null)
{
	char[][][] players;
	char[] line;
	int humans = 0;

	while ((line = lineIter.next()) !is null && line.length) {
		if (output) {
			output.write(line);
			output.write(newline);
		}
		char[][] s = split(line.dup, FIELDSEP);
		char player[][] = new char[][PlayerColumn.max + 1];
		player[PlayerColumn.RAWNAME] = s[0];
		player[PlayerColumn.SCORE]   = s[1];
		player[PlayerColumn.PING]    = s[2];
		player[PlayerColumn.NAME]    = null;
		players ~= player;

		if (player[PlayerColumn.PING] != "0") {
			humans++;
		}
	}

	if (humanCount)
		*humanCount = humans;

	return players;
}


private void invalidInteger(in char[] serverName, in char[] badValue)
{
	char[] msg = "Invalid value reading server \"" ~ serverName ~ "\", " ~
	             "\"" ~ badValue ~ "\" doesn't parse as an integer.";

	debug db(msg);
	else log(msg);
}


/**
 * Parses a server list file to find the addresses of all servers for the
 * currently active mod.  Optionally outputs the IP and port numbers to a file.
 *
 * Params:
 *     readFrom = File to read from.  The format is taken to be
 *                qstat's raw output.
 *     writeTo  = Optional. File to write to. The format is one IP:PORT combo
 *                per line.
 *
 * Returns: A set of strings containing the IP and port of each server that
 *          was found.
 *
 * Throws: IOException.
 */
Set!(char[]) filterServerFile(in char[] readFrom, in char writeTo[]=null)
{
	scope infile = new TextFileInput(readFrom);
	scope OutputStream outfile;
	Set!(char[]) keptServers;

	void outputServer(in char[] address)
	{
		if (outfile) {
			outfile.write(address);
			outfile.write(newline);
		}
		assert(address.length == 0 || isdigit(address[0]));
		keptServers.add(address);
	}

	if (writeTo)
		outfile = new BufferOutput(
	                        new FileConduit(writeTo, FileConduit.WriteCreate));

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
				outputServer(fields[Field.ADDRESS]);
			}
			else if (/*activeMod.name != "baseq3" &&*/
			               icompare(fields[Field.GAME], activeMod.name) == 0) {
				outputServer(fields[Field.ADDRESS]);
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
						outputServer(fields[Field.ADDRESS]);
						break;
					}
					if (cvar[0] == "gamename" &&
					                  icompare(cvar[1], activeMod.name) == 0) {
						outputServer(fields[Field.ADDRESS]);
						break;
					}
				}
			}
		}
	}

	infile.close();
	if (outfile)
		outfile.flush().close();

	return keptServers;
}
