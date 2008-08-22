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
import servertable;
import set;
import settings;
import threading;


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

	static void f() {
		setActiveMod(nameCopy);

		if (setActiveServerList(activeMod.name)) {
			switchToActiveMod();
		}
		else {
			if (common.haveGslist && activeMod.useGslist)
				threadDispatcher.run(&getNewList);
			else if (Path.exists(activeMod.serverFile))
				threadDispatcher.run(&refreshList);
			else
				threadDispatcher.run(&getNewList);
		}
	}

	nameCopy = name;
	threadDispatcher.run(&f);
}


/**
 * Make the serverTable display the server list contained by activeServerList.
 *
 * Useful for updating the display after calling setActiveServerList.
 */
private void switchToActiveMod()
{
	getActiveServerList.sort();

	serverTable.forgetSelection();
	serverTable.reset();
	statusBar.setDefaultStatus(getActiveServerList.length,
	                           getActiveServerList.filteredLength);
}


/** Loads the list from disk.  To be called through ThreadDispatcher.run(). */
void delegate() loadSavedList()
{
	serverTable.clear();
	getActiveServerList.clear();
	GC.collect();

	if (Path.exists(activeMod.serverFile)) {
		auto retriever = new FromFileServerRetriever(activeMod.serverFile);
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
 *     address = IP address and port of servers to query.
 *     replace = Update the servers instead of adding new ones.
 *     select  = Select the newly added or refreshed servers.
 *
 * Note: This is meant to be be called through ThreadDispatcher.run().
 */
void delegate() queryServers(in char[][] addresses, bool replace=false,
                                                             bool select=false)
{
	if (!addresses.length)
		return null;

	auto retriever = new QstatServerRetriever(addresses);
	auto contr = new ServerRetrievalController(retriever, replace);
	if (select)
		contr.autoSelect = addresses;

	return &contr.run;
}


/**
 * Refreshes the list.
 *
 * Note: To be called through ThreadDispatcher.run().
 */
void delegate() refreshList()
{
	if (!Path.exists(activeMod.serverFile)) {
		error("No server list found on disk, press\n"
                                   "\'Get new list\' to download a new list.");
		return null;
	}
	Set!(char[]) servers = filterServerFile(activeMod.serverFile);

	log("Refreshing server list for " ~ activeMod.name ~ "...");
	char[] tmp;
	char[] sfile = tail(activeMod.serverFile, "/", tmp);
	log(Format("Found {} servers in {}.", servers.length, sfile));

	// merge in the extra servers
	Set!(char[]) extraServers = getActiveServerList.extraServers;
	auto oldLength = servers.length;
	foreach (server; extraServers)
		servers.add(server);

	auto delta = servers.length - oldLength;
	log(Format("Added {} extra servers, skipping {} duplicates.",
	                                        delta, extraServers.length-delta));

	serverTable.clear();
	getActiveServerList.clear();
	GC.collect();

	if (servers.length) {
		auto retriever = new QstatServerRetriever(servers.toArray);
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
 * Note: To be called through ThreadDispatcher.run().
 */
void delegate() getNewList()
{
	void f()
	{
		try {
			auto addresses = browserGetNewList();
			log(Format("Got {} servers from {}.", addresses.length,
			                                          activeMod.masterServer));

			auto extraServers = getActiveServerList().extraServers;
			foreach (s; extraServers)
					addresses.add(s);
			log(Format("Added {} extra servers.", extraServers.length));

			if (addresses.length == 0) {
				// FIXME: what to do when there are no servers?
				Display.getDefault.asyncExec(new class Runnable {
					void run()
					{
						serverTable.reset();
						serverTable.notifyRefreshEnded;
					}
				});
			}
			else {				
				auto retriever = new QstatServerRetriever(addresses.toArray,
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
	getActiveServerList.clear();
	GC.collect();

	statusBar.setLeft("Getting new server list...");
	log("Getting new server list for " ~ activeMod.name ~ "...");
	serverTable.notifyRefreshStarted;
	
	return &f;
}


///
class ServerRetrievalController
{
	/// Status messages.  Set before calling run().
	char[] startMessage = "Querying server(s)...";
	char[] noReplyMessage = "There was no reply";  /// ditto

	/* Set selection to these servers when retrieval is finished.  If it's
	 * null or empty, the previous selection will be retained.
	 *
	 * Note: Set before calling run().
	 */
	char[][] autoSelect = null;


	///
	this(IServerRetriever retriever, bool replace=false)
	{
		serverRetriever_= retriever;
		replace_ = replace;

		serverRetriever_.init();

		Display.getDefault.syncExec(new class Runnable {
			void run() { serverTable.notifyRefreshStarted; }
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
			deliverDg_ = replace_ ? &getActiveServerList.replace :
			                        &getActiveServerList.add;

			statusBarUpdater_ = new StatusBarUpdater;
			statusBarUpdater_.text = startMessage;
			Display.getDefault.syncExec(statusBarUpdater_);

			// FIXME: handle open returning 0 to signal abort
			int serverCount_ = serverRetriever_.open();
			assert (serverCount_ != 0);

			scope iter = new LineIterator!(char)(serverRetriever_.inputStream);
			abortParsing = false;
			qstat.parseOutput(iter, &deliver, &counter,
			                                      serverRetriever_.outputFile);
			getActiveServerList.complete = !abortParsing;
			serverRetriever_.close();
			
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

			Display.getDefault.asyncExec(new class Runnable {
				void run()
				{
					volatile if (!runtools.abortParsing)
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

	private void counter(int count)
	{
		statusBarUpdater_.text = startMessage ~ Integer.toString(count);
		Display.getDefault.syncExec(statusBarUpdater_);
	}

	private bool deliver(ServerData* sd)
	{
		if (sd !is null)
			deliverDg_(sd);
		return !abortParsing;
	}

	private void done()
	{
		if (getActiveServerList.length() > 0) {
			IntWrapper index = null;
			if (autoSelect.length) {
				// FIXME: select them all, not just the first one
				index = new IntWrapper(
				          getActiveServerList.getFilteredIndex(autoSelect[0]));
			}
			long noReply = cast(long)serverCount_ - getActiveServerList.length;
			serverTable.reset(index, noReply > 0 ? cast(uint)noReply : 0);
		}
		else {
			statusBar.setLeft(noReplyMessage);
		}
		serverTable.notifyRefreshEnded;
	}

	private {
		IServerRetriever serverRetriever_;
		uint serverCount_;
		StatusBarUpdater statusBarUpdater_;
		bool replace_;
		void delegate(ServerData*) deliverDg_;
	}
}


private class StatusBarUpdater : Runnable {
	char[] text;

	this(char[] text=null) { this.text = text; }

	void run() { statusBar.setLeft(text); }
}
