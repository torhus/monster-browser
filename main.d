module main;

import tango.core.Thread;
import tango.io.Console;
import tango.io.FilePath;
import tango.io.stream.FileStream;
import tango.text.Util;
import Integer = tango.text.convert.Integer;

import dwt.DWT;
import dwt.custom.SashForm;
import dwt.events.KeyAdapter;
import dwt.events.KeyEvent;
import dwt.events.ShellAdapter;
import dwt.events.ShellEvent;
import dwt.events.SelectionAdapter;
import dwt.events.SelectionEvent;
import dwt.graphics.Point;
import dwt.layout.FillLayout;
import dwt.layout.GridData;
import dwt.layout.GridLayout;
import dwt.layout.RowLayout;
import dwt.widgets.Button;
import dwt.widgets.Combo;
import dwt.widgets.Composite;
import dwt.widgets.Display;
import dwt.widgets.Label;
import dwt.widgets.MessageBox;
import dwt.widgets.Shell;
import dwt.widgets.ToolBar;
import dwt.widgets.ToolItem;

import common;
import cvartable;
import dialogs;
version (Windows)
	import link;
import playertable;
import qstat;
import runtools;
import serveractions;
import serverlist;
import servertable;
import settings;


Display display;
ServerTable serverTable;
PlayerTable playerTable;
CvarTable cvarTable;
StatusBar statusBar;
FilterBar filterBar;
SashForm middleForm, rightForm;
Shell mainWindow;
Thread serverThread;
ThreadDispatcher threadDispatcher;


void main(char[][] args) {
	version (redirect) {
		Cerr.output = new FileOutput("DEBUG.OUT");
		Cerr("Cerr is redirected to this file.").newline.flush;
		Cout.output = Cerr.output;
		Cout("Cout is redirected to this file.").newline.flush;
	}

	try	{
		loadSettings();

		display = Display.getDefault();
		mainWindow = new Shell(display);
		mainWindow.setText(APPNAME ~ " " ~ VERSION);

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

		common.useGslist = FilePath(gslistExe).exists();

		if (common.useGslist) {
			log(gslistExe ~
			    " found, using it for faster server list retrieval.");
		}
		else {
			log(gslistExe ~
			    " not found, falling back to qstat for retrieving the "
			    "server list.");
		}

		// restore saved size and state
		char[] size = getSetting("windowSize");
		int pos = locate(size, 'x');
		// FIXME: handle the case of 'x' not being found
		mainWindow.setSize(Integer.convert(size[0..pos]),
		                   Integer.convert(size[pos+1..length]));
		if (getSetting("windowMaximized") == "true") {
			mainWindow.setMaximized(true);
		}

		GridLayout gridLayout = new GridLayout();
		gridLayout.numColumns = 2;
		mainWindow.setLayout(gridLayout);


		// *********** MAIN WINDOW TOP ***************
		Composite topComposite = new Composite(mainWindow, DWT.NONE);
		GridData gridData = new GridData(GridData.HORIZONTAL_ALIGN_FILL |
		                                 GridData.GRAB_HORIZONTAL);
		gridData.horizontalSpan = 2;
		topComposite.setLayoutData(gridData);
		topComposite.setLayout(new FillLayout(DWT.HORIZONTAL));

		ToolBar toolBar = createToolbar(topComposite);

		// filtering options
		filterBar = new FilterBar(topComposite);


		// ************** SERVER LIST, PLAYER LIST, CVARS LIST ***************
		middleForm = new SashForm(mainWindow, DWT.HORIZONTAL);
		gridData = new GridData(GridData.FILL_BOTH);
		middleForm.setLayoutData(gridData);

		// server table widget
		serverTable = new ServerTable(middleForm);
		gridData = new GridData(GridData.FILL_VERTICAL);
		// FIXME: doesn't work
		//gridData.widthHint = 610;  // FIXME: automate using table's info
		serverTable.getTable().setLayoutData(gridData);

		// has to be instantied after the table
		setActiveServerList(activeMod.name);

		// parent for player and cvar tables
		rightForm = new SashForm(middleForm, DWT.VERTICAL);
		gridData = new GridData(GridData.FILL_BOTH);
		rightForm.setLayoutData(gridData);

		FillLayout rightLayout = new FillLayout(DWT.VERTICAL);
		rightForm.setLayout(rightLayout);

		int[] weights = parseIntegerSequence(getSessionState("middleWeights"));
		weights.length = 2;  // FIXME: use defaults instead?
		middleForm.setWeights(weights);;

		// player list
		playerTable = new PlayerTable(rightForm);
		gridData = new GridData();
		playerTable.getTable().setLayoutData(gridData);

		// Server info, cvars, etc
		cvarTable = new CvarTable(rightForm);
		gridData = new GridData();
		cvarTable.getTable().setLayoutData(gridData);

		weights = parseIntegerSequence(getSessionState("rightWeights"));
		weights.length = 2;  // FIXME: use defaults instead?
		rightForm.setWeights(weights);


		// **************** STATUS BAR ******************************
		Composite statusComposite = new Composite(mainWindow, DWT.NONE);
		gridData = new GridData(GridData.HORIZONTAL_ALIGN_FILL |
		                        GridData.GRAB_HORIZONTAL);
		gridData.horizontalSpan = 2;
		statusComposite.setLayoutData(gridData);
		statusComposite.setLayout(new FillLayout(DWT.HORIZONTAL));
		statusBar = new StatusBar(statusComposite);
		statusBar.setLeft(APPNAME ~ " is ready.");

		// **********************************************************

		mainWindow.addKeyListener(new class KeyAdapter {
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

		mainWindow.addShellListener(new class ShellAdapter {
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

		serverTable.getTable.setFocus();
		mainWindow.open();

		if (args.length > 1 && args[1] == "fromfile") {
			loadSavedList();
		}
		else {
			if (common.useGslist) {
				getNewList();
			}
			else {
				// Qstat is too slow to do a getNewList(), so just refresh
				// the old list instead, if possible.
				if (FilePath(activeMod.serverFile).exists())
					refreshList();
				else
					getNewList();
			}
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
		debug throw new Exception("rethrow from main()", e);
		logx(__FILE__, __LINE__, e);
		error(e.classinfo.name ~ "\n" ~ e.toString());
	}
}


class StatusBar
{

	this(Composite parent)
	{
		leftLabel_ = new Label(parent, DWT.NONE);
		leftLabel_.setText(APPNAME ~ " is ready.");
	}

	void setLeft(char[] text)
	{
		if (!leftLabel_.isDisposed) {
			leftLabel_.setText(text);
		}
	}

	void setDefaultStatus(size_t totalServers, size_t shownServers)
	{
		if (shownServers != totalServers) {
			setLeft("Showing " ~ Integer.toString(shownServers) ~ " of " ~
			        Integer.toString(totalServers) ~ " servers");
		}
		else {
			setLeft("Showing " ~ Integer.toString(totalServers) ~ " servers");
		}
	}

private:
	Label leftLabel_;
}


class FilterBar : Composite
{
	this(Composite parent)
	{
		filterComposite_ = new Composite(parent, DWT.NONE);
		button1_ = new Button(filterComposite_, DWT.CHECK);
		button1_.setText("Not empty");
		button1_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				ServerList list = getActiveServerList();
				bool notEmpty = button1_.getSelection() != 0;

				if (button1_.getSelection()) {
					button2_.setSelection(false);
					list.setFilters(list.getFilters() & ~Filter.HAS_HUMANS);
				}

				if (notEmpty)
					list.setFilters(list.getFilters() | Filter.NOT_EMPTY);
				else
					list.setFilters(list.getFilters() & ~Filter.NOT_EMPTY);
			}
		});

		button2_ = new Button(filterComposite_, DWT.CHECK);
		button2_.setText("Has humans");
		button2_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				ServerList list = getActiveServerList();
				bool hasHumans = button2_.getSelection() != 0;

				if (hasHumans)
					list.setFilters(list.getFilters() | Filter.HAS_HUMANS);
				else
					list.setFilters(list.getFilters() & ~Filter.HAS_HUMANS);

			}
		});

		// Restore saved filter state
		Filter state = cast(Filter)Integer.convert(
		                                       getSessionState("filterState"));
		if (state & Filter.NOT_EMPTY)
			button1_.setSelection(true);
		if (state & Filter.HAS_HUMANS)
			button2_.setSelection(true);

		// game type selection
		/*Combo combo = new Combo(filterComposite_, DWT.READ_ONLY);
		combo.setItems(gametypes);
		combo.select(0);*/

		// mod selection
		modCombo_ = new Combo(filterComposite_, DWT.DROP_DOWN);
		setMods(settings.modNames);
		if (getSetting("startWithLastMod") == "true") {
			char[] s = getSetting("lastMod");
			int i = findString(settings.modNames, s);
			if (i == -1) {
				modCombo_.add(s);
				modCombo_.select(modCombo_.getItemCount() - 1);
			}
			else {
				modCombo_.select(i);
			}
			setActiveMod(s);
		}

		modCombo_.clearSelection();  // FIXME: doesn't seem to work
		modCombo_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				serverTable.getTable.setFocus();
				switchToMod((cast(Combo)e.widget).getText());
			}

			public void widgetDefaultSelected(SelectionEvent e)
			{
				char[] s = trim((cast(Combo)e.widget).getText());
				if (s.length == 0) {
					return;
				}

				int i = findString(modNames, s);
				Combo combo = (cast(Combo) e.widget);
				if (i == -1) {
					combo.add(s);
					combo.select(combo.getItemCount() - 1);
				}
				else {
					combo.select(i);
				}

				serverTable.getTable.setFocus();
				switchToMod(s);
			}
		});

		filterComposite_.setLayout(new RowLayout(DWT.HORIZONTAL));
	}

	void setMods(char[][] list)
	{
		int sel, n, height;
		Point p;
		char[][] items;

		if (list is null)
			return;

		sel = modCombo_.getSelectionIndex();
		items = modCombo_.getItems();
		foreach (s; list) {
			if (findString(items, s) == -1) {
				modCombo_.add(s);
			}
		}
		n = modCombo_.getItemCount();
		if (n > 10) {
			n = 10;
		}
		p = modCombo_.getSize();
		height = modCombo_.getItemHeight() * n;
		// FIXME: setSize doesn't seem to do anything here :(
		modCombo_.setSize(p.x, height);

		if (sel == -1) {
			modCombo_.select(0);
		}
		else {
			modCombo_.select(sel);
		}
	}


private:
	Composite filterComposite_;
	Button button1_, button2_;
	Combo modCombo_;
}


ToolBar createToolbar(Composite parent)
{
	auto toolBar = new ToolBar(parent, DWT.HORIZONTAL);

	auto button1 = new ToolItem(toolBar, DWT.PUSH);
	button1.setText("Get new list");
	button1.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			threadDispatcher.run(&getNewList);
		}
	});

	new ToolItem(toolBar, DWT.SEPARATOR);

	ToolItem button2 = new ToolItem(toolBar, DWT.PUSH);
	button2.setText("Refresh list");
	button2.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			threadDispatcher.run(&refreshList);
		}
	});

	new ToolItem(toolBar, DWT.SEPARATOR);

	auto button3 = new ToolItem(toolBar, DWT.PUSH);
	button3.setText("Specify...");
	button3.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			auto dialog = new SpecifyServerDialog(mainWindow);
			if (dialog.open() == DWT.OK) {
				//saveSettings();
			}
		}
	});
/+
	new ToolItem(toolBar, DWT.SEPARATOR);

	auto button4 = new ToolItem(toolBar, DWT.PUSH);
	button4.setText("Monitor...");
	button4.setEnabled(false);
	button4.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			startMonitor(mainWindow);
			//SettingsDialog dialog = new SettingsDialog(mainWindow);
			/*if (dialog.open() == DWT.OK)
				saveSettings();*/
		}
	});
+/
	new ToolItem(toolBar, DWT.SEPARATOR);

	auto button5 = new ToolItem(toolBar, DWT.PUSH);
	button5.setText("Settings...");
	button5.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			SettingsDialog dialog = new SettingsDialog(mainWindow);
			if (dialog.open() == DWT.OK)
				saveSettings();
		}
	});

	return toolBar;
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

		if (serverThread && serverThread.isRunning) {
			volatile abortParsing = true;
		}
		else {
			debug Cout("ThreadDispatcher.dispatch: Killing server browser...")
			                                                          .newline;
			killServerBrowser();

			fp_();
			fp_ = null;
		}
	}

	private void function() fp_ = null;
}
