/**
 * Implements the main functionality of the program.  Querying servers, etc.
 */

module serveractions;

import tango.core.Memory;
import Path = tango.io.Path;
import tango.io.Stdout;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;
import tango.text.stream.LineIterator;

import dwt.dwthelper.Runnable;
import dwt.widgets.Display;

import common;
import dialogs;
import mainwindow;
import qstat;
import runtools;
import serverlist;
import serverqueue;
import servertable;
import set;
import settings;
import threadmanager;


/**
 * Switches the active mod.
 *
 * Takes care of everything, updating the GUI as necessary, querying servers or
 * a master server if there's no pre-existing data for the mod, etc.  Most of
 * the work is done in a new thread.
 */
void switchToMod(char[] name)
{
	static char[] nameCopy;

	static void delegate() f() {
		if (serverTable.setServerList(nameCopy)) {
			ServerList serverList = serverTable.getServerList();

			// FIXME: move into setServerList?
			serverList.sort;
			serverTable.forgetSelection;
			serverTable.fullRefresh;
			statusBar.setDefaultStatus(serverList.length,
			                           serverList.filteredLength);
		}
		else {
			Mod mod = getModConfig(nameCopy);
			if (common.haveGslist && mod.useGslist)
				threadManager.runSecond(&getNewList);
			else if (Path.exists(mod.serverFile))
				threadManager.runSecond(&refreshList);
			else
				threadManager.runSecond(&getNewList);
		}
		return null;
	}

	nameCopy = name;
	threadManager.run(&f);
}


/** Loads the list from disk.  To be called through ThreadManager.run(). */
void delegate() loadSavedList()
{
	ServerList serverList = serverTable.getServerList();

	serverTable.clear();
	serverList.clear();
	GC.collect();

	Mod mod = getModConfig(serverList.modName);
	if (Path.exists(mod.serverFile)) {
		auto retriever = new FromFileServerRetriever(mod.name);
		auto contr = new ServerRetrievalController(retriever);
		contr.startMessage = "Loading saved server list...";
		contr.noReplyMessage = "No servers were found in the file";
		return &contr.run;
	}
	else {
		statusBar.setLeft("Unable to find a file for this mod's master server");
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
		char[] modName = serverTable.getServerList().modName;
		auto retriever = new QstatServerRetriever(modName,
		                                             Set!(char[])(addresses_));
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
	ServerList serverList = serverTable.getServerList();
	Mod mod = getModConfig(serverList.modName);

	if (!Path.exists(mod.serverFile)) {
		error("No server list found on disk, press\n"
                                   "\'Get new list\' to download a new list.");
		return null;
	}
	Set!(char[]) servers = filterServerFile(mod.name, mod.serverFile);

	log("Refreshing server list for " ~ mod.name ~ "...");
	char[] tmp;
	char[] sfile = tail(mod.serverFile, "/", tmp);
	log(Format("Found {} servers in {}.", servers.length, sfile));

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
		auto retriever = new QstatServerRetriever(mod.name, servers);
		auto contr = new ServerRetrievalController(retriever);
		contr.startMessage =
                            Format("Refreshing {} servers...", servers.length);
		contr.noReplyMessage = "None of the servers replied";
		return &contr.run;
	}
	else {
		statusBar.setLeft("No servers were found for this mod");
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
			ServerList serverList = serverTable.getServerList();
			Mod mod = getModConfig(serverList.modName);
			auto addresses = browserGetNewList(mod);
			log(Format("Got {} servers from {}.", addresses.length,
			                                                mod.masterServer));

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
				auto retriever = new QstatServerRetriever(mod.name, addresses,
				                                                         true);
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
	serverTable.getServerList().clear();
	GC.collect();

	statusBar.setLeft("Getting new server list...");
	char[] modName = serverTable.getServerList().modName;
	log("Getting new server list for " ~ modName ~ "...");
	serverTable.notifyRefreshStarted;
	
	return &f;
}


///
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


	///
	this(IServerRetriever retriever, bool replace=false)
	{
		serverRetriever_= retriever;
		replace_ = replace;

		serverRetriever_.initialize();

		Display.getDefault.syncExec(new class Runnable {
			void run() { serverTable.notifyRefreshStarted(&stop); }
		});
	}

	~this()
	{
		if (statusBarUpdater_)
			delete statusBarUpdater_;

	}

	///
	void run()
	{
		try {
			auto serverList = serverTable.getServerList();
			auto dg = replace_ ? &serverList.replace : &serverList.add;

			serverQueue_ = new ServerQueue(dg);
			deliverDg_ = &serverQueue_.add;

			statusBarUpdater_ = new StatusBarUpdater;
			statusBarUpdater_.text = startMessage;
			Display.getDefault.syncExec(statusBarUpdater_);

			// FIXME: handle prepare returning 0 to signal abort
			int serverCount_ = serverRetriever_.prepare();
			assert (serverCount_ != 0);

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

			if (serverQueue_ !is null)
				serverQueue_.addRemainingAndStop();

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

	///
	void stop()
	{
		threadManager.abort = true;
		wasStopped_ = true;
	}

	private bool deliver(ServerData* sd)
	{
		if (sd !is null)
			deliverDg_(sd);

		statusBarUpdater_.text = startMessage ~ Integer.toString(counter_++);
		Display.getDefault.syncExec(statusBarUpdater_);

		return !threadManager.abort;
	}

	private void done()
	{
		ServerList list = serverTable.getServerList();

		if (list.length() > 0) {
			int index = -1;
			if (autoSelect.length) {
				// FIXME: select them all, not just the first one
				index = list.getFilteredIndex(autoSelect[0]);
			}
			long noReply = cast(long)serverCount_ - list.length;
			serverTable.fullRefresh(index);
			statusBar.setDefaultStatus(list.length, list.filteredLength,
			                           noReply > 0 ? cast(uint)noReply : 0);
		}
		else {
			statusBar.setLeft(noReplyMessage);
		}
		serverTable.notifyRefreshEnded;
	}

	private {
		IServerRetriever serverRetriever_;
		uint serverCount_;
		int counter_ = 0;
		StatusBarUpdater statusBarUpdater_;
		bool replace_;
		void delegate(ServerData*) deliverDg_;
		bool wasStopped_ = false;
		ServerQueue serverQueue_;
	}
}


private class StatusBarUpdater : Runnable {
	char[] text;

	this(char[] text=null) { this.text = text; }

	void run() { statusBar.setLeft(text); }
}
