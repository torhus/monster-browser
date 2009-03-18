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


	///
	char[] name() { return name_; }


	///
	char[] fileName() { return fileName_; }


	///
	ServerHandle addServer(ServerData sd)
	{
		synchronized (this) {
			servers_ ~= sd;
			return servers_.length - 1;
		}
	}


	///
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


	///
	ServerData getServerData(ServerHandle sh)
	{
		synchronized (this) {
			assert (sh < servers_.length);
			return servers_[sh];
		}
	}


	///
	void setServerData(ServerHandle sh, ServerData sd)
	{
		synchronized (this) servers_[sh] = sd;
	}


	/// Total number of servers.
	size_t length() { return servers_.length; }


	///
	//void clear() { delete servers_; }


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


	///
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
		node.element(null, "server")
		     .attribute(null, "name", sd.server[ServerColumn.NAME])
		     .attribute(null, "country_code", sd.server[ServerColumn.COUNTRY])
		     .attribute(null, "address", sd.server[ServerColumn.ADDRESS])
		     .attribute(null, "ping", sd.server[ServerColumn.PING])
		   //.attribute(null, "passworded", sd.server[ServerColumn.PASSWORDED])
		     .attribute(null, "player_count", sd.server[ServerColumn.PLAYERS])
		   //.attribute(null, "gametype", sd.server[ServerColumn.GAMETYPE])
		     .attribute(null, "map", sd.server[ServerColumn.MAP]);

		node.childTail.element(null, "cvars");
		cvarsToXml(node.childTail.childTail, sd);
		node.childTail.element(null, "players");
		playersToXml(node.childTail.childTail, sd);
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
		static int counter = 0;

		synchronized (this) {
			//Trace.formatln("INVARIANT counter = {} ({}): {}", ++counter, name_, servers_.length);
			foreach (i, sd; servers_) {
				//assert (isValidIpAddress(sd.server[ServerColumn.ADDRESS]));
				/*if (!isValidIpAddress(sd.server[ServerColumn.ADDRESS]))
					//int x = 1;
					Trace.formatln("Address: ({}) {}", i, sd.server[ServerColumn.ADDRESS]);*/
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
		if (icompare(localName, "cvar") == 0)
			addCvar(attributes);
		else if (icompare(localName, "player") == 0)
			addPlayer(attributes);
		else if (icompare(localName, "server") == 0)
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
			if (icompare(attr.localName, "name") == 0)
				sd.rawName = attr.value;
			else if (icompare(attr.localName, "country_code") == 0)
				sd.server[ServerColumn.COUNTRY] = attr.value;
			else if (icompare(attr.localName, "address") == 0)
				sd.server[ServerColumn.ADDRESS] = attr.value;
			else if (icompare(attr.localName, "ping") == 0)
				sd.server[ServerColumn.PING] = attr.value;
			else if (icompare(attr.localName, "player_count") == 0)
				sd.server[ServerColumn.PLAYERS] = attr.value;
			/*else if (icompare(attr.localName, "gametype") == 0)
				sd.server[ServerColumn.GAMETYPE] = attr.value;*/
			else if (icompare(attr.localName, "map") == 0)
				sd.server[ServerColumn.MAP] = attr.value;
		}

		servers ~= sd;
	}


	// Add a cvar.
	private void addCvar(Attribute!(Ch)[] attributes)
	{
		char[][] cvar = new char[][2];

		foreach (ref attr; attributes) {
			if (icompare(attr.localName, "key") == 0)
				cvar[0] = attr.value;
			else if (icompare(attr.localName, "value") == 0)
				cvar[1] = attr.value;

			if (cvar[0] == "g_gametype")
				servers[$-1].server[ServerColumn.GAMETYPE] = cvar[1];
			else if (cvar[0] == "g_needpass")
				servers[$-1].server[ServerColumn.PASSWORDED] = cvar[1];
		}

		servers[$-1].cvars ~= cvar;
	}


	// Add a player.
	private void addPlayer(Attribute!(Ch)[] attributes)
	{
		char[][] player = new char[][PlayerColumn.max + 1];

		foreach (ref attr; attributes) {
			if (icompare(attr.localName, "name") == 0)
				player[PlayerColumn.RAWNAME] = attr.value;
			else if (icompare(attr.localName, "score") == 0)
				player[PlayerColumn.SCORE] = attr.value;
			else if (icompare(attr.localName, "ping") == 0)
				player[PlayerColumn.PING] = attr.value;
		}

		servers[$-1].players ~= player;
	}

}
