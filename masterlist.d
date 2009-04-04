module masterlist;

import tango.io.device.File;
import Path = tango.io.Path;
import tango.text.Ascii;
import tango.text.Util;
import tango.text.xml.DocPrinter;
import tango.text.xml.Document;
import tango.text.xml.SaxParser;
debug import tango.util.log.Trace;

debug import common;
import serverdata;


///
alias size_t ServerHandle;

///
const ServerHandle InvalidServerHandle = ServerHandle.max;


///
final class MasterList
{
	///
	this(char[] name)
	{
		name_ = name;
		fileName_ = replace(name_ ~ ".xml", ':', '_');
	}


	/// The URL of the master server.
	char[] name() { return name_; }


	/// The name of the file this master server's data is stored in.
	char[] fileName() { return fileName_; }


	/// Add a server, and return its ServerHandle.
	ServerHandle addServer(ServerData sd)
	{
		synchronized (this) {
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
			debug assert(isValidIpAddress(sd.server[ServerColumn.ADDRESS]));
			ServerHandle sh = findServer(sd.server[ServerColumn.ADDRESS]);

			if (sh != InvalidServerHandle) {
				// country code is calculated locally, so we keep it
				ServerData old = getServerData(sh);
				sd.server[ServerColumn.COUNTRY] =
				                     servers_[sh].server[ServerColumn.COUNTRY];
				setServerData(sh, sd);
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
				if (sd.server[ServerColumn.ADDRESS] == address)
					return sh;
			}
			return InvalidServerHandle;
		}
	}


	/// Will assert if sh is invalid.
	ServerData getServerData(ServerHandle sh)
	{
		synchronized (this) {
			assert (sh < servers_.length);
			return servers_[sh];
		}
	}


	/// Will assert if sh is invalid.
	void setServerData(ServerHandle sh, ServerData sd)
	{
		synchronized (this) {
			assert (sh < servers_.length);
			servers_[sh] = sd;
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
	 * Get a filtered selection of servers.
	 */
	void filter(bool delegate(in ServerData*) test,
	                                          void delegate(ServerHandle) emit)
	{
		synchronized (this) {
			foreach (i, ref sd; servers_) {
				if (test(&sd))
					emit(i);
			}
		}
	}


	/**
	 * Load the server list from file.
	 *
	 * Returns: false if the file didn't exist, true if the contents were
	 *          successfully read.
	 *
	 * Throws: IOException if an error occurred during reading.
	 *
	 * Note: After calling this, all ServerHandles that were obtained before
	 *       calling it should be be considered invalid.
	 */
	bool load()
	{
		debug Trace.formatln("load() called");
		if (!Path.exists(fileName_))
			return false;


		char[] content = cast(char[])File.get(fileName_);
		auto parser = new SaxParser!(char);
		auto handler = new MySaxHandler!(char);

		parser.setSaxHandler(handler);
		parser.setContent(content);
		parser.parse;

		debug {
			Trace.formatln("Found {} servers.", handler.servers.length);
			Trace.formatln("==============================");
		}

		synchronized (this) {
			delete servers_;
			servers_ = handler.servers;
		}

		return true;
	}


	/// Save all data.
	void save()
	{
		scope doc = new Document!(char);
		doc.header;

		synchronized (this) {
			doc.tree.element(null, "masterserver");

			foreach (sd; servers_)
				serverToXml(doc.elements, &sd);
		}

		scope printer = new DocPrinter!(char);
		scope f = new File(fileName_, File.WriteCreate);

		void printDg(char[][] str...)
		{
			foreach (s; str)
				f.write(s);
		}

		printer(doc.tree, &printDg);
		f.write("\r\n");
		f.flush.close;
	}


	private static void serverToXml(Document!(char).Node node,
	                                                         in ServerData* sd)
	{
		auto server = node.element(null, "server")
		     .attribute(null, "name", sd.rawName)
		     .attribute(null, "country_code", sd.server[ServerColumn.COUNTRY])
		     .attribute(null, "address", sd.server[ServerColumn.ADDRESS])
		     .attribute(null, "ping", sd.server[ServerColumn.PING])
		     .attribute(null, "player_count", sd.server[ServerColumn.PLAYERS])
		     .attribute(null, "map", sd.server[ServerColumn.MAP]);

		auto cvars = server.element(null, "cvars");
		cvarsToXml(cvars, sd);
		auto players = server.element(null, "players");
		playersToXml(players, sd);
	}


	private static void cvarsToXml(Document!(char).Node node,
	                                                         in ServerData* sd)
	{
		foreach (cvar; sd.cvars) {
			node.element(null, "cvar")
			    .attribute(null, "key", cvar[0])
			    .attribute(null, "value", cvar[1]);
		}
	}


	private static void playersToXml(Document!(char).Node node,
	                                                         in ServerData* sd)
	{
		foreach (player; sd.players) {
			node.element(null, "player")
			    .attribute(null, "name", player[PlayerColumn.RAWNAME])
			    .attribute(null, "score", player[PlayerColumn.SCORE])
			    .attribute(null, "ping", player[PlayerColumn.PING]);
		}
	}


	invariant()
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
	}


	private {
		char[] name_;
		char[] fileName_;
		ServerData[] servers_;
	}
}


private class MySaxHandler(Ch=char) : SaxHandler!(Ch)
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
			if (attr.localName == "name")
				sd.rawName = attr.value;
			else if (attr.localName == "country_code")
				sd.server[ServerColumn.COUNTRY] = attr.value;
			else if (attr.localName == "address")
				sd.server[ServerColumn.ADDRESS] = attr.value;
			else if (attr.localName == "ping")
				sd.server[ServerColumn.PING] = attr.value;
			else if (attr.localName == "player_count")
				sd.server[ServerColumn.PLAYERS] = attr.value;
			/*else if (attr.localName == "gametype")
				sd.server[ServerColumn.GAMETYPE] = attr.value;*/
			else if (attr.localName == "map")
				sd.server[ServerColumn.MAP] = attr.value;
		}

		servers ~= sd;
	}


	// Add a cvar.
	private void addCvar(Attribute!(Ch)[] attributes)
	{
		char[][] cvar = new char[][2];

		foreach (ref attr; attributes) {
			if (attr.localName == "key")
				cvar[0] = attr.value;
			else if (attr.localName == "value")
				cvar[1] = attr.value;

			if (icompare(cvar[0], "g_gametype") == 0)
				servers[$-1].server[ServerColumn.GAMETYPE] = cvar[1];
			else if (icompare(cvar[0], "g_needpass") == 0)
				servers[$-1].server[ServerColumn.PASSWORDED] = cvar[1];
		}

		servers[$-1].cvars ~= cvar;
	}


	// Add a player.
	private void addPlayer(Attribute!(Ch)[] attributes)
	{
		char[][] player = new char[][PlayerColumn.max + 1];

		foreach (ref attr; attributes) {
			if (attr.localName == "name")
				player[PlayerColumn.RAWNAME] = attr.value;
			else if (attr.localName == "score")
				player[PlayerColumn.SCORE] = attr.value;
			else if (attr.localName == "ping")
				player[PlayerColumn.PING] = attr.value;
		}

		servers[$-1].players ~= player;
	}

}
