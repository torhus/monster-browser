module main;

private {
	import std.file;
	import std.string;
	import std.stdio;
	import std.thread;
	import std.conv;

	import runtools;
	import qstat;
	import serveractions;
	import serverlist;
	import link;
	import common;
	import settings;
	//import monitor;
	import gui.dialogs;
	import gui.mainwindow;
}

MainWindow mainWindow;
Thread serverThread;
ThreadDispatcher threadDispatcher;


void main() {
	version (NO_STDOUT) {
		freopen("STDOUT.TXT", "w", stdout);
	}

	try	{
		loadSettings();

		// check for presence of Gslist
		char[] gslistExe;
		version (Windows) {
			gslistExe = "gslist.exe";
		}
		else version(linux) {
			gslistExe = "gslist";
		}
		else {
			static assert(0);
		}

		common.useGslist = cast(bool) std.file.exists(gslistExe);

		if (common.useGslist) {
			log(gslistExe ~
			    " found, using it for faster server list retrieval.");
		}
		else {
			log(gslistExe ~
			    " not found, falling back to qstat for retrieving the "
			    "server list.");
		}

		mainWindow = new MainWindow;
	
		mainWindow.setInitDelegate(
		{
			version (loadSavedList) {
				loadSavedList();  // just for testing stuff
			}
			else {
				if (common.useGslist) {
					getNewList();
				}
				else {
					// Qstat is too slow to do a getNewList(), so just refresh
					// the old list instead, if possible.
					if (exists(activeMod.serverFile))
						refreshList();
					else
						getNewList();
				}
			}
		});

		mainWindow.setCleanupDelegate(
		{
			volatile runtools.abortParsing = true;
			statusBar.setLeft("Saving settings...");
			log("Saving settings...");
			saveSettings();
			statusBar.setLeft("Exiting...");
			log("Exiting...");
			log("Killing server browser...");
			runtools.killServerBrowser();
			//qstat.SaveRefreshList();
			/*log("Waiting for threads to terminate...");
			foreach (int i, Thread t; Thread.getAll()) {
				if (t != Thread.getThis()) {
					log("Waiting for thread " ~
					        common.std.string.toString(i) ~ "...");
					t.wait();
					log("    ...thread " ~
					        common.std.string.toString(i) ~ " done.");
				}
			}*/
		});

		threadDispatcher = new ThreadDispatcher();

		mainWindow.mainLoop();

	}
	catch(Exception e) {
		logx(__FILE__, __LINE__, e);
		error(e.classinfo.name ~ "\n" ~ e.toString());
	}
}


/**
 * Stores a pointer to a function and calls it only when serverThread has
 * terminated.
 */
class ThreadDispatcher
{
	synchronized
	void run(void function() fp)
	{
		debug (td) writefln("ThreadDispatcher.run()");
		assert(fp);
		fp_ = fp;
		dispatch();
	}


	synchronized
	private void dispatch()
	in {
		assert(fp_);
	}
	body {
		debug (td) writefln("ThreadDispatcher.dispatch()");

		if (serverThread !is null &&
		                     serverThread.getState() != Thread.TS.TERMINATED) {
			debug (td) writefln("...calling waitAndRun()");
			volatile abortParsing = true;
			waitAndRun();
		}
		else {
			debug (td) writefln(
			         "ThreadDispatcher.dispatch: Killing server browser...");
			bool success = killServerBrowser();

			debug (td) if (!success)
				writefln("killServerBrowser() failed.");
			else
				writefln("killServerBrowser() succeeded.");


			debug (td) writefln("...calling fp_()");
			/*display.syncExec(null, delegate void (Object o) {
				                            fp_();
			});*/
			fp_();
			fp_ = null;
		}

		debug (td) writefln("ThreadDispatcher.dispatch() returning");
	}


	private void waitAndRun()
	in {
		assert(serverThread !is null);
		assert(abortParsing);
	}
	body {
		bool done = false;

		debug (td) writefln("ThreadDispatcher.waitAndRun()");

		while (!done) {
			switch (serverThread.getState()) {
				case Thread.TS.INITIAL:
					debug (td) writefln("...TS.INITAL, waiting in loop");
					while (serverThread.getState() == Thread.TS.INITIAL) {
						// empty loop
					}
					break;
				case Thread.TS.RUNNING:
					debug (td) writefln("...TS.RUNNING");
					if (waiterThread_ !is null &&
					        waiterThread_.getState() != Thread.TS.TERMINATED) {
						volatile abortWaiting_ = true;

						debug (td)
							writefln("...waiting in loop for waiterThread_");

						while (waiterThread_.getState() !=
						                                Thread.TS.TERMINATED) {
							// empty loop
						}
					}
					volatile abortWaiting_ = false;
					waiterThread_ = new Thread(&waitForThread);
					waiterThread_.start();
					debug (td) writefln("...started waitForThread in a new thread");
					done = true;
					break;
				case Thread.TS.TERMINATED:
					debug (td) writefln("...TS.TERMINATED, calling dispatch()");
					dispatch();
					done = true;
					break;
			}
		}

		debug (td) writefln("ThreadDispatcher.waitAndRun() returning");
	}


	private int waitForThread()
	{
		debug (td) writefln("ThreadDispatcher.waitForThread()");

		volatile while (!abortWaiting_ &&
		                     serverThread.getState() != Thread.TS.TERMINATED) {
			Thread.getThis().yield();
		}

		if (!abortWaiting_) {
			debug (td) writefln(
			            "ThreadDispatcher.waitForThread() calling dispatch()");
			syncExec(null, delegate void (Object o) {
				dispatch();
			});
		}
		debug (td) writefln("ThreadDispatcher.waitForThread() returning");

		return 0;
	}


	private {
		void function() fp_ = null;
		Thread waiterThread_;
		bool abortWaiting_;
	}
}
