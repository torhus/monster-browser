module main;

import core.thread;
import std.exception : ErrnoException;
import std.file;
import std.path;
import std.stdio;
import std.string;
import core.sys.windows.windows;

import java.io.ByteArrayInputStream;
import org.eclipse.swt.SWT;
import org.eclipse.swt.dnd.Clipboard;
import org.eclipse.swt.graphics.Image;
import org.eclipse.swt.widgets.Control;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Event;
import org.eclipse.swt.widgets.Listener;

import colorednames;
import common;
import filewatcher;
import mainwindow;
import messageboxes;
import serveractions;
import servertable;
import settings;
import threadmanager;
import updatecheck;
version (Windows) import mswindows.util;


int main(string[] args) ///
{
	Thread.getThis().name = "main";

	try	{
		_main(args);
	}
	catch(Exception e) {
		logx(__FILE__, __LINE__, e);
		version (redirect)
			error(e.classinfo.name ~ "\n" ~ e.toString());
		return 1;
	}
	return 0;
}


private void _main(string[] args)
{
	globalTimer.start();

	detectDirectories(args[0]);

	checkConsoleOutput();

	try
		initLogging();
	catch (Exception e)
		debug warning(e.toString());

	log("Data path is '" ~ dataDir ~ "'.");

	parseCmdLine(args);

	loadSettings;

	mainWindow = new MainWindow;

	// Set the application's window icon.
	ByteArrayInputStream[] streams;
	streams ~= new ByteArrayInputStream(cast(byte[])import("mb16.png"));
	streams ~= new ByteArrayInputStream(cast(byte[])import("mb32.png"));

	Image[] appIcons;
	foreach (stream; streams)
		appIcons ~= new Image(Display.getDefault, stream);
	mainShell.setImages(appIcons);

	// Handle global keyboard shortcuts.
	Display.getDefault().addFilter(SWT.KeyDown, new class Listener {
		void handleEvent(Event e)
		{
			if ((cast(Control)e.widget).getShell() !is mainShell)
				return;

			switch (e.keyCode) {
				case SWT.ESC:
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0) {
						userAbort = true;
						serverTable.stopRefresh(true);
						e.type = SWT.None;
					}
					break;
				case SWT.F4:
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0) {
						threadManager.run(&checkForNewServers);
						e.type = SWT.None;
					}
					break;
				case SWT.F5:
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0) {
						threadManager.run(&refreshAll);
						e.type = SWT.None;
					}
					break;
				default:
					break;
			}
		}
	});

	clipboard = new Clipboard(Display.getDefault);

	threadManager = new ThreadManager;

	mainWindow.open();
	serverTable.getTable.setFocus();

	if (getSettingInt("checkForUpdates"))
		startUpdateChecker();

	initNameColors();
	
	if (settings.gameNames.length == 0)
		error("No valid game configurations were found.");
	else
		switchToGame(gameBar.selectedGame);

	startFileWatching();

	// main loop
	Display display = Display.getDefault;
	while (!mainShell.isDisposed) {
		if (!display.readAndDispatch())
			display.sleep();
	}


	// call all necessary dispose methods
	mainWindow.disposeAll();
	disposeNameColors();
	foreach (icon; appIcons)
		icon.dispose;
	clipboard.dispose;
	foreach (void delegate() dg; callAtShutdown)
		dg();

	// This has to come after all the other dispose calls.
	display.dispose;

	log("Saving settings...");
	saveSettings();

	log("Saving server lists...");
	foreach (entry; masterLists)
		entry.masterList.save();

	log("Exit.");
}



/**
 * Set the values of the globals appDir, dataDir, and logDir.
 *
 * The argument is args[0], as received by main().
 */
private void detectDirectories(string firstArg)
{
	appDir = dirName(absolutePath(firstArg));

	if (appDir[$-1] != '/')
		appDir ~= '/';

	if (exists(appDir ~ "portable.txt")) {
		dataDir = logDir = appDir;
	}
	else {
		version (Windows) {
			dataDir = getSpecialPath!CSIDL_APPDATA ~ '\\' ~ APPNAME ~ '\\';
			logDir = getSpecialPath!CSIDL_LOCAL_APPDATA ~ '\\' ~ APPNAME ~ '\\';
		}
		if (!exists(dataDir))
			mkdir(dataDir);
		if (!exists(logDir))
			mkdir(logDir);
	}
}


///
void checkConsoleOutput()
{
	version (console) {
		haveConsole = true;
	}
	else version (redirect) {
		haveConsole = false;
		assert(logDir.length);
		redirectOutput(logDir ~ "STDOUT.TXT", logDir ~ "STDERR.TXT");
	}
	else {
		haveConsole = false;
		version (Windows)
			redirectOutput("NUL", "NUL");
		else
			redirectOutput("/dev/null", "/dev/null");
	}
}


/*
 * Redirect stdout and stderr to files.
 *
 * Returns true if it succeeded redirecting both.
 */
private bool redirectOutput(string stdout_, string stderr_)
{
	bool failed = false;

	try {
		stdout.reopen(stdout_, "w");
	}
	catch (ErrnoException e)
	{
		warning("Unable to redirect stdout: " ~ e.toString());
		failed = true;
	}

	try {
		stderr.reopen(stderr_, "w");
	}
	catch (ErrnoException e)
	{
		warning("Unable to redirect stderr: " ~ e.toString());
		failed = true;
	}

	return !failed;
}
