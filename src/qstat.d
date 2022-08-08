/**
 * Functions to parse Qstat's raw format output when querying game servers.
 */

module qstat;

import tango.core.Exception;
import tango.io.device.File;
import tango.io.model.IConduit : OutputStream;
import tango.io.stream.Buffered;
import tango.io.stream.Lines;
import tango.stdc.ctype : isdigit;
import tango.text.Ascii;
import tango.text.Util;
import Float = tango.text.convert.Float;
debug import tango.text.convert.Format;
import tango.text.convert.Integer;
import tango.time.StopWatch;

import colorednames;
import common;
import messageboxes;
import serverdata;
import set;
import settings;


const char[] FIELDSEP = "\x1e"; // \x1e = ascii record separator

private enum Field {
	TYPE, ADDRESS, NAME, MAP, MAX_PLAYERS, PLAYER_COUNT, PING, RETRIES, GAME
}


/**
 * Parse Qstat's output.
 *
 * Returns: true if all servers were parsed and delivered, false if it stopped
 *          prematurely because of deliver() returning false;
 *
 * Throws: when outputFileName is given: IOException.
 */
bool parseOutput(in char[] modName, Lines!(char) iter,
                bool delegate(ServerData*, bool replied) deliver)
{
	scope BufferedOutput outfile = null;
	debug StopWatch timer2;
	debug timer2.start();
	bool keepGoing = true;

	assert(deliver);

	if (arguments.dumpqstat) {
		try {
			outfile = new BufferedOutput(new File(
			                                   "qstat.out", WriteCreateShared));
		}
		catch (IOException e) {
			error("Unable to create file, qstat output will not be saved "
			                                                       "to disk.");
			outfile = null;
		}
	}

	scope (exit) {
		if (outfile)
			outfile.flush.close;
	}

	while (keepGoing) {
		debug checkTime(timer2, "1");
		char[] line = iter.next();
		debug checkTime(timer2, "2");
		if (!line)
			break;

		if (outfile) {
			outfile.write(line);
			outfile.write(newline);
		}

		if (line.length >= 3 && line[0..3] == "Q3S") {
			char[][] fields = split(line.dup, FIELDSEP);
			ServerData sd;

			assert(fields.length >= 3);
			bool error = fields.length < Field.max + 1;

			sd.server.length = ServerColumn.max + 1;

			// still got the address in case of a timeout
			sd.server[ServerColumn.ADDRESS] = fields[Field.ADDRESS];

			if (!error) {
				sd.rawName = fields[Field.NAME];
				sd.server[ServerColumn.PING] = fields[Field.PING];
				sd.server[ServerColumn.MAP] = fields[Field.MAP];

				// cvar line
				line = iter.next();
				if (outfile) {
					outfile.write(line);
					outfile.write(newline);
				}

				parseCvars(line, &sd);

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

				sd.setPlayersColumn(humans, bots,
				                           convert(fields[Field.MAX_PLAYERS]));

				sd.server[ServerColumn.NAME] = stripColorCodes(sd.rawName);

				debug checkTime(timer2, "3");
				keepGoing = deliver(&sd, true);
				debug checkTime(timer2, "4");
			}
			else { // server didn't respond
				debug checkTime(timer2, "3x");
				sd.server[ServerColumn.PING] = TIMEOUT;
				keepGoing = deliver(&sd, false);
				debug checkTime(timer2, "4x");
			}
			if (outfile) {
				outfile.write(newline);
			}
		}
	}

	return keepGoing;
}


debug private void checkTime(ref StopWatch t, char[] name)
{
	auto time = t.stop();
	if (time >= 2)
		log(Format("qstat timer {}: {}", name, time));
	t.start();
}


/**
 * Parses a line of cvars, each cvar of the form "name=value".  If there's more
 * than one cvar, FIELDSEP is expected to separate each name/value pair.  The
 * cvars are appended to sd.cvars.
 *
 * The strings that are the output of this function will be slices into an
 * heap-allocated copy of the line parameter.
 *
 * Params:
 *     line     = String to parse.
 *     sd       = Output, only sd.cvars, sd.server, sd.numericGameType,
 *                and sd.protocolVersion are changed.  sd.rawName is used for
 *                error reporting, but not written to.
 */
private void parseCvars(in char[] line, ServerData* sd)
in {
	assert(ServerColumn.GAMETYPE < sd.server.length &&
	                               ServerColumn.PASSWORDED < sd.server.length);
}
body {
	char[][] temp = split(line.dup, FIELDSEP);

	foreach (char[] s; temp) {
		char[][] cvar = new char[][2];
		cvar[0] = head(s, "=", cvar[1]);

		switch (cvar[0]) {
			case "gametype":
				uint ate;
				int gt = parse(cvar[1], 10, &ate);
				if (ate == cvar[1].length) {
					sd.numericGameType = gt;
				}
				else {
					invalidInteger(sd.rawName, cvar[1]);
					sd.numericGameType = -1;
				}
				break;
			case "g_needpass":
				if (cvar[1] == "0")
					sd.server[ServerColumn.PASSWORDED] = PASSWORD_NO;
				else
					sd.server[ServerColumn.PASSWORDED] = PASSWORD_YES;
				break;
			case "protocol":
				sd.protocolVersion = cvar[1];
				break;
			default:
				break;
		}

		sd.cvars ~= cvar;
	}
}


private char[][][] parsePlayers(Lines!(char) lineIter,
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
