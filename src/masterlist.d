module masterlist;

import core.memory;
import lib.phobosfixes; // DMD 2.052's icmp is broken.
import std.array;
import std.conv;
import std.file;
import std.path;
import std.stdio;
import std.uni;
import tango.text.xml.DocEntity;
import tango.text.xml.SaxParser;

import colorednames;
import common;
import serverdata;


///
alias size_t ServerHandle;

///
const ServerHandle InvalidServerHandle = ServerHandle.max;


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
			debug isValid(&sd);
			if (timedOut(&sd))
				sd.failCount = 1;
			servers_ ~= sd;
			return cast(ServerHandle)(servers_.length - 1);
		}
	}


	/**
	 * Update the data for a server in the master list.
	 *
	 * Will update the first server found whose address matches the one of sd.
	 * The country code and name, and the persistency state, will be kept.
	 *
	 * Returns: The server's handle if it was found in the list, or
	 *          InvalidServerHandle if not.
	 */
	ServerHandle updateServer(ServerData sd)
	{
		synchronized (this) {
			string address = sd.server[ServerColumn.ADDRESS];
			debug isValid(&sd);
			ServerHandle sh = findServer(address);

			if (sh != InvalidServerHandle) {
				ServerData* old = &servers_[sh];

				// some data is be kept between refreshes
				sd.server[ServerColumn.COUNTRY] =
				                              old.server[ServerColumn.COUNTRY];
				sd.countryName = old.countryName;
				sd.persistent = old.persistent;

				if (timedOut(&sd)) {
					old.server[ServerColumn.PING] =
					                              sd.server[ServerColumn.PING];
					// clear player count
					old.setPlayersColumn(0, 0, old.maxClients);
					old.players = null;

					old.failCount++;
				}
				else {
					setServerData(sh, sd);
				}
			}

			return sh;
		}
	}


	/**
	 * Given a server address, returns the handle.
	 *
	 * Returns InvalidServerHandle in case a server with the given address was
	 * not found.
	 *
	 * Complexity is O(n).
	 */
	ServerHandle findServer(in char[] address)
	{
		synchronized (this) {
			foreach (sh, sd; servers_) {
				if (sd.server.length > 0 &&
				                    sd.server[ServerColumn.ADDRESS] == address)
					return cast(ServerHandle)sh;
			}
			return InvalidServerHandle;
		}
	}


	/// Will assert if sh is invalid.
	ServerData getServerData(ServerHandle sh)
	{
		synchronized (this) {
			assert(sh < servers_.length);
			assert(!isEmpty(&servers_[sh]));
			debug isValid(&servers_[sh]);
			return servers_[sh];
		}
	}


	/// Will assert if sh is invalid.
	void setServerData(ServerHandle sh, ServerData sd)
	{
		synchronized (this) {
			assert(sh < servers_.length);
			ServerData* old = &servers_[sh];
			assert(!isEmpty(old));
			debug isValid(old);
			*old = sd;
		}
	}


	/// Total number of servers.
	size_t length() const { return servers_.length; }


	/**
	* Foreach support.  Skips servers for which isEmpty(sd) returns true.
	*/
	int opApply(int delegate(ref ServerHandle) dg) const
	{
		synchronized (this) {
			int result = 0;

			foreach (sh, sd; servers_) {
				if (isEmpty(&sd))
					continue;
				result = dg(cast(ServerHandle)sh);
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
			foreach (sd; servers_) {
				if (!isEmpty(&sd))
					dumper.serverToXml(&sd);
			}
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
		ServerData[] servers_;
	}
}


///
private final class XmlDumper
{

	///
	this(string fileName)
	{
		output_ = File(fileName, "w");
		output_.writeln(`<?xml version="1.0" encoding="UTF-8"?>`);
		output_.writeln("<masterserver>");
	}


	///
	void close()
	{
		output_.writeln("</masterserver>");
		output_.close();
	}


	///
	void serverToXml(in ServerData* sd)
	{
		outputXml(`  <server name=`, sd.rawName);
		outputXml(` country_code=`,  sd.server[ServerColumn.COUNTRY]);
		outputXml(` address=`,       sd.server[ServerColumn.ADDRESS]);
		outputXml(` protocol_version=`, sd.protocolVersion);
		outputXml(` ping=`,          sd.server[ServerColumn.PING]);
		outputXml(` player_count=`,  sd.server[ServerColumn.PLAYERS]);
		outputXml(` map=`,           sd.server[ServerColumn.MAP]);
		outputXml(` persistent=`,    sd.persistent ? "true" : "false");
		output_.writef(` fail_count="%s"`,    sd.failCount);
		output_.writeln(">");

		if (sd.cvars.length) {
			output_.writeln("    <cvars>");
			cvarsToXml(sd);
			output_.writeln("    </cvars>");
		}

		if (sd.players.length) {
			output_.writeln("    <players>");
			playersToXml(sd);
			output_.writeln("    </players>");
		}

		output_.writeln("  </server>");
	}


	private void cvarsToXml(in ServerData* sd)
	{
		foreach (cvar; sd.cvars) {
			outputXml(`      <cvar key=`, cvar[0]);
			outputXml(` value=`, cvar[1]);
			output_.writeln("/>");
		}
	}


	private void playersToXml(in ServerData* sd)
	{
		foreach (player; sd.players) {
			outputXml(`      <player name=`, player[PlayerColumn.RAWNAME]);
			outputXml(` score=`, player[PlayerColumn.SCORE]);
			outputXml(` ping=`, player[PlayerColumn.PING]);
			output_.writeln("/>");
		}
	}


	// Outputs prefix as-is, value in quotes and after encoding entities.
	private void outputXml(in char[] prefix, in char[] value)
	{
		char[100] buf = void;

		output_.write(prefix);
		output_.write("\"");
		output_.write(toEntity(value, buf));
		output_.write("\"");
	}


	private {
		File output_;
	}
}


private final class MySaxHandler(Ch=char) : SaxHandler!(Ch)
{
	ServerData[] servers;

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

	}


	// Allocate a new server and add server attributes.
	private void startServer(Attribute!(Ch)[] attributes)
	{
		ServerData sd;

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
		servers ~= sd;
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

			if (sicmp(cvar[0], "g_gametype") == 0) {
				servers[$-1].numericGameType = toIntOrDefault(cvar[1], -1);
			}
			else if (sicmp(cvar[0], "g_needpass") == 0) {
				string s = cvar[1] == "0" ? PASSWORD_NO : PASSWORD_YES;
				servers[$-1].server[ServerColumn.PASSWORDED] = s;
			}
		}

		servers[$-1].cvars ~= cvar;
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

		servers[$-1].players ~= player;
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
