/**
 * Loading and saving of server lists to disk.
 */

module liststorage;

import tango.io.Stdout;
import tango.text.xml.DocPrinter;
import tango.text.xml.Document;

import serverlist;


///
void saveServerList(in ServerList serverList)
{
	scope doc = new Document!(char);

	doc.header;

	for (int i=0; i < serverList.filteredLength; i++) {
		ServerData* sd = serverList.getFiltered(i);
		doc.root.element(null, "server")
		        .attribute(null, "name", sd.server[ServerColumn.NAME])
		        .attribute(null, "address", sd.server[ServerColumn.ADDRESS])
		        .attribute(null, "ping", sd.server[ServerColumn.PING])
		        .attribute(null, "gametype", sd.server[ServerColumn.GAMETYPE])
		        .attribute(null, "map", sd.server[ServerColumn.MAP]);

		doc.root.lastChild.element(null, "cvars");
		cvarsToXml(doc.root.lastChild.lastChild, sd);
		doc.root.lastChild.element(null, "players");
		playersToXml(doc.root.lastChild.lastChild, sd);
	}

	auto print = new DocPrinter!(char);
	Stdout(print(doc)).newline;
}


private void cvarsToXml(Document!(char).Node node, in ServerData* sd)
{
	foreach (cvar; sd.cvars) {
		node.element(null, "cvar")
		    .attribute(null, "key", cvar[0])
		    .attribute(null, "value", cvar[1]);
	}
}


private void playersToXml(Document!(char).Node node, in ServerData* sd)
{
	foreach (player; sd.players) {
		node.element(null, "player")
		    .attribute(null, "name", player[PlayerColumn.RAWNAME])
		    .attribute(null, "score", player[PlayerColumn.SCORE])
		    .attribute(null, "ping", player[PlayerColumn.PING]);
	}
}
