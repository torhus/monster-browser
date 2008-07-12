module main;

import tango.core.Thread;
import tango.io.Console;
import tango.io.Path;
import tango.io.stream.FileStream;

import dwt.DWT;
import dwt.dnd.Clipboard;
import dwt.events.KeyAdapter;
import dwt.events.KeyEvent;
import dwt.events.ShellAdapter;
import dwt.events.ShellEvent;
import dwt.widgets.Display;

import common;
import dialogs;
version (Windows)
	import link;
import mainwindow;
import qstat;
import runtools;
import serveractions;
import serverlist;
import settings;


Thread serverThread;
ThreadDispatcher threadDispatcher;


void main(char[][] args) ///
{
	version (redirect) {
		try	{
			_main(args);
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
			error(e.classinfo.name ~ "\n" ~ e.toString());
		}
	}
	else {
		_main(args);
	}
}


private void _main(char[][] args)
{
	globalTimer = new Timer;

	version (redirect)
		redirectOutput("CONSOLE.OUT");

	if (!consoleOutputOk) {
		// Avoid getting IOExceptions all over the place.
		Cout.output = new FileOutput("NUL");
		Cerr.output = new FileOutput("NUL");
	}

	if (char[] error = initLogging) {
		debug warning(error);
		// Don't allow for release until refreshlist.tmp conflict is resolved.
		version (Final)			 
			assert(0);
	}

	parseCmdLine(args);

	loadSettings;

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

	common.haveGslist = exists(gslistExe);

	if (common.haveGslist) {
		log(gslistExe ~
			" found, using it for faster server list retrieval.");
	}
	else {
		log(gslistExe ~
			" not found, falling back to qstat for retrieving the "
			"server list.");
	}

	mainWindow = new MainWindow;

	mainWindow.handle.addKeyListener(new class KeyAdapter {
		public void keyPressed (KeyEvent e)
		{
			//FIXME: this function never gets called
			debug Cout("Keypressed").newline;
			switch (e.keyCode) {
				case DWT.F4:
					threadDispatcher.run(&getNewList);
					break;
				case DWT.F5:
					threadDispatcher.run(&refreshList);
					break;
				default:
					break;
			}
		}
	});

	mainWindow.handle.addShellListener(new class ShellAdapter {
		public void shellClosed(ShellEvent e)
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
			foreach (i, t; Thread.getAll()) {
				if (t != Thread.getThis()) {
					log("Waiting for thread " ~
											  Integer.toString(i) ~ "...");
					t.join();
					log("    ...thread " ~ Integer.toString(i) ~ " done.");
				}
			}*/
		}
	});

	setActiveServerList(activeMod.name);
	serverTable.getTable.setFocus();
	
	clipboard = new Clipboard(Display.getDefault);
	
	mainWindow.open();

	if (arguments.fromfile) {
		loadSavedList();
	}
	else {
		if (common.haveGslist && activeMod.useGslist) {
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

	threadDispatcher = new ThreadDispatcher;

	// main loop
	Display display = Display.getDefault;
	while (!mainWindow.handle.isDisposed) {
		threadDispatcher.dispatch();
		if (!display.readAndDispatch())
			display.sleep();
	}

	clipboard.dispose;
	display.dispose;
	
	shutDownLogging;
}


/**
 * Stores a pointer to a function or delegate and calls it only when
 * serverThread has terminated.
 */
class ThreadDispatcher
{
	void run(void function() fp) { dg_ = null; fp_ = fp; } ///
	void run(void delegate() dg) { fp_ = null; dg_ = dg; } ///

	void dispatch() ///
	{
		if (fp_ is null && dg_ is null)
			return;

		if (serverThread && serverThread.isRunning) {
			volatile abortParsing = true;
		}
		else {
			debug Cout("ThreadDispatcher.dispatch: Killing server browser...")
			                                                          .newline;
			killServerBrowser();

			if (fp_ !is null) {
				fp_();
				fp_ = null;
			}
			else {
				dg_();
				dg_ = null;
			}
		}
	}

	private void function() fp_ = null;
	private void delegate() dg_ = null;
}


/*
 * Redirect stdout and stderr (Cout and Cerr) to a file.
 *
 * Note: Cout and Cerr are flushed by a module destructor in Tango, so no
 *       explicit flushing upon shutdown is required.
 */
private bool redirectOutput(char[] file)
{
	try {
		Cerr.output = new FileOutput(file);
		Cerr("Cerr is redirected to this file.").newline.flush;
		Cout.output = Cerr.output;
		Cout("Cout is redirected to this file.").newline.flush;
		return true;
	}
	catch (IOException e) {
		debug warning(e.toString);
		return false;
	}
}


private bool consoleOutputOk()
{
	try {
		Cout.flush;
	}
	catch {
		return false;
	}
	return true;
}
