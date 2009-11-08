module main;

// Workaround for a bug in dmd < 1.041.
// http://d.puremagic.com/issues/show_bug.cgi?id=2673
static if (__VERSION__ < 1041) {
	debug import tango.core.stacktrace.StackTrace;
	debug version = bug2673;
}
import tango.core.Thread;
debug import tango.core.stacktrace.TraceExceptions;
import tango.io.Console;
import tango.io.Path;
import tango.io.device.BitBucket;
import tango.io.device.File;
import tango.sys.Environment;
import tango.sys.win32.SpecialPath;
import tango.util.PathUtil;

import dwt.DWT;
import dwt.dnd.Clipboard;
import dwt.dwthelper.ByteArrayInputStream;
import dwt.graphics.Image;
import dwt.widgets.Control;
import dwt.widgets.Display;
import dwt.widgets.Event;
import dwt.widgets.Listener;

import colorednames : disposeNameColors;
import common;
version (Windows)
	import link;
import mainwindow;
import messageboxes;
import serveractions;
import servertable;
import settings;
import threadmanager;


void main(char[][] args) ///
{
	Thread.getThis().name = "main";

	version (bug2673)
		rt_setTraceHandler(&basicTracer);

	try	{
		_main(args);
	}
	catch(Exception e) {
		logx(__FILE__, __LINE__, e);
		version (redirect)
			error(e.classinfo.name ~ "\n" ~ e.toString());
	}
}


private void _main(char[][] args)
{
	globalTimer.start();

	detectDirectories(args[0]);

	version (redirect)
		redirectOutput(logDir ~ "CONSOLE.OUT");

	if (!consoleOutputOk()) {
		// Avoid getting IOExceptions all over the place.
		Cout.output = new BitBucket;
		Cerr.output = Cout.output;
	}

	try
		initLogging();
	catch (IOException e)
		debug warning(e.toString());

	log("Data path is '" ~ dataDir ~ "'.");

	parseCmdLine(args);

	loadSettings;

	// FIXME: make function for this
	// check for presence of Gslist
	char[] gslistExe;
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
	Display.getDefault().addFilter(DWT.KeyDown, new class Listener {
		void handleEvent(Event e)
		{
			if ((cast(Control)e.widget).getShell() !is mainWindow.handle)
				return;

			switch (e.keyCode) {
				case DWT.ESC:
					if ((e.stateMask & DWT.MODIFIER_MASK) == 0) {
						serverTable.stopRefresh(true);
						e.type = DWT.None;
					}
					break;
				case DWT.F4:
					threadManager.run(&checkForNewServers);
					e.type = DWT.None;
					break;
				case DWT.F5:
					threadManager.run(&refreshAll);
					e.type = DWT.None;
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
	foreach (master; masterLists)
		master.save();

	log("Exit.");
	shutDownLogging;
}



/**
 * Set the values of the globals appDir, dataDir, and logDir.
 *
 * The argument is args[0], as received by main().
 */
private void detectDirectories(in char[] firstArg)
{
	appDir = normalize(Environment.exePath(firstArg).path);
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
			createFolder(dataDir);
		if (!exists(logDir))
			createFolder(logDir);
	}
}


/*
 * Redirect stdout and stderr (Cout and Cerr) to a file.
 *
 * Note: Cout and Cerr are flushed by a module destructor in Tango, so explicit
 *       flushing upon shutdown is not required.
 */
private bool redirectOutput(char[] file)
{
	try {
		Cerr.output = new File(file, WriteCreateShared);
		Cerr("Cerr is redirected to this file.").newline.flush;
		Cout.output = Cerr.output;
		Cout("Cout is redirected to this file.").newline.flush;
		return true;
	}
	catch (IOException e) {
		warning(e.toString);
		return false;
	}
}


private bool consoleOutputOk()
{
	try
		Cout(APPNAME ~ " " ~ VERSION).newline.flush;
	catch (IOException e)
		return false;
	return true;
}
