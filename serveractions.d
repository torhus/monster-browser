/**
 * Implements the main functionality of the program.  Querying servers, etc.
 */

module serveractions;

import tango.core.Memory;
import tango.core.Thread;
import tango.io.File;
import Path = tango.io.Path;
version (quit)
	import tango.io.Stdout;
import tango.text.convert.Format;
import tango.text.convert.Integer;

import dwt.dwthelper.Runnable;
import dwt.widgets.Display;

import common;
import main;
import qstat;
import runtools;
import serverlist;
import servertable;
import settings;


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
			if (common.useGslist)
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

	serverTable.reset();
	statusBar.setDefaultStatus(getActiveServerList.length,
			                   getActiveServerList.filteredLength);
}


/** Loads the list from disk, using a new thread to do the work. */
void loadSavedList()
{
	void f()
	{
		void callback(Object int_count)
		{
			statusBar.setLeft("Loading saved server list... " ~
			                  toString((cast(IntWrapper) int_count).value));
		}

		try {
			browserLoadSavedList(&callback);

			version (quit) { // for benchmarking
				Display.getDefault.syncExec(new class Runnable {
						void run()
						{
							Stdout.formatln("Time since startup: {} seconds.",
							                              globalTimer.seconds);
							mainWindow.close;
						}
				    });
			}

			volatile if (!runtools.abortParsing) {
				version (Tango) {
					Display.getDefault.asyncExec(new class Runnable {
						void run() { serverTable.reset(); }
				    });
				}
				else {
					Display.getDefault.asyncExec(null,
					                        delegate void (Object o) {
					                            serverTable.reset();
					                        });
				}
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
	}

	assert(serverThread is null || !serverThread.isRunning);

	statusBar.setLeft("Loading saved server list...");
	serverThread = new Thread(&f);
	serverThread.start();
}


/**
 * Queries a single server, adds it to the active server list, and refreshes
 * the serverTable to make it show up.
 *
 * The querying is done in a new thread.  The function does not verify that the
 * address is valid.
 */
void queryAndAddServer(in char[] address)
{
	static char[] addressCopy;

	void f()
	{
		void done(Object)
		{
				serverTable.reset(new IntWrapper(
				                       getActiveServerList.getFilteredIndex(addressCopy)));
		}

		try {
			browserRefreshList(delegate void(Object) { });

			version (Tango) {
				volatile if (!runtools.abortParsing) {
					Display.getDefault.asyncExec(new class Runnable {
						void run() { done(null); }
					});
				}
			}
			else {
				volatile if (!runtools.abortParsing) {
					Display.getDefault.asyncExec(null, &done);
				}
			}

		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
	}

	assert(serverThread is null || !serverThread.isRunning);

	File(REFRESHFILE).write(address ~ newline);

	addressCopy = address.dup;

	statusBar.setLeft("Querying server...");

	serverThread = new Thread(&f);
	serverThread.start();
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

		void status(Object int_count)
		{
			statusBar.setLeft("Got " ~  total ~ " servers, querying..." ~
			                  toString((cast(IntWrapper)int_count).value));
		}

		try {
			auto addresses = browserGetNewList();
			log(Format("Got {} servers from {}.", addresses.length,
			                                          activeMod.masterServer));

			auto extraServers = getActiveServerList().extraServers;
			foreach (s; extraServers)
					addresses.add(s);
			log(Format("Added {} extra servers.", extraServers.length));

			if (Path.exists(REFRESHFILE))
				Path.remove(REFRESHFILE);
			auto written = appendServersToFile(REFRESHFILE, addresses);
			log(Format("Wrote {} addresses to {}.", written, REFRESHFILE));

			total = toString(written);


			if (addresses.length == 0) {
				// FIXME: what to do when there are no servers?
				Display.getDefault.asyncExec(new class Runnable {
					void run() { serverTable.reset(); }
				});
			}
			else {
				Display display = Display.getDefault;
				version (Tango) {
					display.asyncExec(new class Runnable {
						void run() { statusBar.setLeft("Got "  ~
					                          total ~ " servers, querying...");
				        }
				    });
				}
				else {
				    display.asyncExec(null, delegate void (Object o) {
					                        statusBar.setLeft("Got "  ~
					                              total ~ " servers, querying...");
				                        } );
				}

				browserRefreshList(&status, true);
				volatile if (!runtools.abortParsing) {
					version (Tango) {
						display.asyncExec(new class Runnable {
							void run() { serverTable.reset(); }
					    });
					}
					else {

					    display.asyncExec(null, delegate void (Object o) {
					                                serverTable.reset();
					                            });
					}
				}
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
	serverThread.start();
}


/** Refreshes the list, in a new thread. */
void refreshList()
{
	static uint total;

	void f()
	{
		static char[] statusMsg;

		void status(Object int_count)
		{
			assert(statusMsg !is null);
			statusBar.setLeft(statusMsg ~
			                  toString((cast(IntWrapper)int_count).value));
		}

		void done(Object o)
		{
			serverTable.reset(null, total-getActiveServerList.length);
		}

		try {
			statusMsg = "Refreshing " ~  toString(total) ~ " servers...";
			browserRefreshList(&status);
			version (Tango) {
				volatile if (!runtools.abortParsing) {
					Display.getDefault.asyncExec(new class Runnable {
						void run() { done(null); }
					});
				}
			}
			else {
				volatile if (!runtools.abortParsing) {
					Display.getDefault.asyncExec(null, &done);
				}
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
	}

	assert(serverThread is null || !serverThread.isRunning);

	auto servers = filterServerFile(activeMod.serverFile, REFRESHFILE);
	log("Refreshing server list for " ~ activeMod.name ~ "...");
	log(Format("Found {} servers in {} and wrote them to {}.", servers.length,
	                                        activeMod.serverFile, REFRESHFILE));

	auto extraServers = getActiveServerList.extraServers;
	auto written = appendServersToFile(REFRESHFILE, extraServers, servers);
	log(Format("Added {} extra servers, skipping {} duplicates.", written,
	                                             extraServers.length-written));

	total = servers.length + written;
	statusBar.setLeft("Refreshing " ~ toString(total) ~ " servers...");
	serverTable.clear();
	getActiveServerList.clear();

	GC.collect();
	serverThread = new Thread(&f);
	serverThread.start();
}
