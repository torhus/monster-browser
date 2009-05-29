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
	this(char[] address)
	{
		assert(address.length > 0);
		address_ = address;
		fileName_ = replace(address ~ ".xml", ':', '_');
	}


	/**
	 * The host name or IP address, plus optionally a port number for the
	 * master server.
	 */
	char[] address() { return address_; }


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
			return servers_.length - 1;
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
			char[] address = sd.server[ServerColumn.ADDRESS];
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
					old.setPlayerColumn(0, 0, old.maxClients);
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
	 */
	private ServerHandle findServer(in char[] address)
	{
		synchronized (this) {
			foreach (sh, sd; servers_) {
				if (sd.server.length > 0 &&
				                    sd.server[ServerColumn.ADDRESS] == address)
					return sh;
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
	 * Clear the server list.
	 *
	 * Calling this invalidates all ServerHandles.
	 **/
	void clear() { delete servers_; }


	/**
	* Foreach support.  Skips servers for which isEmpty(sd) returns true.
	*/
	synchronized int opApply(int delegate(ref ServerHandle) dg)
	{
		int result = 0;

		foreach (sh, sd; servers_) {
			if (isEmpty(&sd))
				continue;
			result = dg(sh);
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
	 * Throws: IOException if an error occurred during reading.
	 *         XmlException for XML syntax errors.
	 *
	 * Note: After calling this, all ServerHandles that were obtained before
	 *       calling it should be be considered invalid.
	 */
	bool load()
	{
		if (!Path.exists(appDir ~ fileName_))
			return false;

		log(Format("Opening '{}'...", fileName_));

		scope timer = new Timer;
		char[] content = cast(char[])File.get(appDir ~ fileName_);
		GC.setAttr(content.ptr, GC.BlkAttr.NO_SCAN);
		auto parser = new SaxParser!(char);
		auto handler = new MySaxHandler!(char);

		parser.setSaxHandler(handler);
		parser.setContent(content);
		parser.parse;
		delete content;

		log(Format("Loaded {} servers in {} seconds.", handler.servers.length,
		                                                       timer.seconds));

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
		scope timer = new Timer;
		scope dumper = new XmlDumper(appDir ~ fileName_);

		synchronized (this) {
			foreach (sd; servers_) {
				if (!isEmpty(&sd))
					dumper.serverToXml(&sd);
			}
		}

		dumper.close();
		log(Format("Saved {} in {} seconds.", fileName_, timer.seconds));
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
					Trace.formatln("Address: ({}) {}", i, address);
					assert(0, "MasterList: invalid address");
				}
			}
		}
	}*/


	private {
		char[] address_;
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
		output_.format(`  <server name="{}"`, sd.rawName)
		       .format(` country_code="{}"`,  sd.server[ServerColumn.COUNTRY])
		       .format(` address="{}"`,       sd.server[ServerColumn.ADDRESS])
		       .format(` ping="{}"`,          sd.server[ServerColumn.PING])
		       .format(` player_count="{}"`,  sd.server[ServerColumn.PLAYERS])
		       .format(` map="{}"`,           sd.server[ServerColumn.MAP])
		       .format(` fail_count="{}"`,    sd.failCount)
			   .formatln(">");

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
		foreach (cvar; sd.cvars)
			output_.format(`      <cvar key="{}" value="{}"/>`,
			                                         cvar[0], cvar[1]).newline;
	}


	private void playersToXml(in ServerData* sd)
	{
		foreach (player; sd.players) {
			output_.format(`      <player name="{}" score="{}" ping="{}"/>`,
                                               player[PlayerColumn.RAWNAME],
											   player[PlayerColumn.SCORE],
											   player[PlayerColumn.PING]);
			output_.newline;
		}
	}


	private {
		FormatOutput!(char) output_;
	}
}


private final class MySaxHandler(Ch=char) : SaxHandler!(Ch)
{
	ServerData[] servers;


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
				sd.rawName = attr.value.dup;
				sd.server[ServerColumn.NAME] = stripColorCodes(attr.value);
			}
			else if (attr.localName == "country_code")
				sd.server[ServerColumn.COUNTRY] = attr.value.dup;
			else if (attr.localName == "address")
				sd.server[ServerColumn.ADDRESS] = attr.value.dup;
			else if (attr.localName == "ping")
				sd.server[ServerColumn.PING] = attr.value.dup;
			else if (attr.localName == "player_count")
				sd.server[ServerColumn.PLAYERS] = attr.value.dup;
			else if (attr.localName == "map")
				sd.server[ServerColumn.MAP] = attr.value.dup;
			else if (attr.localName == "fail_count")
				sd.failCount = Integer.convert(attr.value);
		}

		servers ~= sd;
	}


	// Add a cvar.
	private void addCvar(Attribute!(Ch)[] attributes)
	{
		char[][] cvar = new char[][2];

		foreach (ref attr; attributes) {
			if (attr.localName == "key")
				cvar[0] = attr.value.dup;
			else if (attr.localName == "value")
				cvar[1] = attr.value.dup;

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
				player[PlayerColumn.RAWNAME] = attr.value.dup;
			else if (attr.localName == "score")
				player[PlayerColumn.SCORE] = attr.value.dup;
			else if (attr.localName == "ping")
				player[PlayerColumn.PING] = attr.value.dup;
		}

		servers[$-1].players ~= player;
	}

}
