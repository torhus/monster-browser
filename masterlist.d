module masterlist;

import core.memory;
import lib.phobosfixes; // DMD 2.052's icmp is broken.
import std.array;
import std.file;
import std.path;
import std.stdio;
import Integer = tango.text.convert.Integer;
import tango.text.xml.SaxParser;

import colorednames;
import common;
import serverdata;


///
typedef size_t ServerHandle;

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
	string name() { return name_; }
	
	
	/// The name of the file this master server's data is stored in.
	string fileName() { return fileName_; }


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
	 * The country code will be kept, since it's not suppposed to change.
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
				// country code is calculated locally, so we keep it
				sd.server[ServerColumn.COUNTRY] =
				                              old.server[ServerColumn.COUNTRY];
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
			ServerData* sd = &servers_[sh];
			assert(!isEmpty(sd));
			debug isValid(sd);
			return *sd;
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
	size_t length() { return servers_.length; }


	/**
	* Foreach support.  Skips servers for which isEmpty(sd) returns true.
	*/
	int opApply(int delegate(ref ServerHandle) dg)
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
		delete content;

		log("Loaded %s servers in %s seconds.", handler.servers.length,
		                                                        timer.seconds);

		synchronized (this) {
			delete servers_;
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
	private bool isValid(in ServerData* sd)
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
		output_.writef(`  <server name="%s"`, sd.rawName);
		output_.writef(` country_code="%s"`,  sd.server[ServerColumn.COUNTRY]);
		output_.writef(` address="%s"`,       sd.server[ServerColumn.ADDRESS]);
		output_.writef(` protocol_version="%s"`, sd.protocolVersion);
		output_.writef(` ping="%s"`,          sd.server[ServerColumn.PING]);
		output_.writef(` player_count="%s"`,  sd.server[ServerColumn.PLAYERS]);
		output_.writef(` map="%s"`,           sd.server[ServerColumn.MAP]);
		output_.writef(` persistent="%s"`,    sd.persistent ? "true" : "false");
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
		foreach (cvar; sd.cvars)
			output_.writefln(`      <cvar key="%s" value="%s"/>`,
			                                                 cvar[0], cvar[1]);
	}


	private void playersToXml(in ServerData* sd)
	{
		foreach (player; sd.players) {
			output_.writefln(`      <player name="%s" score="%s" ping="%s"/>`,
                                               player[PlayerColumn.RAWNAME],
											   player[PlayerColumn.SCORE],
											   player[PlayerColumn.PING]);
		}
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
				sd.rawName = attr.value.idup;
				sd.server[ServerColumn.NAME] = stripColorCodes(attr.value);
			}
			else if (attr.localName == "country_code")
				sd.server[ServerColumn.COUNTRY] = attr.value.idup;
			else if (attr.localName == "address")
				sd.server[ServerColumn.ADDRESS] = attr.value.idup;
			else if (attr.localName == "protocol_version")
				sd.protocolVersion = attr.value.idup;
			else if (attr.localName == "ping")
				sd.server[ServerColumn.PING] = attr.value.idup;
			else if (attr.localName == "player_count")
				sd.server[ServerColumn.PLAYERS] = attr.value.idup;
			else if (attr.localName == "map")
				sd.server[ServerColumn.MAP] = attr.value.idup;
			else if (attr.localName == "persistent")
				sd.persistent = attr.value == "true";
			else if (attr.localName == "fail_count")
				sd.failCount = cast(int)Integer.convert(attr.value);
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
				cvar[0] = attr.value.idup;
			else if (attr.localName == "value")
				cvar[1] = attr.value.idup;

			if (icmp(cvar[0], "g_gametype") == 0)
				servers[$-1].server[ServerColumn.GAMETYPE] = cvar[1];
			else if (icmp(cvar[0], "g_needpass") == 0) {
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
				player[PlayerColumn.RAWNAME] = attr.value.idup;
			else if (attr.localName == "score")
				player[PlayerColumn.SCORE] = attr.value.idup;
			else if (attr.localName == "ping")
				player[PlayerColumn.PING] = attr.value.idup;
		}

		servers[$-1].players ~= player;
	}

}
