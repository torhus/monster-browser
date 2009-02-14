module masterlist;

import tango.io.FileConduit;
debug import tango.io.Stdout;
import tango.text.Util;
import tango.text.xml.DocPrinter;
import tango.text.xml.Document;

import serverlist;


///
class MasterList
{
	///
	this(char[] name)
	{
		name_ = name;
		doc_ = new Document!(char);
		doc_.header;
		doc_.root.element(null, "masterserver");
		root_ = doc_.root.lastChild;
	}


	///
	void addServer(ServerData* sd)
	{
		root_.element(null, "server")
		        .attribute(null, "name", sd.server[ServerColumn.NAME])
		        .attribute(null, "address", sd.server[ServerColumn.ADDRESS])
		        .attribute(null, "ping", sd.server[ServerColumn.PING])
		        .attribute(null, "gametype", sd.server[ServerColumn.GAMETYPE])
		        .attribute(null, "map", sd.server[ServerColumn.MAP]);

		root_.lastChild.element(null, "cvars");
		cvarsToXml(root_.lastChild.lastChild, sd);
		root_.lastChild.element(null, "players");
		playersToXml(root_.lastChild.lastChild, sd);
	}


	///
	void save()
	{
		scope printer = new DocPrinter!(char);
		char[] fname = replace(name_ ~ ".xml", ':', '_');
		scope f = new FileConduit(fname, FileConduit.WriteCreate);

		void printDg(char[][] str...)
		{
			foreach (s; str)
				f.write(s);
		}

		printer(doc_.root, &printDg);
		f.write("\r\n");
		f.flush.close;
	
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
		Document!(char) doc_;
		Document!(char).Node root_;
	}
}
