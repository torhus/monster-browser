/**
 * Implements the main functionality of the program.  Querying servers, etc.
 */

module serveractions;

import tango.core.Exception;
import tango.core.Memory;
import Path = tango.io.Path;
import tango.io.stream.TextFile;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;
import tango.util.log.Trace;

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
 *
 * FIXME: simplify this messy function
 */
void switchToGame(in char[] name)
{
	static char[] gameName;

	static void delegate() f() {
		ServerList serverList;
		bool needRefresh;

		// make sure we have a ServerList object
		if (ServerList* list = gameName in serverListCache) {
			serverList = *list;
			needRefresh = !serverList.complete;
		}
		else {
			char[] masterName = getGameConfig(gameName).masterServer;
			MasterList master;

			// make sure we have a MasterList object
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

			// Add servers from the extra servers file, if found.
			auto file = getGameConfig(gameName).extraServersFile;
			try {
				if (Path.exists(file)) {
					auto input = new TextFileInput(file);
					auto addresses = collectIpAddresses(input);
					input.close;
					foreach (addr; addresses)
						serverList.addExtraServer(addr);
				}
			}
			catch (IOException e) {
				log("Error when reading \"" ~ file ~ "\".");
			}
		}

		serverTable.setServerList(serverList);
		serverTable.clear();

		if (needRefresh) {
			GameConfig game = getGameConfig(gameName);
			if (arguments.fromfile)
				threadManager.runSecond(&loadSavedList);
			else if (common.haveGslist && game.useGslist)
				threadManager.runSecond(&checkForNewServers);
			else {
				// try to refresh if we can, otherwise get a new list
				MasterList master = serverList.master;
				bool canRefresh = master.length > 0;
				if (!canRefresh) {
					try {
						canRefresh = master.load() && master.length > 0;
					}
					catch (IOException e) {
						error("There was an error reading " ~ master.fileName
						                    ~ "\nPress OK to get a new list.");
					}
					catch (XmlException e) {
						error("Syntax error in " ~ master.fileName
						                    ~ "\nPress OK to get a new list.");
					}
				}

				if (canRefresh)
					threadManager.runSecond(&refreshAll);
				else
					threadManager.runSecond(&checkForNewServers);
			}
		}
		else {
			serverTable.serverList.sort();
			serverTable.forgetSelection();
			serverTable.fullRefresh();
			statusBar.setLeft("Ready");
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
	if (Path.exists(dataDir ~ master.fileName)) {
		auto retriever = new MasterListServerRetriever(game, master);
		auto contr = new ServerRetrievalController(retriever);
		contr.disableQueue();
		statusBar.setLeft("Loading saved server list...");
		return &contr.run;
	}
	else {
		statusBar.setLeft(
		                "Unable to find a file for this game's master server");
		return null;
	}
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
		contr.progressLabel = Format("Querying {} servers", addresses_.length);

		if (select_)
			contr.autoSelect = addresses_;

		return &contr.run;
	}

	if (!addresses.length)
		return;

	if (addresses.length > 100)
		GC.collect();

	addresses_ = addresses;
	replace_ = replace;
	select_ = select;

	threadManager.run(&f);
}


/**
 * Refreshes all servers for the current mod.
 *
 * Note: To be called through ThreadManager.run().
 */
void delegate() refreshAll()
{
	ServerList serverList = serverTable.serverList;
	MasterList master = serverList.master;
	GameConfig game = getGameConfig(serverList.gameName);

	assert(master.length > 0);

	static Set!(char[]) addresses, addresses2;

	// reset static variables
	addresses.clear();
	addresses2.clear();

	foreach (sh; master) {
		ServerData sd = master.getServerData(sh);
		bool matched = matchMod(&sd, game.mod);

		if (matched)
			addresses.add(sd.server[ServerColumn.ADDRESS]);
		else if (timedOut(&sd) && sd.failCount < 2)
			// retry previously unresponsive servers
			addresses2.add(sd.server[ServerColumn.ADDRESS]);
	}

	log("Refreshing server list for " ~ game.name ~ "...");
	log(Format("Found {} servers, master is {}.", addresses.length,
	                                                          master.address));

	// merge in the extra servers
	Set!(char[]) extraServers = serverList.extraServers;
	auto oldLength = addresses.length;
	foreach (server; extraServers)
		addresses.add(server);

	auto delta = addresses.length - oldLength;
	log(Format("Added {} extra servers, skipping {} duplicates.",
	                                        delta, extraServers.length-delta));

	serverTable.clear();
	serverList.clear();
	GC.collect();

	void f()
	{
		ServerList serverList = serverTable.serverList;
		MasterList master = serverList.master;
		GameConfig game = getGameConfig(serverList.gameName);

		if (addresses.length) {
			auto retriever = new QstatServerRetriever(game.name, master,
			                                                  addresses, true);
			auto contr = new ServerRetrievalController(retriever);
			contr.progressLabel = Format("Refreshing {} servers",
			                                                 addresses.length);
			contr.run();
		}

		if (addresses2.length) {
			auto retriever = new QstatServerRetriever(game.name, master,
			                                                 addresses2, true);
			auto contr = new ServerRetrievalController(retriever);
			contr.progressLabel =
			              Format("Retrying {} previously unresponsive servers",
			                                                addresses2.length);
			contr.run();
		}
	}

	if (addresses.length || addresses2.length) {
		return &f;
	}
	else {
		statusBar.setLeft("No servers were found for this game");
		return null;
	}
}


/**
 * Checks for new servers for the current mod.
 *
 * Note: To be called through ThreadManager.run().
 */
void delegate() checkForNewServers()
{
	void f()
	{
		try {
			ServerList serverList = serverTable.serverList;
			MasterList master = serverList.master;
			GameConfig game = getGameConfig(serverList.gameName);

			Display.getDefault().syncExec(dgRunnable( {
				statusBar.showProgress("Getting new list from master", true);
			}));

			Set!(char[]) addresses = browserGetNewList(game);

			// Make sure we don't start removing servers based on an incomplete
			// address list.
			if (threadManager.abort) {
				Display.getDefault().syncExec(dgRunnable( {
					statusBar.hideProgress("Interrupted");
				}));
				return;
			}

			size_t total = addresses.length;
			int removed = 0;
			Set!(char[]) addresses2;

			// Exclude servers that are already known to run the right mod, and
			// delete servers from the master list that's missing from the
			// master server.
			foreach (sh; master) {
				ServerData sd = master.getServerData(sh);
				char[] address = sd.server[ServerColumn.ADDRESS];
				if (address in addresses) {
					addresses.remove(address);
					if (!matchMod(&sd, game.mod))
						addresses2.add(address);
				}
				else if (!sd.persistent) {
					setEmpty(&sd);
					master.setServerData(sh, sd);
					removed++;
				}
			}

			log(Format("Got {} servers from {}, including {} new.",
			                      total, game.masterServer, addresses.length));

			if (removed > 0) {
				Display.getDefault().syncExec(dgRunnable( {
					serverList.refillFromMaster();
					serverTable.fullRefresh();
				}));

				log(Format("Removed {} servers that were missing from master.",
				                                                     removed));
			}

			size_t count = addresses.length + addresses2.length;

			if (count == 0) {
				// FIXME: what to do when there are no servers?
				Display.getDefault.asyncExec(dgRunnable( {
					statusBar.hideProgress("There were no new servers");
					serverTable.fullRefresh;
					serverTable.notifyRefreshEnded;
				}));
			}
			else {
				// if it's only a few servers, do it all in one go
				if (count < 100 || addresses.length == 0) {
					foreach (addr; addresses2)
						addresses.add(addr);
					addresses2.clear();
				}

				auto retriever = new QstatServerRetriever(game.name, master,
				                                              addresses, true);
				auto contr = new ServerRetrievalController(retriever);
				contr.progressLabel = Format("Checking {} servers",
				                                             addresses.length);
				contr.run();

				if (addresses2.length) {
					retriever = new QstatServerRetriever(game.name,
					                                 master, addresses2, true);
					contr = new ServerRetrievalController(retriever);
					contr.progressLabel = Format("Extended check, {} servers",
					                                        addresses2.length);
					contr.run();
				}
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}

	}

	ServerList serverList = serverTable.serverList;
	if (serverList.master.length > 0) {
		log("Checking for new servers for " ~ serverList.gameName ~ "...");
	}
	else {
		log("Getting new server list for " ~ serverList.gameName ~ "...");
	}
	serverTable.notifyRefreshStarted((bool) { threadManager.abort = true; });

	GC.collect();

	return &f;
}


/**
 * This class controls most of the process of querying a list of game servers.
 *
 * Objects of this class takes care of all GUI updates necessary while
 * querying servers.
 *
 * The process is mostly configured through the IServerRetriever object given
 * to the constructor.  This object does the actual querying and parsing.
 */
class ServerRetrievalController
{
	/**
	 * Text label for the progress bar.
	 *
	 * Set before calling run() if you don't want the default to be used.
	 */

	char[] progressLabel = "Querying servers";


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
	 */
	this(IServerRetriever retriever, bool replace=false)
	{
		serverRetriever_= retriever;
		replace_ = replace;

		serverRetriever_.initialize();

		serverList_ = serverTable.serverList;

		try
			maxTimeouts_ = Integer.toInt(getSetting("maxTimeouts"));
		catch (IllegalArgumentException e)
			maxTimeouts_ = 3;  // FIXME: use the actual default

		Display.getDefault.syncExec(dgRunnable( {
			serverTable.notifyRefreshStarted(&stop);
		}));
	}


	/**
	 * Calling this will make servers get added into ServerList directly.
	 *
	 * Workaround for ServerQueue not working when loading more than a few
	 * hundred servers from disk using the 'fromfile' argument.
	 */
	void disableQueue() { useQueue_ = false; }


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
			Display.getDefault.syncExec(statusBarUpdater_);

			total_ = serverRetriever_.prepare();

			if (total_ != 0) {
				auto dg = replace_ ? &serverList_.replace : &serverList_.add;

				if (useQueue_) {
					serverQueue_ = new ServerQueue(dg);
					deliverDg_ = &serverQueue_.add;
				}
				else {
					deliverDg2_ = dg;
					deliverDg_ = &deliverDgWrapper;
				}

				Display.getDefault.syncExec(dgRunnable( {
					statusBar.showProgress(progressLabel);
				}));

				serverRetriever_.retrieve(&deliver);
				serverList_.complete = !threadManager.abort;

				// a benchmarking tool
				if (arguments.quit) {
					Display.getDefault.syncExec(dgRunnable( {
						Trace.formatln("Time since startup: {} seconds.",
						                                   globalTimer.stop());
						mainWindow.close;
					}));
				}
				if (useQueue_)
					serverQueue_.stop(addRemaining_);
			}

			Display.getDefault.syncExec(dgRunnable( {
				if (threadManager.abort || wasStopped_) {
					statusBar.hideProgress("Interrupted");
					serverTable.notifyRefreshEnded;
				}
				else {
					statusBar.hideProgress("Done");
					done;
				}
			}));
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
	}


	/**
	 * Stops the whole process.
	 *
	 * If addRemaining is true, any servers already received will be added to
	 * the server list.
	 */
	void stop(bool addRemaining)
	{
		threadManager.abort = true;
		wasStopped_ = true;
		addRemaining_ = addRemaining;
	}


	private bool deliver(ServerHandle sh, bool replied, bool matched)
	{
		counter_++;

		assert(sh != InvalidServerHandle);

		if (!replied) {
			ServerData sd = serverList_.master.getServerData(sh);
			if (sd.failCount <= maxTimeouts_) {
				timedOut_++;
				// Try to match using the old data, since we still want to
				// display the server if we know it runs the right mod.
				assert(!matched);  // assure we don't do this needlessly
				matched =
				        matchMod(&sd, getGameConfig(serverList_.gameName).mod);
			}
			else {
				setEmpty(&sd);
				serverList_.master.setServerData(sh, sd);
				if (replace_)
					refillAndRefresh();  // make server disappear from GUI
				matched = false;
			}
		}

		if (matched)
			deliverDg_(sh);

		// progress display
		statusBarUpdater_.totalToQuery = total_;
		statusBarUpdater_.progress = counter_;

		Display.getDefault.syncExec(statusBarUpdater_);

		return !threadManager.abort;
	}


	private void done()
	{
		int index = -1;
		if (autoSelect.length) {
			// FIXME: select them all, not just the first one
			index = serverList_.getFilteredIndex(autoSelect[0]);
			serverTable.setSelection([index], true);
		}

		// FIXME: only doing this so that players will be shown
		serverTable.fullRefresh();

		serverTable.notifyRefreshEnded();
	}


	private void refillAndRefresh()
	{
		Display.getDefault.syncExec(dgRunnable( {
			serverList_.refillFromMaster();
			serverTable.fullRefresh();
		}));
	}

	// Just a workaround for ServerQueue.add and ServerList.add and replace
	// not having the same signatures.
	private final void deliverDgWrapper(ServerHandle sh)
	{
		assert(deliverDg2_ !is null);
		deliverDg2_(sh);
	}


	private {
		IServerRetriever serverRetriever_;
		int counter_ = 0;
		int total_;
		uint timedOut_ = 0;
		int maxTimeouts_;
		StatusBarUpdater statusBarUpdater_;
		bool replace_;
		void delegate(ServerHandle) deliverDg_;
		bool delegate(ServerHandle) deliverDg2_;
		bool wasStopped_ = false;
		bool addRemaining_ = true;
		bool useQueue_ = true;
		ServerList serverList_;
		ServerQueue serverQueue_;
	}
}


// Update the progress bar when querying servers.
private class StatusBarUpdater : Runnable {
	int totalToQuery;
	int progress;

	void run()
	{
		statusBar.setProgress(totalToQuery, progress);
	}
}
