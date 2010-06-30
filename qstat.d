/**
 * Functions to parse Qstat's raw format output when querying game servers.
 */

module qstat;

import std.stdio;
import std.stream : InputStream;
import tango.text.Ascii;
import tango.text.Util;
import tango.text.convert.Integer;

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
bool parseOutput(in char[] modName, InputStream input,
                 bool delegate(ServerData*, bool replied) deliver)
{
	char[][] gtypes;
	File outfile;
	debug Timer timer2;
	debug timer2.start();
	bool keepGoing = true;

	assert(deliver);

	if (arguments.dumpqstat) {
		try {
			outfile = File("qstat.out", "w");
		}
		catch (StdioException e) {
			error("Unable to create file, qstat output will not be saved "
			                                                       "to disk.");
		}
	}

	if (modName in gameTypes) {
		gtypes = gameTypes[modName];
	}
	else {
		gtypes = defaultGameTypes;
	}

	while (keepGoing && !input.eof()) {
		debug checkTime(timer2, "1");
		char[] line = input.readline();
		debug checkTime(timer2, "2");
		if (!line)
			break;

		if (outfile.isOpen)
			outfile.writeln(line);

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
				line = input.readline();
				if (outfile.isOpen)
					outfile.writeln(line);

				parseCvars(line, &sd, gtypes);

				sortStringArray(sd.cvars);

				// parse players
				int humans;
				sd.players = parsePlayers(input, &humans, outfile);

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
			if (outfile.isOpen) {
				outfile.writeln();
			}
		}
	}

	return keepGoing;
}


debug private void checkTime(ref Timer t, string name)
{
	auto time = t.seconds;
	if (time >= 2)
		log("qstat timer %s: %s", name, time);
	t.start();
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
 *     sd       = Output, only sd.cvars, sd.server, and sd.protocolVersion are
 *                changed.  sd.rawName is used for error reporting, but not
 *                written to.
 *     gtypes   = Game type names, indexed with the value of the 'gametype'
 *                cvar to find the value of sd.server's Game type column.  If
 *                gametype >= gtypes.length, the number is used instead.
 */
private void parseCvars(in char[] line, ServerData* sd,
                                                       in char[][] gtypes=null)
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

		// FIXME: avoid this cast
		sd.cvars ~= cast(string[])cvar;
	}
}


private string[][] parsePlayers(InputStream input, int* humanCount,
                                                                   File output)
{
	string[][] players;
	char[] line;
	int humans = 0;

	while (!input.eof() && (line = input.readline(line))) {
		if (output.isOpen)
			output.writeln(line);
		// FIXME: use phobos splitting, to avoid assumeUnique?
		char[][] s = split(line.dup, FIELDSEP);
		string[] player = new string[PlayerColumn.max + 1];
		player[PlayerColumn.RAWNAME] = assumeUnique!s[0];
		player[PlayerColumn.SCORE]   = assumeUnique!s[1];
		player[PlayerColumn.PING]    = assumeUnique!s[2];
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
