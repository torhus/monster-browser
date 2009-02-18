module masterlist;

import tango.io.File;
import tango.io.FileConduit;
debug import tango.io.Stdout;
import tango.text.Ascii;
import tango.text.Util;
import tango.text.xml.DocPrinter;
import tango.text.xml.Document;
import tango.text.xml.SaxParser;

import serverlist;


///
alias size_t ServerHandle;


///
class MasterList
{
	///
	this(char[] name)
	{
		name_ = name;
	}


	///
	void addServer(ServerData* sd)
	{

	}


	/**
	 * Get a filtered selection of servers.
	 *
	 * FIXME: need to synchronize?
	 */
	void filter(bool delegate(in ServerData*) test,
	                                          void delegate(ServerHandle) emit)
	{
		foreach (i, ref sd; servers_) {
			if (test(&sd))
				emit(i);
		}
	}


	///
	void load()
	{
		auto parser = new SaxParser!(char);
		auto handler = new MySaxHandler!(char);
		char[] fname = replace(name_ ~ ".xml", ':', '_');
		auto content = cast(char[])File(fname).read();

		parser.setSaxHandler(handler);
		parser.setContent(content);
		parser.parse;
		delete content;

		Stdout.formatln("Found {} servers.", handler.servers.length);
		Stdout.formatln("==============================");

		/*foreach (sd; handler.servers)
			print(&sd);*/

		delete servers_;
		servers_ = handler.servers;
	}


	///
	void save()
	{
		auto doc = new Document!(char);
		doc.header;
		doc.root.element(null, "masterserver");

		// FIXME: call serverToXml() here

		scope printer = new DocPrinter!(char);
		char[] fname = replace(name_ ~ ".xml", ':', '_');
		scope f = new FileConduit(fname, FileConduit.WriteCreate);

		void printDg(char[][] str...)
		{
			foreach (s; str)
				f.write(s);
		}

		printer(doc.root, &printDg);
		f.write("\r\n");
		f.flush.close;
	}


	private static void serverToXml(Document!(char).Node node,
	                                                         in ServerData* sd)
	{
		node.element(null, "server")
		        .attribute(null, "name", sd.server[ServerColumn.NAME])
		        .attribute(null, "address", sd.server[ServerColumn.ADDRESS])
		        .attribute(null, "ping", sd.server[ServerColumn.PING])
		        .attribute(null, "gametype", sd.server[ServerColumn.GAMETYPE])
		        .attribute(null, "map", sd.server[ServerColumn.MAP]);

		node.lastChild.element(null, "cvars");
		cvarsToXml(node.lastChild.lastChild, sd);
		node.lastChild.element(null, "players");
		playersToXml(node.lastChild.lastChild, sd);
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


	private {
		char[] name_;
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


	// Allocate a new server and add server attributes.
	private void startServer(Attribute!(Ch)[] attributes)
	{
		ServerData sd;

		sd.server.length = ServerColumn.max + 1;

		foreach (ref attr; attributes) {
			if (icompare(attr.localName, "name") == 0)
				sd.rawName = attr.value;
			else if (icompare(attr.localName, "address") == 0)
				sd.server[ServerColumn.ADDRESS] = attr.value;
			else if (icompare(attr.localName, "ping") == 0)
				sd.server[ServerColumn.PING] = attr.value;
			else if (icompare(attr.localName, "gametype") == 0)
				sd.server[ServerColumn.GAMETYPE] = attr.value;
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


debug private void print(in ServerData* sd)
{
	Stdout.formatln("rawName: {}", sd.rawName);
	Stdout.formatln("server ping: {}", sd.server[ServerColumn.PING]);
	Stdout.formatln("server gametype: {}", sd.server[ServerColumn.GAMETYPE]);
	Stdout.formatln("server map: {}", sd.server[ServerColumn.MAP]);
	Stdout.formatln("server address: {}", sd.server[ServerColumn.ADDRESS]);
	foreach (cvar; sd.cvars)
		Stdout.formatln("cvar {}: {}", cvar[0], cvar[1]);
	foreach (player; sd.players)
		Stdout.formatln("player {}: score: {} ping: {}", player[3], player[1], player[2]);

	Stdout("=============================").newline;
}
