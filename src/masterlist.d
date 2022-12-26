module masterlist;

import core.memory;
import std.array;
import std.conv;
import std.file;
import std.path;
import std.range : isInputRange;
import std.stdio;
import std.uni;
import tango.text.xml.DocEntity;
import tango.text.xml.SaxParser;

import colorednames;
import common;
import serverdata;


///
alias ServerHandle = string;

///
const ServerHandle invalidServerHandle = "";


///
final class MasterList
{
	///
	this(string name)
	{
		assert(name.length > 0);
		name_ = name;
		fileName_ = replace(name ~ ".xml", ":", "_");
	}

	
	/// Name, as given to the constructor.
	string name() const { return name_; }
	
	
	/// The name of the file this master server's data is stored in.
	string fileName() const { return fileName_; }


	/// Add a server, and return its ServerHandle.
	ServerHandle addServer(ServerData sd)
	{
		synchronized (this) {
			string address = sd.server[ServerColumn.ADDRESS];
			debug isValid(&sd);
			if (timedOut(&sd)) {
				sd.failCount = 1;
				if (!hasReplied(&sd))
					downCount_++;
			}

			assert(!(address in servers_));
			servers_[address] = sd;
			return address;
		}
	}


	/**
	 * Update the data for a server in the master list.
	 *
	 * Will update the first server found whose address matches the one of sd.
	 * The country code and name, and the persistency state, will be kept.
	 *
	 * Returns: The server's handle if it was found in the list, or
	 *          invalidServerHandle if not.
	 */
	ServerHandle updateServer(ServerData sd)
	{
		synchronized (this) {
			string address = sd.server[ServerColumn.ADDRESS];
			debug isValid(&sd);
			ServerData* oldSd = address in servers_;

			if (oldSd is null)
				return invalidServerHandle;

			// some data is be kept between refreshes
			sd.server[ServerColumn.COUNTRY] =
				                        oldSd.server[ServerColumn.COUNTRY];
			sd.countryName = oldSd.countryName;
			sd.persistent = oldSd.persistent;

			if (timedOut(&sd)) {
				oldSd.server[ServerColumn.PING] =
					                            sd.server[ServerColumn.PING];
				// clear player count
				oldSd.setPlayersColumn(0, 0, oldSd.maxClients);
				oldSd.players = null;

				oldSd.failCount++;
			}
			else {
				if (!hasReplied(oldSd)) {
					assert(downCount_ > 0);
					downCount_--;
				}
				setServerData(address, sd);
			}

			return address;
		}
	}

	///
	void removeServer(ServerHandle sh)
	{
		ServerData* sd = sh in servers_;
		if (sd) {
			if (!hasReplied(sd))
				downCount_--;
			servers_.remove(sh);
		}
	}


	/**
	 * Given a server address, returns the handle.
	 *
	 * Returns invalidServerHandle in case a server with the given address was
	 * not found.
	 */
	ServerHandle findServer(in char[] address)
	{
		synchronized (this) {
			if (ServerData* sd = address in servers_) {
				assert(sd.server.length > 0 &&
				                   sd.server[ServerColumn.ADDRESS] == address);
				return sd.server[ServerColumn.ADDRESS];
			}
			return invalidServerHandle;
		}
	}


	/// Will assert if sh is invalid.
	ServerData getServerData(ServerHandle sh)
	{
		synchronized (this) {
			ServerData* sd = sh in servers_;
			assert(sh !is null);
			debug isValid(sd);
			return *sd;
		}
	}


	/// Will assert if sh is invalid.
	void setServerData(ServerHandle sh, ServerData sd)
	{
		synchronized (this) {
			assert(sh in servers_);
			ServerData* old = sh in servers_;
			debug isValid(old);
			*old = sd;
		}
	}


	/// Total number of servers.
	size_t length() const { return servers_.length; }

	/// Number of servers that have never replied.
	size_t downCount() const { return downCount_; }


	/**
	* Foreach support.
	*/
	int opApply(int delegate(ref ServerHandle) dg) const
	{
		synchronized (this) {
			int result = 0;

			foreach (sh, sd; servers_) {
				result = dg(sh);
				if (result)
					break;
			}
			return result;
		}
	}


	/**
	 * Load the server list from file.
	 *
	 * Returns: false if the file didn't exist, true if the contents were
	 *          successfully read.
	 *
	 * Params:
	 *     defaultProtocolVersion = Used for servers that have a missing or
	 *                              empty protocol_version attribute.
	 *
	 * Throws: FileException if an error occurred during reading.
	 *         XmlException for XML syntax errors.
	 *
	 * Note: After calling this, all ServerHandles that were obtained before
	 *       calling it should be be considered invalid.
	 */
	bool load(string defaultProtocolVersion)
	{
		if (!exists(dataDir ~ fileName_))
			return false;

		log("Opening '%s'...", fileName_);

		Timer timer;
		timer.start();

		char[] content = cast(char[])read(dataDir ~ fileName_);
		GC.setAttr(content.ptr, GC.BlkAttr.NO_SCAN);
		auto parser = new SaxParser!(char);
		auto handler = new MySaxHandler!(char)(defaultProtocolVersion);

		parser.setSaxHandler(handler);
		parser.setContent(content);
		parser.parse;

		log("Loaded %s servers in %s seconds.", handler.servers.length,
		                                                        timer.seconds);

		synchronized (this) {
			servers_ = handler.servers;
			downCount_ = handler.downCount;
		}

		return true;
	}


	/**
	 * Save all data.
	 *
	 * Throws: StdioException.
	 */
	void save()
	{
		string jsonFileName = setExtension(fileName_, "json");
		Timer timer;
		timer.start();

		synchronized (this) {
			servers_.byValue().dumpJson(dataDir ~ jsonFileName);
		}

		log("Saved %s in %s seconds.", jsonFileName, timer.seconds);
	}


	///
	private bool isValid(in ServerData* sd) const
	{
		if (!isValidIpAddress(sd.server[ServerColumn.ADDRESS])) {
			debug print("MasterList.isValid()" , *sd);
			return false;
		}
		return true;
	}


	/*invariant()
	{
		synchronized (this) {
			foreach (i, sd; servers_) {
				char[] address = sd.server[ServerColumn.ADDRESS];
				if (!isValidIpAddress(address)) {
					Log.formatln("Address: ({}) {}", i, address);
					assert(0, "MasterList: invalid address");
				}
			}
		}
	}*/


	private {
		string name_;
		string fileName_;
		ServerData[string] servers_;
		size_t downCount_ = 0;
	}
}


///
void dumpJson(R)(R servers, string path)
	if (isInputRange!R)
{
	bool first = true;
	auto f = File(path, "w");

	void cvarsToJson(const ref ServerData sd, bool last)
	{
		f.writeln(`    "cvars": {`);
		foreach (i, cvar; sd.cvars) {
			f.writef(`      "%s": "%s"`, cvar[0], cvar[1]);
			f.writeln((i + 1 < sd.cvars.length) ? "," : "");
		}
		f.writeln(last ? "    }" : "    },");
	}

	void playersToJson(const ref ServerData sd)
	{
		f.writeln(`    "players": [`);
		foreach (i, player; sd.players) {
			f.writef(`      {"name": "%s", "score": "%s", "ping": "%s"}`,
			               player[PlayerColumn.RAWNAME],
			               player[PlayerColumn.SCORE],
			               player[PlayerColumn.PING]);
			f.writeln((i + 1 < sd.players.length) ? "," : "");
		}
		f.writeln("    ]");
	}

	f.writeln(`[`);

	foreach (sd; servers) {
		with (ServerColumn) {
			f.writeln(first ? "  {" : "  },\n  {");
			f.writefln(`    "name": "%s",`, sd.rawName);
			f.writefln(`    "countryCode": "%s",`,     sd.server[COUNTRY]);
			f.writefln(`    "address": "%s",`,         sd.server[ADDRESS]);
			f.writefln(`    "protocolVersion": "%s",`, sd.protocolVersion);
			f.writefln(`    "ping": "%s",`,            sd.server[PING]);
			f.writefln(`    "playerCount": "%s",`,     sd.server[PLAYERS]);
			f.writefln(`    "map": "%s",`,             sd.server[MAP]);
			f.writefln(`    "persistent": %s,`,      sd.persistent);
			f.writef(`    "failCount": %s`, sd.failCount);
			f.writefln((sd.cvars.length || sd.players.length) ? ",": "");
		}

		if (sd.cvars.length)
			cvarsToJson(sd, sd.players.length == 0);

		if (sd.players.length)
			playersToJson(sd);

		first = false;
	}

	f.writeln(first ? "]" : "  }\n]");
}


private final class MySaxHandler(Ch=char) : SaxHandler!(Ch)
{
	ServerData[string] servers;
	ServerData sd;
	size_t downCount = 0;

	private string defaultProtocolVersion_;


	this(string defaultProtocolVersion)
	{
		defaultProtocolVersion_ = defaultProtocolVersion;
	}

	override void startElement(const(Ch)[] uri, const(Ch)[] localName,
	                           const(Ch)[] qName, Attribute!(Ch)[] attributes)
	{
		if (localName == "cvar")
			addCvar(attributes);
		else if (localName == "player")
			addPlayer(attributes);
		else if (localName == "server")
			startServer(attributes);
	}


	override void endElement(const(Ch)[] uri, const(Ch)[] localName,
	                         const(Ch)[] qName)
	{
		if (localName == "server") {
			auto cvars = sd.cvars;

			sortStringArray(cvars);

			if (auto cvar = cvars.getCvar("g_gametype")) {
				sd.server[ServerColumn.GAMETYPE_NUM] = cvar[1];
				sd.numericGameType = toIntOrDefault(cvar[1], -1);
			}
			if (auto cvar = cvars.getCvar("g_needpass")) {
				string s = cvar[1] == "0" ? PASSWORD_NO : PASSWORD_YES;
				sd.server[ServerColumn.PASSWORDED] = s;
			}
			if (auto cvar = cvars.getCvar("game")) {
				sd.server[ServerColumn.CVAR_GAME] = cvar[1];
			}
			if (auto cvar = cvars.getCvar("gamename")) {
				sd.server[ServerColumn.CVAR_GAMENAME] = cvar[1];
			}

			if (!hasReplied(&sd))
				downCount++;

			servers[sd.server[ServerColumn.ADDRESS]] = sd;
			sd = ServerData.init;
		}
	}


	// Allocate a new server and add server attributes.
	private void startServer(Attribute!(Ch)[] attributes)
	{
		sd.server.length = ServerColumn.max + 1;

		foreach (ref attr; attributes) {
			if (attr.localName == "name") {
				sd.rawName = fromEntityCopy(attr.value);
				sd.server[ServerColumn.NAME] =
				           cast(string)fromEntity(stripColorCodes(attr.value));
			}
			else if (attr.localName == "country_code")
				sd.server[ServerColumn.COUNTRY] = fromEntityCopy(attr.value);
			else if (attr.localName == "address")
				sd.server[ServerColumn.ADDRESS] = fromEntityCopy(attr.value);
			else if (attr.localName == "protocol_version")
				sd.protocolVersion = fromEntityCopy(attr.value);
			else if (attr.localName == "ping")
				sd.server[ServerColumn.PING] = fromEntityCopy(attr.value);
			else if (attr.localName == "player_count")
				sd.server[ServerColumn.PLAYERS] = fromEntityCopy(attr.value);
			else if (attr.localName == "map")
				sd.server[ServerColumn.MAP] = fromEntityCopy(attr.value);
			else if (attr.localName == "persistent")
				sd.persistent = attr.value == "true";
			else if (attr.localName == "fail_count")
				sd.failCount = toIntOrDefault(attr.value);
		}

		// Make sure there's a protocol version.  This makes it less likely the
		// server is being 'forgotten' and never queried or deleted.
		// It also takes care of upgrading from the old XML files, where there
		// were no protocol_version attribute.
		if (sd.protocolVersion.length == 0)
			sd.protocolVersion = defaultProtocolVersion_;
	}


	// Add a cvar.
	private void addCvar(Attribute!(Ch)[] attributes)
	{
		string[] cvar = new string[2];

		foreach (ref attr; attributes) {
			if (attr.localName == "key")
				cvar[0] = fromEntityCopy(attr.value);
			else if (attr.localName == "value")
				cvar[1] = fromEntityCopy(attr.value);
		}

		sd.cvars ~= cvar;
	}


	// Add a player.
	private void addPlayer(Attribute!(Ch)[] attributes)
	{
		string[] player = new string[PlayerColumn.max + 1];

		foreach (ref attr; attributes) {
			if (attr.localName == "name")
				player[PlayerColumn.RAWNAME] = fromEntityCopy(attr.value);
			else if (attr.localName == "score")
				player[PlayerColumn.SCORE] = fromEntityCopy(attr.value);
			else if (attr.localName == "ping")
				player[PlayerColumn.PING] = fromEntityCopy(attr.value);
		}

		sd.players ~= player;
	}

	// Convert XML entities to characters, unconditionally copying the source.
	string fromEntityCopy(in char[] s)
	{	
		const(char)[] r = fromEntity(s);
		if (r.ptr != s.ptr)
			return cast(string)r;
		else
			return s.idup;
	}

}
