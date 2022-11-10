/**
 * Implements the main functionality of the program.  Querying servers, etc.
 */

module serveractions;

import core.memory;
import std.algorithm;
import std.conv;
import std.file;
import std.stdio;
import std.string;
import tango.text.xml.PullParser : XmlException;

import java.lang.Runnable;
import org.eclipse.swt.widgets.Display;

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
import syncaa;
import threadmanager;


///
struct MasterListCacheEntry
{
	MasterList masterList;  ///
	Set!(string) retryProtocols;  ///
}

/// Master server lists indexed by master list name.
__gshared MasterListCacheEntry*[char[]] masterLists;

/// ServerList cache indexed by game config name.
shared serverListCache = new SyncAA!(string, ServerList);

///
void updateServerListCache(string[] validGameNames)
{
	foreach (name; serverListCache.keys) {
		auto list = serverListCache[name];

		if (list is serverTable.serverList)
			continue;

		if (validGameNames.canFind(name))
			list.refillFromMaster(true);
		else
			serverListCache.remove(name);
	}
}


/**
 * Switches the active game.
 *
 * Takes care of everything, updating the GUI as necessary, querying servers or
 * a master server if there's no pre-existing data for the game, etc.  Most of
 * the work is done in the secondary thread.
 */
void switchToGame(string name, bool configChanged=false)
{
	__gshared string gameName;

	void f() {
		ServerList serverList;
		GameConfig game = getGameConfig(gameName);
		bool firstTime = true;

		// make sure we have a ServerList object
		if (ServerList list = serverListCache.get(gameName)) {
			serverList = list;
			firstTime = false;
		}
		else {
			string masterName = game.masterServer;
			MasterList master;

			// make sure we have a MasterList object
			if (auto m = masterName in masterLists) {
				master = (*m).masterList;
			}
			else {
				master = new MasterList(masterName);
				auto entry = new MasterListCacheEntry;
				// see http://d.puremagic.com/issues/show_bug.cgi?id=1860
				entry.masterList = master;
				masterLists[masterName] = entry;

				try {
					master.load(game.protocolVersion);
				}
				catch (FileException e) {
					error("There was an error reading " ~ master.fileName);
				}
				catch (XmlException e) {
					error("Syntax error in " ~ master.fileName);
				}

			}

			serverList = new ServerList(gameName, master, game.useEtColors);
			serverListCache[gameName] = serverList;

			// Add servers from the extra servers file, if found.
			auto file = game.extraServersFile;
			try {
				if (exists(file)) {
					auto addresses = collectIpAddresses(File(file));
					serverList.addExtraServers(addresses[]);
				}
			}
			catch (StdioException e) {
				log("Error when reading \"" ~ file ~ "\".");
			}
		}

		serverTable.setServerList(serverList);
		serverTable.clear();
		filterBar.clearSearch();

		if (serverList.complete) {
			serverList.refillFromMaster(configChanged);
			serverTable.forgetSelection();
			serverTable.fullRefresh();
			statusBar.setLeft("Ready");
		}
		else {
			int startupAction = getSettingInt("startupAction");

			if (startupAction == 0 || arguments.fromfile)
				threadManager.run(&loadSavedList);
			else if (startupAction == 2)
				threadManager.run(&checkForNewServers);
			else {
				if (serverList.master.length > 0)
					threadManager.run(&refreshAll);
				else
					threadManager.run(&checkForNewServers);
			}
		}

	}

	gameName = name;
	threadManager.run({ Display.getDefault().syncExec(dgRunnable(&f)); });
}


/** Loads the list from disk.  To be called through ThreadManager.run(). */
void loadSavedList()
{
	ServerList serverList = serverTable.serverList;
	MasterList master = serverList.master;

	Display.getDefault().syncExec(dgRunnable({
		serverTable.clear();
		serverList.clear();
	}));

	GC.collect();

	GameConfig game = getGameConfig(serverList.gameName);
	auto retriever = new MasterListServerRetriever(game, master);
	auto contr = new ServerRetrievalController(retriever);
	contr.disableQueue();
	contr.progressLabel = "Loading saved server list...";
	contr.run();
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
void queryServers(string[] addresses, bool replace=false, bool select=false)
{
	__gshared string[] addresses_;
	__gshared bool replace_, select_;

	static void f() {
		string gameName = serverTable.serverList.gameName;
		MasterList master = serverTable.serverList.master;

		auto retriever = new QstatServerRetriever(gameName, master,
		                                   Set!(string)(addresses_), replace_);
		auto contr = new ServerRetrievalController(retriever, replace_);
		contr.progressLabel = format("Querying %s servers", addresses_.length);

		if (select_)
			contr.autoSelect = addresses_;

		contr.run();
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
void refreshAll()
{
	ServerList serverList = serverTable.serverList;
	MasterList master = serverList.master;
	GameConfig game = getGameConfig(serverList.gameName);
	Set!(string) addresses, addresses2;
	auto entry = masterLists[master.name];
	auto retry = game.protocolVersion in entry.retryProtocols;

	assert(master.length > 0);

	foreach (sh; master) {
		ServerData sd = master.getServerData(sh);
		bool matched = matchGame(&sd, game);

		if (matched)
			addresses.add(sd.server[ServerColumn.ADDRESS]);
		else if (retry && timedOut(&sd) && sd.failCount < 2  &&
		                            sd.protocolVersion == game.protocolVersion)
			// retry previously unresponsive servers
			addresses2.add(sd.server[ServerColumn.ADDRESS]);
	}

	log("Refreshing server list for " ~ game.name ~ "...");
	log("%s servers to refresh, %s to retry.", addresses.length,
	                                                        addresses2.length);

	// merge in the extra servers
	Set!(string) extraServers = serverList.extraServers;
	auto oldLength = addresses.length;
	addresses.add(extraServers);

	auto delta = addresses.length - oldLength;
	log("Added %s extra servers, skipping %s duplicates.",
	                                         delta, extraServers.length-delta);

	Display.getDefault().syncExec(dgRunnable({
		serverTable.clear();
		serverList.clear();
	}));
	GC.collect();

	if (addresses.length || addresses2.length) {
		auto updater = new StatusBarUpdater(cast(int)(addresses.length +
		                                               addresses2.length));
		if (addresses.length) {
			auto retriever = new QstatServerRetriever(game.name, master,
			                                                  addresses, true);
			auto contr = new ServerRetrievalController(retriever, false,
			                                      !addresses2.length, updater);
			contr.progressLabel = text("Refreshing ", addresses.length,
			                           " servers");
			contr.run();
		}

		if (addresses2.length && !threadManager.abort) {
			auto retriever = new QstatServerRetriever(game.name, master,
			                                                 addresses2, true);
			auto contr = new ServerRetrievalController(retriever, false, true,
			                                                           updater);
			contr.progressLabel = text("Retrying ", addresses2.length,
			                            " previously unresponsive servers");
			contr.interruptedMessage = "Ready";
			contr.run();
		}
	}
	else {
		Display.getDefault().syncExec(dgRunnable({
			statusBar.setLeft("No servers were found for this game");
		}));
	}
}


/**
 * Checks for new servers for the current mod.
 *
 * Note: To be called through ThreadManager.run().
 */
void checkForNewServers()
{
	ServerList serverList = serverTable.serverList;

	log("Checking for new servers for " ~ serverList.gameName ~ "...");

	Display.getDefault().syncExec(dgRunnable({
		serverTable.notifyRefreshStarted((bool) {
			threadManager.abort = true;
		});
	}));

	GC.collect();

	try {
		MasterList master = serverList.master;
		GameConfig game = getGameConfig(serverList.gameName);
		string masterName = split(game.masterServer, ":")[0];
		Set!(string) addresses;
		bool serverError = false;

		Display.getDefault().syncExec(dgRunnable( {
			statusBar.showProgress("Getting new list from " ~ masterName, true);
		}));
		
		try {
			addresses = browserGetNewList(game);
		}
		catch (MasterServerException e) {
			Display.getDefault().syncExec(dgRunnable( {
				statusBar.setProgressError();
			}));
			error("Unable to retrieve a server list from " ~ masterName ~
			                              ".\n\n\"" ~ e.toString() ~ "\"");
			serverError = true;
		}

		// Make sure we don't start removing servers based on an incomplete
		// address list.
		if (serverError || threadManager.abort) {
			Display.getDefault().syncExec(dgRunnable( {
				statusBar.hideProgress("Ready");
				serverTable.notifyRefreshEnded();
			}));
			return;
		}

		size_t total = addresses.length;
		int removed = 0;
		Set!(string) addresses2;

		// Exclude servers that are already known to run the right mod, and
		// delete servers from the master list that's missing from the
		// master server.
		foreach (sh; master) {
			ServerData sd = master.getServerData(sh);

			// Prevent servers with a different protocol version from being
			// removed.  This also causes the server to remain in addresses if
			// it has switched protocol versions, causing it to be queried in
			// the first batch of servers instead of the second.
			if (sd.protocolVersion != game.protocolVersion)
				continue;

			string address = sd.server[ServerColumn.ADDRESS];
			if (address in addresses) {
				addresses.remove(address);
				if (!matchGame(&sd, game))
					addresses2.add(address);
			}
			else if (!sd.persistent) {
				master.removeServer(sh);
				removed++;
			}
		}

		log("Got %s servers from %s, including %s new.",
		                           total, game.masterServer, addresses.length);

		if (removed > 0) {
			Display.getDefault().syncExec(dgRunnable( {
				serverList.refillFromMaster();
				serverTable.fullRefresh();
			}));

			log("Removed %s servers that were missing from master.", removed);
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
			auto updater = new StatusBarUpdater(cast(int)(addresses.length +
			                                              addresses2.length));

			masterLists[master.name].retryProtocols.add(game.protocolVersion);

			auto retriever = new QstatServerRetriever(game.name, master,
			                                                  addresses, true);
			auto contr = new ServerRetrievalController(retriever, false,
			                                      !addresses2.length, updater);
			string message = format("Got %s servers, querying", total);
			if (addresses.length < total)
				contr.progressLabel = message ~ format(" %s new",
			                                     addresses.length);
			else
				contr.progressLabel = message;

			contr.run();

			if (addresses2.length) {
				retriever = new QstatServerRetriever(game.name,
				                                     master, addresses2, true);
				contr = new ServerRetrievalController(retriever, false, true,
				                                                      updater);
				contr.progressLabel = message ~ format(" %s already known",
				                                            addresses2.length);
				contr.interruptedMessage = "Ready";
				contr.run();
			}
		}
	}
	catch(Exception e) {
		logx(__FILE__, __LINE__, e);
	}
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
	string progressLabel = "Querying servers";
	

	/**
	 * Status message shown if interrupted by the user or otherwise.
	 *
	 * Set before calling run() if you don't want the default to be used.
	 */
	string interruptedMessage = "Aborted";


	/**
	 * Set selection to these servers when retrieval is finished.
	 *
	 * If null or empty, the previous selection will be retained.
	 *
	 * Note: Set before calling run().
	 */
	string[] autoSelect = null;


	/**
	 * Params:
	 *     replace = Pass the received servers to ServerList.replace instead of
	 *               the default ServerList.add.
	 *     finish  = Set this to false when querying servers in multiple
	 *               batches.  Set it to true again for the last batch.
	 *     updater = If querying in multiple batches, prime this with the
	 *               combined total number of servers for all batches.  Then
	 *               reuse the same object for each batch.
	 */
	this(IServerRetriever retriever, bool replace=false, bool finish=true,
	                                        StatusBarUpdater updater=null)
	{
		serverRetriever_= retriever;
		replace_ = replace;
		finish_ = finish;
		statusBarUpdater_ = updater;

		serverRetriever_.initialize();

		serverList_ = serverTable.serverList;

		maxTimeouts_ = getSettingInt("maxTimeouts");

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
			int total = serverRetriever_.prepare();

			if (total != 0) {
				auto dg = replace_ ? &serverList_.replace : &serverList_.add;

				if (useQueue_) {
					serverQueue_ = new ServerQueue(dg);
					deliverDg_ = &serverQueue_.add;
				}
				else {
					deliverDg2_ = dg;
					deliverDg_ = &deliverDgWrapper;
				}

				if (!statusBarUpdater_)
					statusBarUpdater_ = new StatusBarUpdater(total);
				else
					assert(statusBarUpdater_.total >= total);

				Display.getDefault.syncExec(dgRunnable( {
					statusBar.showProgress(progressLabel, false,
					      statusBarUpdater_.total, statusBarUpdater_.progress);
				}));

				userAbort = false;
				serverRetriever_.retrieve(&deliver);

				// a benchmarking tool
				if (arguments.quit) {
					Display.getDefault.syncExec(dgRunnable( {
						log("Time since startup: %s seconds.",
						                                  globalTimer.seconds);
						mainWindow.close;
					}));
				}
				if (useQueue_)
					serverQueue_.stop(addRemaining_);
			}

			Display.getDefault.syncExec(dgRunnable( {
				if (threadManager.abort || wasStopped_) {
					statusBar.hideProgress(interruptedMessage);
					serverTable.notifyRefreshEnded;
					serverList_.complete = false;

					if (userAbort) {
						// disable refreshAll's autoretry
						MasterList master = serverList_.master;
						GameConfig game = getGameConfig(serverList_.gameName);
						auto masterItem = masterLists[master.name];
						masterItem.retryProtocols.remove(game.protocolVersion);
					}
				}
				else {
					if (finish_) {
						statusBar.hideProgress("Done");
						done();
					}
					serverList_.complete = true;
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


	private bool deliver(ServerHandle sh, bool replied)
	{
		assert(sh != InvalidServerHandle);
		
		ServerData sd = serverList_.master.getServerData(sh);
		GameConfig game = getGameConfig(serverList_.gameName);
		bool matched;

		if (replied) {
			matched = matchGame(&sd, game);
		}
		else {
			if (sd.failCount <= maxTimeouts_) {
				timedOut_++;
				if (sd.protocolVersion.length == 0) {
					// This can happen when checking for new servers.  Just set
					// the most likely protocol version, so the server gets
					// included in refreshAll()'s requery of unresponsive
					// servers.
					sd.protocolVersion = game.protocolVersion;
					serverList_.master.setServerData(sh, sd);
				}
				// Try to match using the old data, since we still want to
				// display the server if we know it runs the right game.
				matched = matchGame(&sd, game);
			}
			else {
				serverList_.master.removeServer(sh);
				if (replace_)
					refillAndRefresh();  // make server disappear from GUI
				matched = false;
			}
		}

		if (matched)
			deliverDg_(sh);

		// progress display
		statusBarUpdater_.increment();
		Display.getDefault.syncExec(statusBarUpdater_);

		return !threadManager.abort;
	}


	private void done()
	{
		debug serverList_.verifySorted();

		// FIXME: Ugly workaround for sorting bug, #33.
		serverList_.sort();

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
		bool finish_;
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


/// Update the progress bar when querying servers.
class StatusBarUpdater : Runnable {
	///
	this(int totalServers)
	{
		assert(totalServers >= 0);
		total_ = totalServers;
	}

	int total() { return total_; } ///
	int progress() { return progress_; } ///

	///
	void increment(int amount=1)
	{
		assert(amount >= 0);
		progress_ += amount;
	}

	void run() ///
	{
		statusBar.setProgress(total, progress);
	}
	
	private int progress_ = 0, total_;
}
