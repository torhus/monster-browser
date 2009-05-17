module main;

// Workaround for a bug in dmd < 1.041.
// http://d.puremagic.com/issues/show_bug.cgi?id=2673
static if (__VERSION__ < 1041) {
	debug import tango.core.stacktrace.StackTrace;
	debug version = bug2673;
}
debug import tango.core.stacktrace.TraceExceptions;
import tango.io.Console;
import tango.io.Path;
import tango.io.device.BitBucket;
import tango.io.device.File;
import tango.sys.Environment;
import tango.util.PathUtil;

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
	appDir = normalize(Environment.exePath(args[0]).path);

	globalTimer = new Timer;

	version (redirect)
		redirectOutput(appDir ~ "CONSOLE.OUT");

	if (!consoleOutputOk()) {
		// Avoid getting IOExceptions all over the place.
		Cout.output = new BitBucket;
		Cerr.output = Cout.output;
	}

	try
		initLogging();
	catch (IOException e)
		debug warning(e.toString());

	log("Using path '" ~ appDir ~ "'.");

	parseCmdLine(args);

	loadSettings;

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
	Display.getDefault().addFilter(SWT.KeyDown, new class Listener {
		void handleEvent(Event e)
		{
			if ((cast(Control)e.widget).getShell() !is mainWindow.handle)
				return;

			switch (e.keyCode) {
				case SWT.ESC:
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0) {
						serverTable.stopRefresh(true);
						e.type = SWT.None;
					}
					break;
				case SWT.F4:
					threadManager.run(&getNewList);
					e.type = SWT.None;
					break;
				case SWT.F5:
					threadManager.run(&refreshList);
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
		threadManager.dispatch();
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
	display.dispose;

	log("Saving settings...");
	saveSettings();

	log("Saving server lists...");
	foreach (master; masterLists)
		master.save();

	log("Exit.");
	shutDownLogging;
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
