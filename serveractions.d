/**
 * Implements the main functionality of the program.  Querying servers, etc.
 */

module serveractions;

import tango.core.Memory;
import tango.core.Thread;
import tango.io.File;
import Path = tango.io.Path;
import tango.io.Stdout;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;
import tango.text.stream.LineIterator;

import dwt.dwthelper.Runnable;
import dwt.widgets.Display;

import common;
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
				getNewList();
			else if (Path.exists(activeMod.serverFile))
				refreshList();
			else
				getNewList();
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


/** Loads the list from disk, using a new thread to do the work. */
void loadSavedList()
{
	serverTable.clear();
	getActiveServerList.clear();

	if (Path.exists(activeMod.serverFile)) {
		auto retriever = new FromFileServerRetriever(activeMod.serverFile);
		auto contr = new ServerRetrievalController(retriever);
		contr.startMessage = "Loading saved server list...";
		contr.noReplyMessage = "No servers were found in the file";
		contr.start;
	}
	else {
		Display.getDefault.asyncExec(new class Runnable {
			void run()
			{
				statusBar.setLeft(
				         "Unable to find a file for this mod's master server");
			}
		});
	}
}


/**
 * Queries one or more servers, adds them to the active server list, and
 * refreshes the serverTable to make them show up.
 *
 * If replace is true, it will instead update servers with new data.
 *
 * The querying is done in a new thread.  The function does not verify that the
 * address is valid.
 *
 * Params:
 *     address = IP address and port of servers to query.
 *     replace = Update the servers instead of adding new ones.
 *     select  = Select the newly added or refreshed servers.
 */
void queryServers(in char[][] addresses, bool replace=false, bool select=false)
{
	if (!addresses.length)
		return;

	auto retriever = new QstatServerRetriever(addresses);
	auto contr = new ServerRetrievalController(retriever, replace);
	if (select)
		contr.autoSelect = addresses;
	threadDispatcher.run(&contr.start);
}


/** Refreshes the list, in a new thread. */
void refreshList()
{
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

	if (servers.length) {
		auto retriever = new QstatServerRetriever(servers.toArray);
		auto contr = new ServerRetrievalController(retriever, false);
		contr.startMessage =
		                    Format("Refreshing {} servers...", servers.length);
		contr.noReplyMessage = "None of the servers replied";
		contr.start;
	}
	else {
		statusBar.setLeft("No servers were found for this mod");
	}
}


///
class ServerRetrievalController
{
	/// Status messages.
	char[] startMessage = "Querying server(s)...";
	char[] noReplyMessage = "There was no reply";  /// ditto

	/// Set selection to these servers when retrieval is finished.  If it's
	/// null or empty, the previous selection will be retained.
	char[][] autoSelect = null;


	///
	this(IServerRetriever retriever, bool replace=false)
	{
		serverRetriever_= retriever;
		replace_ = replace;
		statusBarUpdater_ = new StatusBarUpdater;
	}

	~this()
	{
		if (statusBarUpdater_)
			delete statusBarUpdater_;

	}

	///
	void start()
	{
		assert(serverThread is null || !serverThread.isRunning);

		serverRetriever_.init();
		
		statusBar.setLeft(startMessage);

		GC.collect;
		serverThread = new Thread(&run);
		serverTable.notifyRefreshStarted;
		serverThread.start();
	}

	private void run()
	{
		try {
			auto deliverDg = replace_ ? &getActiveServerList.replace :
			                            &getActiveServerList.add;

			// FIXME: handle open returning 0 to signal abort
			int serverCount_ = serverRetriever_.open();
			assert (serverCount_ != 0);

			scope iter = new LineIterator!(char)(serverRetriever_.inputStream);
			qstat.parseOutput(iter, deliverDg, &counter,
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
	}
}


/**
 * Retrieves a new list from the master server.
 *
 * Uses a new thread to do the work.
 */
void getNewList()
{
	void f()
	{
		static char[] total;
		scope status = new StatusBarUpdater;

		void counter(int count)
		{
			status.text = "Got " ~  total ~
			                 " servers, querying..." ~ Integer.toString(count);
			Display.getDefault.syncExec(status);
		}

		try {
			auto addresses = browserGetNewList();
			log(Format("Got {} servers from {}.", addresses.length,
			                                          activeMod.masterServer));

			auto extraServers = getActiveServerList().extraServers;
			foreach (s; extraServers)
					addresses.add(s);
			log(Format("Added {} extra servers.", extraServers.length));

			if (Path.exists(appDir ~ REFRESHFILE))
				Path.remove(appDir ~ REFRESHFILE);
			auto written = appendServersToFile(appDir ~ REFRESHFILE, addresses);
			log(Format("Wrote {} addresses to {}.", written, REFRESHFILE));

			total = Integer.toString(written);


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
				Display display = Display.getDefault;
				display.asyncExec(new StatusBarUpdater("Got "  ~
				                             total ~ " servers, querying..."));

				browserRefreshList(&getActiveServerList.add, &counter, true);
				display.asyncExec(new class Runnable {
					void run()
					{
						volatile if (!runtools.abortParsing)
							serverTable.reset;
						serverTable.notifyRefreshEnded;
					}
				});
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}

	}

	assert(serverThread is null || !serverThread.isRunning);

	serverTable.clear();
	getActiveServerList.clear();

	GC.collect();
	statusBar.setLeft("Getting new server list...");
	log("Getting new server list for " ~ activeMod.name ~ "...");
	serverThread = new Thread(&f);
	serverTable.notifyRefreshStarted;
	serverThread.start();
}


private class StatusBarUpdater : Runnable {
	char[] text;

	this(char[] text=null) { this.text = text; }

	void run() { statusBar.setLeft(text); }
}
