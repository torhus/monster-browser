module serverdata;

debug import tango.core.Thread;
import tango.text.Ascii;
import tango.text.Util;
import Integer = tango.text.convert.Integer;
debug import tango.util.log.Trace;

import dwt.graphics.TextLayout;


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

	/// Extract some info about the server. Always returns >= 0.
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
		auto r = Integer.convert(s[locate(s, '+')+1 .. $]);
		assert(r >= 0 && r <= int.max);
		return r;
	}

	/// ditto
	int maxClients()
	{
		char[] s = server[ServerColumn.PLAYERS];
		auto r = Integer.convert(s[locate(s, '/')+1 .. $]);
		assert(r >= 0 && r <= int.max);
		return r;
	}

	/// Extract some info about the server.
	bool hasHumans() { return server[ServerColumn.PLAYERS][0] != '0'; }

	/// ditto
	bool hasBots()
	{
		char[] s = server[ServerColumn.PLAYERS];
		return (s[locate(s, '+')+1] != '0');
	}
}


// should correspond to playertable.playerHeaders
enum PlayerColumn { NAME, SCORE, PING, RAWNAME };
// should correspond to servertable.serverHeaders
enum ServerColumn {
	COUNTRY, NAME, PASSWORDED, PING, PLAYERS, GAMETYPE, MAP, ADDRESS
};


/// Returns true if this server runs the correct mod.
bool matchMod(in ServerData* sd, in char[] mod)
{
	foreach (cvar; sd.cvars) {
		if ((cvar[0] == "game" || cvar[0] == "gamename") &&
		                                           icompare(cvar[1], mod) == 0)
			return true;
	}
	return false;
}


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
void print(ref ServerData sd, char[] file=null, long line=-1)
{
	print(null, sd, file, line);
}

/// ditto
void print(char[] prefix, ref ServerData sd, char[] file=null, long line=-1)
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