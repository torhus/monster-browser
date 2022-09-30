module masterlist;

import core.memory;
import std.array;
import std.conv;
import std.file;
import std.path;
import std.stdio;
import std.uni;

import dxml.parser;
import dxml.util;
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

		synchronized (this) {
			servers_.clear;
			downCount_ = 0;
			parse(content, defaultProtocolVersion);
			log("Loaded %s servers in %s seconds.", servers_.length,
			                                                    timer.seconds);
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

	private void parse(in char[] content, string defaultProtocolVersion)
	{
		ServerData sd;

		void addCvar(R)(R attributes) if (isAttrRange!R)
		{
			string[] cvar = new string[2];

			foreach (attr; attributes) {
				if (attr.name == "key")
					cvar[0] = decodeXML(attr.value);
				else if (attr.name == "value")
					cvar[1] = decodeXML(attr.value);
			}

			sd.cvars ~= cvar;
		}

		void addPlayer(R)(R attributes) if (isAttrRange!R)
		{
			string[] player = new string[PlayerColumn.max + 1];

			foreach (attr; attributes) {
				if (attr.name == "name")
					player[PlayerColumn.RAWNAME] = decodeXML(attr.value);
				else if (attr.name == "score")
					player[PlayerColumn.SCORE] = decodeXML(attr.value);
				else if (attr.name == "ping")
					player[PlayerColumn.PING] = decodeXML(attr.value);
			}

			sd.players ~= player;
		}

		void startServer(R)(R attributes) if (isAttrRange!R)
		{
			sd.server.length = ServerColumn.max + 1;

			foreach (attr; attributes) {
				switch (attr.name) {
					case "name":
						sd.rawName = decodeXML(attr.value);
						sd.server[ServerColumn.NAME] =
						              (stripColorCodes(decodeXML(attr.value)));
						break;
					case "country_code":
						sd.server[ServerColumn.COUNTRY] = decodeXML(attr.value);
					break;
					case "address":
						sd.server[ServerColumn.ADDRESS] = decodeXML(attr.value);
						break;
					case "protocol_version":
						sd.protocolVersion = decodeXML(attr.value);
						break;
					case "ping":
						sd.server[ServerColumn.PING] = decodeXML(attr.value);
						break;
					case "player_count":
						sd.server[ServerColumn.PLAYERS] = decodeXML(attr.value);
						break;
					case "map":
						sd.server[ServerColumn.MAP] = decodeXML(attr.value);
						break;
					case "persistent":
						sd.persistent = attr.value == "true";
						break;
					case "fail_count":
						sd.failCount = toIntOrDefault(attr.value);
						break;
					default:
						break;
				}
			}
			// Make sure there's a protocol version.  This makes it less likely the
			// server is being 'forgotten' and never queried or deleted.
			// It also takes care of upgrading from the old XML files, where there
			// were no protocol_version attribute.
			if (sd.protocolVersion.length == 0)
				sd.protocolVersion = defaultProtocolVersion;
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
				downCount_++;

			servers_[sd.server[ServerColumn.ADDRESS]] = sd;
			sd = ServerData.init;
		}

		enum config = makeConfig(SplitEmpty.yes, SkipComments.yes);
		foreach(entity; parseXML!config(content)) {
			if (entity.type == EntityType.elementStart) {
				switch (entity.name) {
					case "cvar":
						addCvar(entity.attributes);
						break;
					case "player":
						addPlayer(entity.attributes);
						break;
					case "server":
						startServer(entity.attributes);
						break;
					default:
						break;
				}
			}
			else if (entity.type == EntityType.elementEnd &&
			                                         entity.name == "server") {
				endServer();
			}
		}
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
