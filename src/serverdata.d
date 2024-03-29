module serverdata;

debug import core.thread;
import std.ascii : isDigit;
import std.conv;
import std.string;
import std.uni : sicmp;

import colorednames : stripColorCodes;
import common;
import gameconfig;


/** Stores all data for a server. */
struct ServerData {
	/// server name, with any color codes intact
	string rawName;
	/// g_gametype cvar's value, or -1 if missing or invalid.
	int numericGameType = -1;
	/// name (without color codes), ping, playercount, map, etc.
	/// Note: If this is a zero-length array, this object is considered to be
	/// empty, and can be deleted.
	string[] server;
	/// list of players, with country, name, score, ping, and raw name (with color
	/// codes) for each.
	string[][] players;
	/// list of cvars, with key and value for each
	string[][] cvars;

	string countryName;  ///

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
		if (s.length > 0 && isDigit(s[0]))
			return parse!int(s);
		return 0;
	}

	/// ditto
	int botCount() const
	{
		string s = server[ServerColumn.PLAYERS];
		ptrdiff_t plus = indexOf(s, '+');

		if (plus != -1) {
			string t = s[plus+1 .. $];
			if (isDigit(t[0]))
				return parse!int(t);
		}
		return 0;
	}

	/// ditto
	int maxClients() const
	{
		string s = server[ServerColumn.PLAYERS];
		ptrdiff_t slash = indexOf(s, '/');

		if (slash != -1) {
			string t = s[slash+1 .. $];
			if (isDigit(t[0]))
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
		ptrdiff_t plus = indexOf(s, '+');
		if (plus != -1)
			return ((plus + 1) < s.length) && (s[plus+1] != '0');
		return false;
	}
}


// should correspond to playertable.playerHeaders
enum PlayerColumn { NAME, SCORE, PING, RAWNAME }
// should correspond to servertable.serverHeaders
enum ServerColumn {
	COUNTRY, NAME, PASSWORDED, PING, PLAYERS, GAMETYPE, GAMETYPE_NUM, MAP,
	ADDRESS, CVAR_GAME, CVAR_GAMENAME
}


enum PASSWORD_YES = "X";  ///
enum PASSWORD_NO  = "";  ///

///
enum TIMEOUT = "9999";


///
void addCleanPlayerNames(string[][] players)
{
	foreach (p; players) {
		if (p[PlayerColumn.NAME] is null)
			p[PlayerColumn.NAME] = stripColorCodes(p[PlayerColumn.RAWNAME]);
	}
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

	static if (!MOD_ONLY)
		return true;

	if (sicmp(sd.server[ServerColumn.CVAR_GAME], game.mod) == 0 ||
	             sicmp(sd.server[ServerColumn.CVAR_GAMENAME], game.mod) == 0) {
		return true;
	}

	return game.mod.length == 0 && sd.cvars.length > 0;
}


/**
 * Returns the game type name corresponding to the given the numeric type.
 */
string getGameTypeName(in GameConfig game, int type)
{
	if (type < 0)
		return "";

	const(string)[] gtypes = game.gameTypes;

	if (gtypes is null) {
		// Fall back to hardcoded names or Q3 defaults.
		string[]* t = game.mod in gameTypes;
		gtypes = t ? *t : defaultGameTypes;
	}

	return type < gtypes.length ? gtypes[type] : to!string(type);
}

/// Did this server time out when last queried?
bool timedOut(in ServerData* sd)
{
	return sd.server[ServerColumn.PING] == TIMEOUT;
}

/// Has this server ever responded?
bool hasReplied(in ServerData* sd)
{
	return sd.cvars.length > 0;
}

///
immutable defaultGameTypes = ["FFA", "1v1", "SP", "TDM", "CTF",
                           /* "OFCTF", "Overload", "Harvester", */
                             ];

///
__gshared string[][string] gameTypes;


shared static this() {
	// Initialize game type mappings.
	gameTypes["smokinguns"] = split("FFA Duel 2 TDM RTP BR", " ");
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
