module serverdata;

debug import tango.core.Thread;
import tango.stdc.ctype;
import tango.text.Ascii;
import tango.text.Util;
import Integer = tango.text.convert.Integer;
debug import tango.util.log.Trace;

import dwt.graphics.TextLayout;

import common;


/** Stores all data for a server. */
struct ServerData {
	/// server name, with any color codes intact
	char[] rawName;
	/// name (without color codes), ping, playercount, map, etc.
	char[][] server;
	/// list of players, with country, name, score, ping, and raw name (with color
	/// codes) for each.
	char[][][] players;
	/// list of cvars, with key and value for each
	char[][][] cvars;

	TextLayout customData = null;

	int failCount = 0;

	/*
	 * Extract some info about the server.
	 *
	 * Default to zero when there is no info available.
	 */
	int humanCount()
	{
		auto r = Integer.convert(server[ServerColumn.PLAYERS]);
		assert(r >= 0 && r <= int.max);
		return r;
	}

	/// ditto
	int botCount()
	{
		char[] s = server[ServerColumn.PLAYERS];
		auto plus = locate(s, '+');

		if (plus != s.length) {
			auto r = Integer.convert(s[plus+1 .. $]);
			assert(r >= 0 && r <= int.max);
			return r;
		}
		else {
			return 0;
		}
	}

	/// ditto
	int maxClients()
	{
		char[] s = server[ServerColumn.PLAYERS];
		auto slash = locate(s, '/');

		if (slash != s.length) {
			auto r = Integer.convert(s[slash+1 .. $]);
			assert(r >= 0 && r <= int.max);
			return r;
		}
		else {
			return 0;
		}
	}

	/*
	 * Extract some info about the server.
	 *
	 * Default to false when there is no info available.
	 */
	bool hasHumans()
	{
		char[] players = server[ServerColumn.PLAYERS];
		return  players.length && players[0] != '0';
	}

	/// ditto
	bool hasBots()
	{
		char[] s = server[ServerColumn.PLAYERS];
		auto plus = locate(s, '+');
		return ((plus + 1) < s.length) && (s[plus+1] != '0');
	}
}


// should correspond to playertable.playerHeaders
enum PlayerColumn { NAME, SCORE, PING, RAWNAME };
// should correspond to servertable.serverHeaders
enum ServerColumn {
	COUNTRY, NAME, PASSWORDED, PING, PLAYERS, GAMETYPE, MAP, ADDRESS
};


/**
 * Does this server run the given mod?
 *
 * Also returns false if there is no data to match against.
 */
bool matchMod(in ServerData* sd, in char[] mod, bool* hasMatchData=null)
{
	bool hasData = false;
	bool matched = false;

	foreach (cvar; sd.cvars) {
		if (cvar[0] == "game" || cvar[0] == "gamename") {
			hasData = true;
			if (icompare(cvar[1], mod) == 0)
				matched = true;
		}
	}

	static if (!MOD_ONLY) {
		hasData = true;
		matched = true;
	}

	if (hasMatchData)
		*hasMatchData = hasData;

	return matched;
}


/// Did this server time out when last queried?
bool timedOut(in ServerData* sd)
{
	char[] ping = sd.server[ServerColumn.PING];
	return ping == TIMEOUT;
}


///
const MAX_FAIL_COUNT = 2;

///
const char[] TIMEOUT = "9999";

///
const char[][] defaultGameTypes = ["FFA", "1v1", "SP", "TDM", "CTF",
                                   /* "OFCTF", "Overload", "Harvester", */
                                  ];

///
char[][][char[]] gameTypes;


static this() {
	gameTypes["osp"] = split("FFA 1v1 SP TDM CTF CA", " ");
	gameTypes["q3ut3"] = split("FFA FFA FFA TDM TS FtL C&H CTF B&D", " ");
	gameTypes["q3ut4"] = split("FFA FFA FFA TDM TS FtL C&H CTF B&D", " ");
	gameTypes["smokinguns"] = split("FFA Duel 2 TDM RTP BR", " ");
	gameTypes["westernq3"]  = split("FFA Duel 2 TDM RTP BR", " ");
	gameTypes["wop"] = split("FFA 1v1 2 SyC LPS TDM 6 SyCT BB", " ");
}


/// Print contents of sd to stdout.  Debugging tool.
debug void print(ref ServerData sd, char[] file=null, long line=-1)
{
	print(null, sd, file, line);
}

/// ditto
debug void print(char[] prefix, ref ServerData sd, char[] file=null, long line=-1)
{
	if (file)
		Trace.format(prefix ~ " ====== {}({}) ======", file, line);
	else
		Trace.format(prefix ~ " ====================");
	Trace.formatln(" thread: {} address: {}", cast(void*)Thread.getThis(), &sd);
	Trace.formatln("rawName({}): {}", sd.rawName.ptr, sd.rawName);
	Trace.formatln("server ping({}): {}", sd.server[ServerColumn.PING].ptr, sd.server[ServerColumn.PING]);
	Trace.formatln("server gametype({}): {}", sd.server[ServerColumn.GAMETYPE].ptr, sd.server[ServerColumn.GAMETYPE]);
	Trace.formatln("server map({}): {}", sd.server[ServerColumn.MAP].ptr, sd.server[ServerColumn.MAP]);
	Trace.formatln("server address({}): {}", sd.server[ServerColumn.ADDRESS].ptr, sd.server[ServerColumn.ADDRESS]);
	foreach (cvar; sd.cvars)
		Trace.formatln("cvar ({}){}: ({}){}", cvar[0].ptr, cvar[0], cvar[1].ptr, cvar[1]);
	foreach (player; sd.players)
		Trace.formatln("player({}) : {} score({}): {} ping({}): {}", player[3].ptr, player[3], player[1].ptr, player[1], player[2].ptr, player[2]);

	Trace.formatln("=============================");
	Trace.formatln("");
	Trace.flush();
}
