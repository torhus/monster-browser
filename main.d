module main;

private {
	import std.file;
	import std.string;
	import std.stdio;
	import std.thread;
	import std.conv;

	import dwt.all;
	import runtools;
	import qstat;
	import serveractions;
	import serverlist;
	import link;
	import servertable;
	import playertable;
	import mainwindow;
	import cvartable;
	import common;
	import settings;
	import monitor;
	import dialogs;
}

Display display;
ServerTable serverTable;
PlayerTable playerTable;
CvarTable cvarTable;
StatusBar statusBar;
FilterBar filterBar;
MainWindow mainWindow;
Thread serverThread;
ThreadDispatcher threadDispatcher;


void main() {
	version (NO_STDOUT) {
		freopen("STDOUT.TXT", "w", stdout);
	}

	try	{
		loadSettings();

		display = Display.getDefault();


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

		if (common.useGslist) {
			getNewList();
			//debug loadSavedList();
		}
		else {
			// Qstat is too slow to do a getNewList(), so just refresh
			// the old list instead, if possible.
			if (exists(activeMod.serverFile))
				refreshList();
			else
				getNewList();
		}

		threadDispatcher = new ThreadDispatcher();

		while (!mainWindow.isDisposed()) {
			threadDispatcher.dispatch();
			if (!display.readAndDispatch())
				display.sleep();
			}
			display.dispose();
	}
	catch(Exception e) {
		logx(__FILE__, __LINE__, e);
		MessageBox.showMsg(e.classinfo.name ~ "\n" ~ e.toString());
	}
}


/**
 * Stores a pointer to a function and calls it only when serverThread has
 * terminated.
 */
class ThreadDispatcher
{
	void run(void function() fp) { fp_ = fp; }

	void dispatch()
	{
		if (fp_ is null)
			return;

		if (serverThread && serverThread.getState() != Thread.TS.TERMINATED) {
			volatile abortParsing = true;
		}
		else {
			debug writefln("ThreadDispatcher.dispatch: Killing server browser...");
			bool success = killServerBrowser();

			debug if (!success)
				writefln("killServerBrowser() failed.");
			else
				writefln("killServerBrowser() succeeded.");


			fp_();
			fp_ = null;
		}
	}

	private void function() fp_ = null;
}
