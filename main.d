﻿module main;

import core.thread;
//debug import tango.core.tools.TraceExceptions;
import std.file;
import std.path;
import std.stdio;
version (Windows) import tango.sys.win32.SpecialPath;

import java.io.ByteArrayInputStream;
import org.eclipse.swt.SWT;
import org.eclipse.swt.dnd.Clipboard;
import org.eclipse.swt.graphics.Image;
import org.eclipse.swt.widgets.Control;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Event;
import org.eclipse.swt.widgets.Listener;

import colorednames : disposeNameColors;
import common;
import link;
import mainwindow;
import messageboxes;
import serveractions;
import servertable;
import settings;
import threadmanager;


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

	version (redirect) {
		haveConsole = false;
		redirectOutput(logDir);
	}
	else {
		// this isn't necessarily true
		haveConsole = true;
	}

	try
		initLogging();
	catch (StdioException e)
		debug warning(e.toString());

	log("Data path is '" ~ dataDir ~ "'.");

	parseCmdLine(args);

	loadSettings;

	// FIXME: make function for this
	// check for presence of Gslist
	string gslistExe;
	version (Windows) {
		gslistExe = appDir ~ "gslist.exe";
	}
	else version(linux) {
		gslistExe = appDir ~ "gslist";
	}
	else {
		static assert(0);
	}

	common.haveGslist = exists(gslistExe);

	if (common.haveGslist)
		log("Found gslist, using it for faster server list retrieval.");

	mainWindow = new MainWindow;

	// Set the application's window icon.
	ByteArrayInputStream streams[];
	streams ~= new ByteArrayInputStream(cast(byte[])import("mb16.png"));
	streams ~= new ByteArrayInputStream(cast(byte[])import("mb32.png"));

	Image[] appIcons;
	foreach (stream; streams)
		appIcons ~= new Image(Display.getDefault, stream);
	mainWindow.handle.setImages(appIcons);

	// Handle global keyboard shortcuts.
	Display.getDefault().addFilter(SWT.KeyDown, new class Listener {
		void handleEvent(Event e)
		{
			if ((cast(Control)e.widget).getShell() !is mainWindow.handle)
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
					threadManager.run(&checkForNewServers);
					e.type = SWT.None;
					break;
				case SWT.F5:
					threadManager.run(&refreshAll);
					e.type = SWT.None;
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
	switchToGame(filterBar.selectedGame);

	// main loop
	Display display = Display.getDefault;
	while (!mainWindow.handle.isDisposed) {
		if (!display.readAndDispatch())
			display.sleep();
	}


	// call all necessary dispose methods
	foreach (slist; serverListCache)
		slist.disposeCustomData();
	mainWindow.disposeAll();
	colorednames.disposeNameColors();
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
		if (entry.save)
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
	appDir = dirname(rel2abs(firstArg));

	if (appDir[$-1] != '/')
		appDir ~= '/';

	if (exists(appDir ~ "portable.txt")) {
		dataDir = logDir = appDir;
	}
	else {
		version (Windows) {
			dataDir = getSpecialPath(CSIDL_APPDATA) ~ '/' ~ APPNAME ~ '/';
			logDir = getSpecialPath(CSIDL_LOCAL_APPDATA) ~ '/' ~ APPNAME ~ '/';
		}
		if (!exists(dataDir))
			mkdir(dataDir);
		if (!exists(logDir))
			mkdir(logDir);
	}
}


/*
 * Redirect stdout and stderr to a file.
 *
 * Returns true if it succeeded.
 */
private bool redirectOutput(string dir)
{
	bool error = false;

	if (!freopen((dir ~ "stdout.log").ptr, "w", stdout.getFP())) {
		warning("Unable to redirect stdout to stdout.log");
		error = true;
	}

	if (!freopen((dir ~ "stderr.log").ptr, "w", stderr.getFP())) {
		warning("Unable to redirect stderr to stderr.log");
		error = true;
	}

	return !error;
}
