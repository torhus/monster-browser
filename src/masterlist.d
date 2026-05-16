module masterlist;

import core.memory;
import std.array;
import std.ascii : newline;
import std.conv;
import std.file;
import std.path;
import std.stdio;
import std.uni;
import ddn.data.xml.stream;
import ddn.data.xml.write;

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
			sd.locationName = oldSd.locationName;
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

		auto content = cast(string)read(dataDir ~ fileName_);
		GC.setAttr(content.ptr, GC.BlkAttr.NO_SCAN);

		auto reader = new MyXmlReader(content, defaultProtocolVersion);
		reader.parse();

		log("Loaded %s servers in %s seconds.", reader.servers.length,
		                                                        timer.seconds);

		synchronized (this) {
			servers_ = reader.servers;
			downCount_ = reader.downCount;
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
		Timer timer;
		timer.start();

		scope dumper = new XmlDumper(dataDir ~ fileName_);

		synchronized (this) {
			foreach (sd; servers_)
				dumper.serverToXml(&sd);
		}

		dumper.close();
		log("Saved %s in %s seconds.", fileName_, timer.seconds);
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
private final class XmlDumper
{

	///
	this(string fileName)
	{
		XmlWriteOptions options = {
			pretty: true, indentation: "  ", newline: newline
		};
		output_ = File(fileName, "wb");
		auto sink = (const(char)[] v) { output_.write(v); };
		writer_ = new XmlStreamWriter(sink, options);
		writer_.startElement("masterserver");
	}


	///
	void close()
	{
		writer_.endElement();
		output_.close();
	}


	///
	void serverToXml(in ServerData* sd)
	{
		writer_.startElement("server");
		writer_.attribute("name",             sd.rawName);
		writer_.attribute("country_code",     sd.server[ServerColumn.COUNTRY]);
		writer_.attribute("address",          sd.server[ServerColumn.ADDRESS]);
		writer_.attribute("protocol_version", sd.protocolVersion);
		writer_.attribute("ping",             sd.server[ServerColumn.PING]);
		writer_.attribute("player_count",     sd.server[ServerColumn.PLAYERS]);
		writer_.attribute("map",              sd.server[ServerColumn.MAP]);
		writer_.attribute("persistent",       sd.persistent ? "true" : "false");
		writer_.attribute("fail_count",       to!string(sd.failCount));

		if (sd.cvars.length) {
			writer_.startElement("cvars");
			cvarsToXml(sd);
			writer_.endElement();
		}

		if (sd.players.length) {
			writer_.startElement("players");
			playersToXml(sd);
			writer_.endElement();
		}
		writer_.endElement();
	}


	private void cvarsToXml(in ServerData* sd)
	{
		foreach (cvar; sd.cvars) {
			writer_.startElement("cvar");
			writer_.attribute("key",   cvar[0]);
			writer_.attribute("value", cvar[1]);
			writer_.endElement();
		}
	}


	private void playersToXml(in ServerData* sd)
	{
		foreach (player; sd.players) {
			writer_.startElement("player");
			writer_.attribute("name",  player[PlayerColumn.RAWNAME]);
			writer_.attribute("score", player[PlayerColumn.SCORE]);
			writer_.attribute("ping",  player[PlayerColumn.PING]);
			writer_.endElement();
		}
	}

	private {
		XmlStreamWriter writer_;
		File output_;
	}
}


private final class MyXmlReader
{
	ServerData[string] servers;
	size_t downCount = 0;


	this(string xml, string defaultProtocolVersion)
	{
		defaultProtocolVersion_ = defaultProtocolVersion;
		reader_ = new XmlReader(xml);
	}


	void parse()
	{
		while(!reader_.empty) {
			auto element = reader_.front;
			switch (element.type) {
				case XmlEventType.START_ELEMENT:
					if (element.local == "server")
						startServer(element);
					else if (element.local == "cvars")
						addCvars();
					else if (element.local == "players")
						addPlayers();
					break;
				case XmlEventType.END_ELEMENT:
					if (element.local == "server")
						endServer();
					break;
				default:
				break;
			}
			reader_.popFront();
		}
	}


	// Allocate a new server and add server attributes.
	private void startServer(in XmlEvent event)
	{
		assert(event.local == "server");
		assert(event.type == XmlEventType.START_ELEMENT);

		sd.server.length = ServerColumn.max + 1;

		foreach (attr; event.attributes) {
			if (attr.local == "name") {
				sd.rawName = attr.value.dup;
				sd.server[ServerColumn.NAME] = stripColorCodes(attr.value);
			}
			else if (attr.local == "country_code")
				sd.server[ServerColumn.COUNTRY] = attr.value.dup;
			else if (attr.local == "address")
				sd.server[ServerColumn.ADDRESS] = attr.value.dup;
			else if (attr.local == "protocol_version")
				sd.protocolVersion = attr.value.dup;
			else if (attr.local == "ping")
				sd.server[ServerColumn.PING] = attr.value.dup;
			else if (attr.local == "player_count")
				sd.server[ServerColumn.PLAYERS] = attr.value.dup;
			else if (attr.local == "map")
				sd.server[ServerColumn.MAP] = attr.value.dup;
			else if (attr.local == "persistent")
				sd.persistent = attr.value == "true";
			else if (attr.local == "fail_count")
				sd.failCount = toIntOrDefault(attr.value);
		}

		// Make sure there's a protocol version.  This makes it less likely the
		// server is being 'forgotten' and never queried or deleted.
		// It also takes care of upgrading from the old XML files, where there
		// were no protocol_version attribute.
		if (sd.protocolVersion.length == 0)
			sd.protocolVersion = defaultProtocolVersion_;
	}


	void endServer()
	{
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


	private void addCvars()
	{
		assert(reader_.front.local == "cvars");
		assert(reader_.front.type == XmlEventType.START_ELEMENT);

		reader_.popFront();
		if (reader_.front.type == XmlEventType.TEXT)
			reader_.popFront();

		while(reader_.front.local != "cvars") {
			auto element = reader_.front;
			string[] cvar;

			switch (element.type) {
				case XmlEventType.START_ELEMENT: {
					cvar = new string[2];
					foreach (attr; element.attributes) {
						if (attr.local == "key")
							cvar[0] = attr.value.dup;
						else if (attr.local == "value")
							cvar[1] = attr.value.dup;
					}
					sd.cvars ~= cvar;
					break;
				}
				default:
					break;
			}
			reader_.popFront();
		}
	}


	private void addPlayers()
	{
		assert(reader_.front.local == "players");
		assert(reader_.front.type == XmlEventType.START_ELEMENT);

		reader_.popFront();
		if (reader_.front.type == XmlEventType.TEXT)
			reader_.popFront();

		while(reader_.front.local != "players") {
			auto element = reader_.front;
			string[] player;

			switch (element.type) {
				case XmlEventType.START_ELEMENT: {
					player = new string[PlayerColumn.max + 1];
					foreach (attr; element.attributes) {
						if (attr.local == "name")
							player[PlayerColumn.RAWNAME] = attr.value.dup;
						else if (attr.local == "score")
							player[PlayerColumn.SCORE] = attr.value.dup;
						else if (attr.local == "ping")
							player[PlayerColumn.PING] = attr.value.dup;
					}
					sd.players ~= player;
					break;
				}
				default:
					break;
			}
			reader_.popFront();
		}
	}


	private {
		XmlReader reader_;
		string defaultProtocolVersion_;
		ServerData sd;
	}
}
