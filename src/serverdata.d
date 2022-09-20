module serverdata;

debug import core.thread;
import core.stdc.ctype;
import std.conv;
import std.string;

import common;
import settings;


/** Stores all data for a server. */
struct ServerData {
	/// server name, with any color codes intact
	string rawName;
	/// name (without color codes), ping, playercount, map, etc.
	/// Note: If this is a zero-length array, this object is considered to be
	/// empty, and can be deleted.
	string[] server;
	/// list of players, with country, name, score, ping, and raw name (with color
	/// codes) for each.
	string[][] players;
	/// list of cvars, with key and value for each
	string[][] cvars;

	int failCount = 0;  ///

	bool persistent;  ///

	string protocolVersion;  ///


	///
	void setPlayersColumn(int humans, int bots, int maxClients)
	{
		server[ServerColumn.PLAYERS] = text(humans, "+", bots, "/", maxClients);
	}

	/*
	 * Extract some info about the server.
	 *
	 * Default to zero when there is no info available.
	 */
	int humanCount() const
	{
		string s = server[ServerColumn.PLAYERS];
		if (s.length > 0 && isdigit(s[0]))
			return parse!int(s);
		return 0;
	}

	/// ditto
	int botCount() const
	{
		string s = server[ServerColumn.PLAYERS];
		int plus = indexOf(s, '+');

		if (plus != -1) {
			string t = s[plus+1 .. $];
			if (isdigit(t[0]))
				return parse!int(t);
		}
		return 0;
	}

	/// ditto
	int maxClients() const
	{
		string s = server[ServerColumn.PLAYERS];
		int slash = indexOf(s, '/');

		if (slash != -1) {
			string t = s[slash+1 .. $];
			if (isdigit(t[0]))
				return parse!int(t);
		}
		return 0;
	}

	/*
	 * Extract some info about the server.
	 *
	 * Default to false when there is no info available.
	 */
	bool hasHumans() const
	{
		string players = server[ServerColumn.PLAYERS];
		return  players.length && players[0] != '0';
	}

	/// ditto
	bool hasBots() const
	{
		string s = server[ServerColumn.PLAYERS];
		int plus = indexOf(s, '+');
		if (plus != -1)
			return ((plus + 1) < s.length) && (s[plus+1] != '0');
		return false;
	}
}


// should correspond to playertable.playerHeaders
enum PlayerColumn { NAME, SCORE, PING, RAWNAME };
// should correspond to servertable.serverHeaders
enum ServerColumn {
	COUNTRY, NAME, PASSWORDED, PING, PLAYERS, GAMETYPE, MAP, ADDRESS
};


enum PASSWORD_YES = "X";  ///
enum PASSWORD_NO  = "";  ///

///
enum TIMEOUT = "9999";


/// Set sd to the empty state.
void setEmpty(ServerData* sd)
{
	sd.rawName = null;
	sd.server  = null;
	sd.players = null;
	sd.cvars   = null;
}


/// Is sd empty?
bool isEmpty(in ServerData* sd)
{
	return sd.server.length == 0;
}


/**
 * Does this server match the given game configuration?
 *
 * Also returns false if there is no data to match against.
 */
bool matchGame(in ServerData* sd, in GameConfig game)
{
	if (sd.protocolVersion != game.protocolVersion)
		return false;

	debug bool gameMatched = false;

	// FIXME: use binary search?
	foreach (cvar; sd.cvars) {
		if (cvar[0] == "gamename") {
			if (icmp(cvar[1], game.mod) == 0) {
				return true;
			}
			else {
				debug {
					/* do nothing */
				}
				else {
					break;
				}
			}
		}
		debug if (cvar[0] == "game" && icmp(cvar[1], game.mod) == 0) {
			gameMatched = true;
		}
	}

	debug if (gameMatched) {
		log("Skipped (game matched) %s (%s)",
		        sd.server[ServerColumn.NAME], sd.server[ServerColumn.ADDRESS]);
	}

	static if (MOD_ONLY)
		return false;
	else
		return true;
}


/// Did this server time out when last queried?
bool timedOut(in ServerData* sd)
{
	return sd.server[ServerColumn.PING] == TIMEOUT;
}


///
enum defaultGameTypes = ["FFA", "1v1", "SP", "TDM", "CTF",
                         /* "OFCTF", "Overload", "Harvester", */
                        ];

///
__gshared string[][string] gameTypes;


shared static this() {
	gameTypes["osp"] = split("FFA 1v1 SP TDM CTF CA", " ");
	gameTypes["q3ut3"] = split("FFA FFA FFA TDM TS FtL C&H CTF B&D", " ");
	gameTypes["q3ut4"] = split("FFA FFA FFA TDM TS FtL C&H CTF B&D", " ");
	gameTypes["smokinguns"] = split("FFA Duel 2 TDM RTP BR", " ");
	gameTypes["westernq3"]  = split("FFA Duel 2 TDM RTP BR", " ");
	gameTypes["wop"] = split("FFA 1v1 2 SyC LPS TDM 6 SyCT BB", " ");
	gameTypes["WorldofPadman"] = split("FFA 1v1 2 SyC LPS TDM CtL SyCT BB", " ");
}


/// Print contents of sd to stdout.  Debugging tool.
debug void print(ref ServerData sd, string file=null, long line=-1)
{
	print(null, sd, file, line);
}

/// ditto
debug void print(string prefix, ref const ServerData sd, string file=null, long line=-1)
{
/*	if (file)
		Log.formatln(prefix ~ " ====== {}({}) ======", file, line);
	else
		Log.formatln(prefix ~ " ====================");
	Log.formatln("thread: {} address: {}", cast(void*)Thread.getThis(), &sd);
	Log.formatln("rawName({}): {}", sd.rawName.ptr, sd.rawName);
	Log.formatln("server ping({}): {}", sd.server[ServerColumn.PING].ptr, sd.server[ServerColumn.PING]);
	Log.formatln("server gametype({}): {}", sd.server[ServerColumn.GAMETYPE].ptr, sd.server[ServerColumn.GAMETYPE]);
	Log.formatln("server map({}): {}", sd.server[ServerColumn.MAP].ptr, sd.server[ServerColumn.MAP]);
	Log.formatln("server address({}): {}", sd.server[ServerColumn.ADDRESS].ptr, sd.server[ServerColumn.ADDRESS]);
	foreach (cvar; sd.cvars)
		Log.formatln("cvar ({}){}: ({}){}", cvar[0].ptr, cvar[0], cvar[1].ptr, cvar[1]);
	foreach (player; sd.players)
		Log.formatln("player({}) : {} score({}): {} ping({}): {}", player[3].ptr, player[3], player[1].ptr, player[1], player[2].ptr, player[2]);

	Log.formatln("=============================");
	Log.formatln("");
*/
}
