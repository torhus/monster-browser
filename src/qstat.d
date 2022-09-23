/**
 * Functions to parse Qstat's raw format output when querying game servers.
 */

module qstat;

import std.ascii : newline;
import std.conv;
import std.process;
import std.stdio;
import std.string;
import Integer = tango.text.convert.Integer;

import colorednames;
import common;
import messageboxes;
import serverdata;
import set;
import settings;


string FIELDSEP = "\x1e"; // \x1e = ascii record separator

private enum Field {
	TYPE, ADDRESS, NAME, MAP, MAX_PLAYERS, PLAYER_COUNT, PING, RETRIES, GAME
}


/**
 * Parse Qstat's output.
 *
 * Returns: true if all servers were parsed and delivered, false if it stopped
 *          prematurely because of deliver() returning false;
 *
 * Throws: StdioException when dumpqstat is specified.
 */
bool parseOutput(in char[] modName, File input,
                 bool delegate(ServerData*, bool replied) deliver)
{
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
			error("Unable to create file, qstat output will not be saved " ~
			                                                       "to disk.");
		}
	}

	while (keepGoing) {
		debug checkTime(timer2, "1");
		string line = stripRight(input.readln(), newline);
		debug checkTime(timer2, "2");
		if (!line)
			break;

		if (outfile.isOpen)
			outfile.writeln(line);

		if (line.startsWith("Q3S")) {
			string[] fields = split(line, FIELDSEP);
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
				line = stripRight(input.readln(), newline);
				if (outfile.isOpen)
					outfile.writeln(line);

				parseCvars(line, &sd);

				sortStringArray(sd.cvars);

				// parse players
				int humans;
				sd.players = parsePlayers(input, &humans, outfile);

				// 'Players' column contents
				uint ate;
				int total = cast(int)Integer.parse(fields[Field.PLAYER_COUNT], 10, &ate);

				if (ate < fields[Field.PLAYER_COUNT].length)
					invalidInteger(sd.rawName, fields[Field.PLAYER_COUNT]);

				int bots = total - humans;
				if (bots < 0)
					bots = 0;

				sd.setPlayersColumn(humans, bots,
				                  cast(int)Integer.convert(fields[Field.MAX_PLAYERS]));

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
 * cvars are appended to sd.cvars.
 *
 * The strings that are the output of this function will be slices into the
 * line parameter.
 *
 * Params:
 *     line     = String to parse.
 *     sd       = Output, only sd.cvars, sd.server, sd.numericGameType,
 *                and sd.protocolVersion are changed.  sd.rawName is used for
 *                error reporting, but not written to.
 */
private void parseCvars(string line, ServerData* sd)
in {
	assert(ServerColumn.GAMETYPE < sd.server.length &&
	                               ServerColumn.PASSWORDED < sd.server.length);
}
body {
	string[] temp = split(line, FIELDSEP);

	foreach (string s; temp) {
		int i = indexOf(s, '=');
		if (i == -1)
			continue;

		string[] cvar = new string[2];
		cvar[0] = s[0..i];
		cvar[1] = s[i+1..$];

		switch (cvar[0]) {
			case "gametype":
				uint ate;
				int gt = cast(int)Integer.parse(cvar[1], 10, &ate);
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


private string[][] parsePlayers(File input, int* humanCount, File output)
{
	string[][] players;
	int humans = 0;

	foreach (line; input.byLineCopy(KeepTerminator.no, newline)) {
		if (output.isOpen)
			output.writeln(line);

		// no more players?
		if (line.length == 0)
			break;

		string[] fields = split(line, FIELDSEP);
		string[] player = new string[PlayerColumn.max + 1];
		player[PlayerColumn.RAWNAME] = fields[0];
		player[PlayerColumn.SCORE]   = fields[1];
		player[PlayerColumn.PING]    = fields[2];
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
