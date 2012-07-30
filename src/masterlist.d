module masterlist;

import tango.core.Memory;
import Path = tango.io.Path;
import tango.io.device.File;
import tango.io.stream.Buffered;
import tango.io.stream.Format;
import tango.text.Ascii;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;
import tango.time.StopWatch;
import tango.text.xml.DocEntity;
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
	this(char[] name)
	{
		assert(name.length > 0);
		name_ = name;
		fileName_ = replace(name ~ ".xml", ':', '_');
	}

	
	/// Name, as given to the constructor.
	char[] name() { return name_; }
	
	
	/// The name of the file this master server's data is stored in.
	char[] fileName() { return fileName_; }


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
	 * The country code and persistency state will be kept.
	 *
	 * Returns: The server's handle if it was found in the list, or
	 *          InvalidServerHandle if not.
	 */
	ServerHandle updateServer(ServerData sd)
	{
		synchronized (this) {
			char[] address = sd.server[ServerColumn.ADDRESS];
			debug isValid(&sd);
			ServerHandle sh = findServer(address);

			if (sh != InvalidServerHandle) {
				ServerData* old = &servers_[sh];

				// some data is be kept between refreshes
				sd.server[ServerColumn.COUNTRY] =
				                              old.server[ServerColumn.COUNTRY];
				sd.persistent = old.persistent;

				if (timedOut(&sd)) {
					old.server[ServerColumn.PING] =
					                              sd.server[ServerColumn.PING];
					old.updateState = sd.updateState;
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

	
	/// Set the updateState field of a ServerData object.
	void setUpdateState(ServerHandle sh, UpdateState updateState)
	{
		synchronized (this) {
			assert(sh < servers_.length);
			servers_[sh].updateState = updateState;
		}
	}


	/// Total number of servers.
	size_t length() { return servers_.length; }


	/**
	* Foreach support.  Skips servers for which isEmpty(sd) returns true.
	*/
	synchronized int opApply(int delegate(ref ServerHandle) dg)
	{
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
	 * Throws: IOException if an error occurred during reading.
	 *         XmlException for XML syntax errors.
	 *
	 * Note: After calling this, all ServerHandles that were obtained before
	 *       calling it should be be considered invalid.
	 */
	bool load(in char[] defaultProtocolVersion)
	{
		if (!Path.exists(dataDir ~ fileName_))
			return false;

		log(Format("Opening '{}'...", fileName_));

		StopWatch timer;
		timer.start();

		char[] content = cast(char[])File.get(dataDir ~ fileName_);
		GC.setAttr(content.ptr, GC.BlkAttr.NO_SCAN);
		auto parser = new SaxParser!(char);
		auto handler = new MySaxHandler!(char)(defaultProtocolVersion);

		parser.setSaxHandler(handler);
		parser.setContent(content);
		parser.parse;
		delete content;

		log(Format("Loaded {} servers in {} seconds.", handler.servers.length,
		                                                        timer.stop()));

		synchronized (this) {
			delete servers_;
			servers_ = handler.servers;
		}

		return true;
	}


	/**
	 * Save all data.
	 *
	 * Throws: IOException.
	 */
	void save()
	{
		StopWatch timer;
		timer.start();

		scope dumper = new XmlDumper(dataDir ~ fileName_);

		synchronized (this) {
			foreach (sd; servers_) {
				if (!isEmpty(&sd))
					dumper.serverToXml(&sd);
			}
		}

		dumper.close();
		log(Format("Saved {} in {} seconds.", fileName_, timer.stop()));
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
		char[] name_;
		char[] fileName_;
		ServerData[] servers_;
	}
}


///
private final class XmlDumper
{

	///
	this(in char[] fileName)
	{
		auto file = new BufferedOutput(new File(fileName, File.WriteCreate));
		output_ = new FormatOutput!(char)(file);
		output_.formatln(`<?xml version="1.0" encoding="UTF-8"?>`);
		output_.formatln("<masterserver>");
	}


	///
	void close()
	{
		output_.formatln("</masterserver>");
		output_.flush().close();
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
		output_.format(` fail_count="{}"`,    sd.failCount);
		output_.formatln(">");

		if (sd.cvars.length) {
			output_.formatln("    <cvars>");
			cvarsToXml(sd);
			output_.formatln("    </cvars>");
		}

		if (sd.players.length) {
			output_.formatln("    <players>");
			playersToXml(sd);
			output_.formatln("    </players>");
		}

		output_.formatln("  </server>");
	}


	private void cvarsToXml(in ServerData* sd)
	{
		foreach (cvar; sd.cvars) {
			outputXml(`      <cvar key=`, cvar[0]);
			outputXml(` value=`, cvar[1]);
			output_.formatln("/>");
		}
	}


	private void playersToXml(in ServerData* sd)
	{
		foreach (player; sd.players) {
			outputXml(`      <player name=`, player[PlayerColumn.RAWNAME]);
			outputXml(` score=`, player[PlayerColumn.SCORE]);
			outputXml(` ping=`, player[PlayerColumn.PING]);
			output_.formatln("/>");
		}
	}


	// Outputs prefix as-is, value in quotes and after encoding entities.
	private void outputXml(in char[] prefix, in char[] value)
	{
		char[100] buf = void;

		output_.stream.write(prefix);
		output_.stream.write("\"");
		output_.stream.write(toEntity(value, buf));
		output_.stream.write("\"");
	}
	

	private {
		FormatOutput!(char) output_;
	}
}


private final class MySaxHandler(Ch=char) : SaxHandler!(Ch)
{
	ServerData[] servers;

	private char[] defaultProtocolVersion_;


	this(in char[] defaultProtocolVersion)
	{
		defaultProtocolVersion_ = defaultProtocolVersion;
	}

	override void startElement(Ch[] uri, Ch[] localName, Ch[] qName,
	                                               Attribute!(Ch)[] attributes)
	{
		if (localName == "cvar")
			addCvar(attributes);
		else if (localName == "player")
			addPlayer(attributes);
		else if (localName == "server")
			startServer(attributes);
	}


	override void endElement(Ch[] uri, Ch[] localName, Ch[] qName)
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
				                       fromEntity(stripColorCodes(attr.value));
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
				sd.failCount = Integer.convert(attr.value);
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
		char[][] cvar = new char[][2];

		foreach (ref attr; attributes) {
			if (attr.localName == "key")
				cvar[0] = fromEntityCopy(attr.value);
			else if (attr.localName == "value")
				cvar[1] = fromEntityCopy(attr.value);

			if (icompare(cvar[0], "g_gametype") == 0)
				servers[$-1].server[ServerColumn.GAMETYPE] = cvar[1];
			else if (icompare(cvar[0], "g_needpass") == 0) {
				char[] s = cvar[1] == "0" ? PASSWORD_NO : PASSWORD_YES;
				servers[$-1].server[ServerColumn.PASSWORDED] = s;
			}
		}

		servers[$-1].cvars ~= cvar;
	}


	// Add a player.
	private void addPlayer(Attribute!(Ch)[] attributes)
	{
		char[][] player = new char[][PlayerColumn.max + 1];

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
	char[] fromEntityCopy(in char[] s)
	{	
		char[] r = fromEntity(s);
		if (r.ptr != s.ptr)
			return r;
		else
			return s.dup;
	}

}
