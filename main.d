module main;

import tango.io.Console;
import tango.io.Path;
import tango.io.stream.FileStream;
import tango.sys.Environment;
import tango.util.PathUtil;

import dwt.DWT;
import dwt.dnd.Clipboard;
import dwt.dwthelper.ByteArrayInputStream;
import dwt.events.KeyAdapter;
import dwt.events.KeyEvent;
import dwt.events.ShellAdapter;
import dwt.events.ShellEvent;
import dwt.graphics.Image;
import dwt.widgets.Control;
import dwt.widgets.Display;
import dwt.widgets.Event;
import dwt.widgets.Listener;

import colorednames : disposeNameColors;
import common;
import dialogs;
import geoip : disposeFlagImages;
version (Windows)
	import link;
import mainwindow;
import serveractions;
import serverlist;
import servertable;
import settings;
import threadmanager;


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
	char[] s = replace(args[0].dup, '\\', '/');
	appDir = normalize(Environment.exePath(s).path);

	globalTimer = new Timer;

	version (redirect)
		redirectOutput(appDir ~ "CONSOLE.OUT");

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

	if (common.haveGslist) {
		log("'" ~ gslistExe ~
			"' found, using it for faster server list retrieval.");
	}
	else {
		log("'" ~ gslistExe ~
			"' not found, falling back to qstat for retrieving the "
			"server list.");
	}

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
						serverTable.stopRefresh();
						e.type = DWT.None;
					}
					break;
				case DWT.F4:
					threadManager.run(&getNewList);
					e.type = DWT.None;
					break;
				case DWT.F5:
					threadManager.run(&refreshList);
					e.type = DWT.None;
					break;
				default:
					break;
			}
		}
	});

	mainWindow.handle.addShellListener(new class ShellAdapter {
		public void shellClosed(ShellEvent e)
		{
			threadManager.abort = true;
			statusBar.setLeft("Saving settings...");
			log("Saving settings...");
			saveSettings();
			statusBar.setLeft("Exiting...");
			log("Exiting...");
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

	serverTable.setServerList(filterBar.selectedMod);
	serverTable.getTable.setFocus();
	
	clipboard = new Clipboard(Display.getDefault);

	threadManager = new ThreadManager;

	mainWindow.open();
	
	Mod mod = getModConfig(filterBar.selectedMod);

	if (arguments.fromfile) {
		threadManager.run(&loadSavedList);
	}
	else {
		if (common.haveGslist && mod.useGslist) {
			threadManager.run(&getNewList);
		}
		else {
			// Qstat is too slow to do a getNewList(), so just refresh
			// the old list instead, if possible.
			if (exists(mod.serverFile))
				threadManager.run(&refreshList);
			else
				threadManager.run(&getNewList);
		}
	}	

	// main loop
	Display display = Display.getDefault;
	while (!mainWindow.handle.isDisposed) {
		threadManager.dispatch();
		if (!display.readAndDispatch())
			display.sleep();
	}


	// call all necessary dispose methods
	ServerList.disposeAllCustomData();
	colorednames.disposeNameColors();
	geoip.disposeFlagImages();
	mainWindow.disposeAll();
	foreach (icon; appIcons)
		icon.dispose;
	clipboard.dispose;
	display.dispose;
	
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
		Cerr.output = new FileOutput(file);
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
	try {
		Cout.flush;
	}
	catch {
		return false;
	}
	return true;
}
