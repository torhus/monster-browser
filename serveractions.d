/**
 * Implements the main functionality of the program.  Querying servers, etc.
 */

module serveractions;

import tango.core.Memory;
import Path = tango.io.Path;
import tango.io.Stdout;
import tango.io.stream.TextFileStream;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;
import tango.text.stream.LineIterator;

import dwt.dwthelper.Runnable;
import dwt.widgets.Display;

import common;
import masterlist;
import mainwindow;
import messageboxes;
import qstat;
import runtools;
import serverdata;
import serverlist;
import serverqueue;
import servertable;
import set;
import settings;
import threadmanager;


/// Master server lists indexed by server domain name and port number.
MasterList[char[]] masterLists;

/// ServerList cache indexed by mod name.
// FIXME: needs to be index by mod + game name instead.
ServerList[char[]] serverListCache;


/**
 * Switches the active game.
 *
 * Takes care of everything, updating the GUI as necessary, querying servers or
 * a master server if there's no pre-existing data for the game, etc.  Most of
 * the work is done in a new thread.
 */
void switchToGame(in char[] name)
{
	static char[] gameName;

	static void delegate() f() {
		MasterList master;
		ServerList serverList;
		bool needRefresh;

		if (ServerList* list = gameName in serverListCache) {
			serverList = *list;
			needRefresh = !serverList.complete;
		}
		else {
			char[] masterName = getGameConfig(gameName).masterServer;

			if (auto m = masterName in masterLists) {
				master = *m;
			}
			else {
				master = new MasterList(masterName);
				masterLists[masterName] = master;
			}

			serverList = new ServerList(gameName, master);
			serverListCache[gameName] = serverList;
			needRefresh = true;

			auto file = getGameConfig(gameName).extraServersFile;
			try {
				if (Path.exists(file)) {
					auto input = new TextFileInput(file);
					auto servers = collectIpAddresses(input);
					input.close;
					foreach (s; servers)
						serverList.addExtraServer(s);
				}
			}
			catch (IOException e) {
				log("Error when reading \"" ~ file ~ "\".");
			}
		}

		serverTable.setServerList(serverList);

		if (needRefresh) {
			GameConfig game = getGameConfig(gameName);
			if (arguments.fromfile && Path.exists(master.fileName))
				threadManager.runSecond(&loadSavedList);
			else if (common.haveGslist && game.useGslist)
				threadManager.runSecond(&getNewList);
			else if (master.length > 0 || master.load())
				threadManager.runSecond(&refreshList);
			else
				threadManager.runSecond(&getNewList);
		}
		else {
			serverTable.serverList.sort();
			serverTable.forgetSelection();
			serverTable.fullRefresh();
			statusBar.setDefaultStatus(serverList.length,
			                                        serverList.filteredLength);
		}

		return null;
	}

	gameName = name;
	threadManager.run(&f);
}


/** Loads the list from disk.  To be called through ThreadManager.run(). */
void delegate() loadSavedList()
{
	ServerList serverList = serverTable.serverList;
	MasterList master = serverList.master;

	serverTable.clear();
	serverList.clear();
	GC.collect();

	GameConfig game = getGameConfig(serverList.gameName);
	//if (Path.exists(master.fileName)) {
		auto retriever = new MasterListServerRetriever(game, master);
		auto contr = new ServerRetrievalController(retriever);
		contr.startMessage = "Loading saved server list...";
		contr.noReplyMessage = "No servers were found in the file";
		return &contr.run;
	/*}
	else {
		statusBar.setLeft(
		                "Unable to find a file for this game's master server");
		return null;
	}*/
}


/**
 * Queries one or more servers, adds them to the active server list, and
 * refreshes the serverTable to make them show up.
 *
 * If replace is true, it will instead update servers with new data.
 *
 * The function does not verify that the address is valid.
 *
 * Params:
 *     addresses = IP address and port of servers to query.
 *     replace = Update the servers instead of adding new ones.
 *     select  = Select the newly added or refreshed servers.
 *
 */
void queryServers(in char[][] addresses, bool replace=false, bool select=false)
{
	static char[][] addresses_;
	static bool replace_, select_;

	static void delegate() f() {
		char[] gameName = serverTable.serverList.gameName;
		MasterList master = serverTable.serverList.master;

		auto retriever = new QstatServerRetriever(gameName, master,
		                                   Set!(char[])(addresses_), replace_);
		auto contr = new ServerRetrievalController(retriever, replace_);
		if (select_)
			contr.autoSelect = addresses_;

		return &contr.run;
	}

	if (!addresses.length)
		return;

	addresses_ = addresses;
	replace_ = replace;
	select_ = select;

	threadManager.run(&f);
}


/**
 * Refreshes the list.
 *
 * Note: To be called through ThreadManager.run().
 */
void delegate() refreshList()
{
	ServerList serverList = serverTable.serverList;
	MasterList master = serverList.master;
	GameConfig game = getGameConfig(serverList.gameName);

	if (master.length == 0 && !master.load()) {
		error("No server list found on disk, press\n"
                                   "\'Get new list\' to download a new list.");
		return null;
	}

	Set!(char[]) servers;

	bool test(in ServerData* sd) { return matchMod(sd, game.mod); }

	void emit(ServerHandle sh)
	{
		servers.add(master.getServerData(sh).server[ServerColumn.ADDRESS]);
	}

	master.filter(&test, &emit);

	log("Refreshing server list for " ~ game.name ~ "...");
	log(Format("Found {} servers, master is {}.", servers.length,
	                                                             master.name));

	// merge in the extra servers
	Set!(char[]) extraServers = serverList.extraServers;
	auto oldLength = servers.length;
	foreach (server; extraServers)
		servers.add(server);

	auto delta = servers.length - oldLength;
	log(Format("Added {} extra servers, skipping {} duplicates.",
	                                        delta, extraServers.length-delta));

	serverTable.clear();
	serverList.clear();
	GC.collect();

	if (servers.length) {
		auto retriever = new QstatServerRetriever(game.name, master, servers,
		                                                                 true);
		auto contr = new ServerRetrievalController(retriever);
		contr.startMessage =
                            Format("Refreshing {} servers...", servers.length);
		contr.noReplyMessage = "None of the servers replied";
		return &contr.run;
	}
	else {
		statusBar.setLeft("No servers were found for this game");
		return null;
	}
}


/**
 * Retrieves a new list from the master server.
 *
 * Note: To be called through ThreadManager.run().
 */
void delegate() getNewList()
{
	void f()
	{
		try {
			ServerList serverList = serverTable.serverList;
			GameConfig game = getGameConfig(serverList.gameName);
			auto addresses = browserGetNewList(game);
			log(Format("Got {} servers from {}.", addresses.length,
			                                               game.masterServer));

			auto extraServers = serverList.extraServers;
			foreach (s; extraServers)
					addresses.add(s);
			log(Format("Added {} extra servers.", extraServers.length));

			if (addresses.length == 0) {
				// FIXME: what to do when there are no servers?
				Display.getDefault.asyncExec(new class Runnable {
					void run()
					{
						serverTable.fullRefresh;
						serverTable.notifyRefreshEnded;
					}
				});
			}
			else {
				MasterList master = serverTable.serverList.master;
				
				auto retriever = new QstatServerRetriever(game.name, master,
				                                                    addresses);
				auto contr = new ServerRetrievalController(retriever);
				contr.startMessage = Format("Got {} servers, querying...",
				                                             addresses.length);
				contr.noReplyMessage = "None of the servers replied";
				contr.run();
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}

	}

	serverTable.clear();
	serverTable.serverList.clear();
	// FIXME: update master list instead of clearing it
	//serverTable.serverList.master.clear();
	GC.collect();

	statusBar.setLeft("Getting new server list...");
	char[] gameName = serverTable.serverList.gameName;
	log("Getting new server list for " ~ gameName ~ "...");
	serverTable.notifyRefreshStarted;

	return &f;
}


/**
 * This class controls most of the process of querying a list of game servers.
 *
 * Objects of this class takes care of all GUI updates necessary while
 * querying servers.
 *
 * The process is mostly configured through the IServerRetriever object given
 * to the constructor.  This object does the actual querying, parsing, saving
 * of server lists to disk, etc.
 */
class ServerRetrievalController
{
	/**
	 * Status bar messages.
	 *
	 * Set before calling run() if you don't want the defaults to be used.
	 */
	char[] startMessage = "Querying server(s)...";
	char[] noReplyMessage = "There was no reply";  /// ditto


	/**
	 * Set selection to these servers when retrieval is finished.
	 *
	 * If null or empty, the previous selection will be retained.
	 *
	 * Note: Set before calling run().
	 */
	char[][] autoSelect = null;


	/**
	 * Params:
	 *     replace = Pass the received servers to ServerList.replace instead of
	 *               the default ServerList.add.
	 *     store   = Add or update this server in the MasterList object
	 *               associated with this game/mod.
	 */
	this(IServerRetriever retriever, bool replace=false, bool store=true)
	{
		serverRetriever_= retriever;
		replace_ = replace;
		store_ = store;

		serverRetriever_.initialize();

		serverList_ = serverTable.serverList;

		Display.getDefault.syncExec(new class Runnable {
			void run() { serverTable.notifyRefreshStarted(&stop); }
		});
	}


	~this()
	{
		if (statusBarUpdater_)
			delete statusBarUpdater_;

	}


	/**
	 * Call this to start the process.
	 *
	 * Note: primarily to be called in a secondary thread, not tested when
	 *       running in the GUI thread.
	 */
	void run()
	{
		try {
			statusBarUpdater_ = new StatusBarUpdater;
			statusBarUpdater_.text = startMessage;
			Display.getDefault.syncExec(statusBarUpdater_);

			serverCount_ = serverRetriever_.prepare();

			if (serverCount_ != 0) {
				auto serverList = serverTable.serverList;
				auto dg = replace_ ? &serverList.replace : &serverList.add;

				serverQueue_ = new ServerQueue(dg);
				deliverDg_ = &serverQueue_.add;

				serverRetriever_.retrieve(&deliver);
				serverList.complete = !threadManager.abort;

				// a benchmarking tool
				if (arguments.quit) {
					Display.getDefault.syncExec(new class Runnable {
						void run()
						{
							Stdout.formatln("Time since startup: {} seconds.",
							                              globalTimer.seconds);
							mainWindow.close;
						}
					});
				}
				serverQueue_.stop(addRemaining_);
			}

			Display.getDefault.asyncExec(new class Runnable {
				void run()
				{
					if (!threadManager.abort || wasStopped_)
						done;
					else
						serverTable.notifyRefreshEnded;
				}
			});
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
	}


	/**
	 * Stops the whole process.
	 *
	 * If addRemaining is true, any servers already received will be added to
	 * to the server list.
	 */
	void stop(bool addRemaining)
	{
		threadManager.abort = true;
		wasStopped_ = true;
		addRemaining_ = addRemaining;
	}


	private bool deliver(ServerHandle sh, bool replied, bool matched)
	{
		assert(sh != InvalidServerHandle);
		
		if (replied) {
			if (matched)
				deliverDg_(sh);
		}
		else {
			timedOut_++;
		}

		statusBarUpdater_.text = startMessage ~ Integer.toString(counter_++);
		Display.getDefault.syncExec(statusBarUpdater_);		

		return !threadManager.abort;
	}


	private void done()
	{
		ServerList list = serverTable.serverList;

		if (list.length > 0) {
			int index = -1;
			if (autoSelect.length) {
				// FIXME: select them all, not just the first one
				index = list.getFilteredIndex(autoSelect[0]);
			}

			if (store_)
				serverList_.master.save();

			serverTable.fullRefresh(index);
			statusBar.setDefaultStatus(list.length, list.filteredLength,
			                                                        timedOut_);
		}
		else {
			statusBar.setLeft(noReplyMessage);
		}
		serverTable.notifyRefreshEnded;
	}


	private {
		IServerRetriever serverRetriever_;
		int serverCount_;
		int counter_ = 0;
		uint timedOut_ = 0;
		StatusBarUpdater statusBarUpdater_;
		bool replace_;
		bool store_;
		void delegate(ServerHandle) deliverDg_;
		bool wasStopped_ = false;
		bool addRemaining_ = true;
		ServerList serverList_;
		ServerQueue serverQueue_;
	}
}


private class StatusBarUpdater : Runnable {
	char[] text;

	this(char[] text=null) { this.text = text; }

	void run() { statusBar.setLeft(text); }
}
