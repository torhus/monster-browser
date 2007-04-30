module main;

private {
	import std.string;
	import std.stdio;
	import std.thread;
	import std.conv;

	import dwt.all;
	import parselist;
	import qstat;
	import serverlist;
	import link;
	import servertable;
	import playertable;
	import cvartable;
	import common;
	import settings;
	import monitor;
	import dialogs;
}

Display display;
ServerTable serverTable;
ServerList activeServerList;
PlayerTable playerTable;
CvarTable cvarTable;
StatusBar statusBar;
FilterBar filterBar;
Shell mainWindow;
Thread serverThread;
ThreadDispatcher threadDispatcher;


void main() {
	version (NO_STDOUT) {
		freopen("STDOUT.TXT", "w", stdout);
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

		// restore saved size and state
		char[] size = getSetting("windowSize");
		int pos = std.string.find(size, 'x');
		mainWindow.setSize(toInt(size[0..pos]), toInt(size[pos+1..length]));
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
		SashForm middleForm = new SashForm(mainWindow, DWT.HORIZONTAL);
		gridData = new GridData(GridData.FILL_BOTH);
		middleForm.setLayoutData(gridData);

		// server table widget
		serverTable = new ServerTable(middleForm);
		gridData = new GridData(GridData.FILL_VERTICAL);
		// FIXME: doesn't work
		//gridData.widthHint = 610;  // FIXME: automate using table's info
		serverTable.getTable().setLayoutData(gridData);

		// has to be instantied after the table
		setActiveServerList(modName);

		// parent for player and cvar tables
		SashForm rightForm = new SashForm(middleForm, DWT.VERTICAL);
		gridData = new GridData(GridData.FILL_BOTH);
		rightForm.setLayoutData(gridData);

		FillLayout rightLayout = new FillLayout(DWT.VERTICAL);
		rightForm.setLayout(rightLayout);

		// distribution of space between the tables
		middleForm.setWeights([16, 5]);

		// player list
		playerTable = new PlayerTable(rightForm);
		gridData = new GridData();
		playerTable.getTable().setLayoutData(gridData);

		// Server info, cvars, etc
		cvarTable = new CvarTable(rightForm);
		gridData = new GridData();
		cvarTable.getTable().setLayoutData(gridData);

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
				debug writefln("Keypressed");
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
				volatile parselist.abort = true;
				statusBar.setLeft("Saving settings...");
				log("Saving settings...");
				saveSettings();
				statusBar.setLeft("Exiting...");
				log("Exiting...");
				log("Killing server browser...");
				parselist.killServerBrowser();
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
			}
		});

		serverTable.getTable.setFocus();
		mainWindow.open();

		if (common.useGslist) {
			getNewList();
			//debug loadSavedList();
		}
		else {
			// Qstat is too slow to do a getNewList(), so just refresh
			// the old list instead, if possible.
			if (getSetting("lastMod") == settings.modName) {
				refreshList();
			}
			else {
				//getNewList();
				refreshList();
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
		logx(__FILE__, __LINE__, e);
		MessageBox.showMsg(e.classinfo.name ~ "\n" ~ e.toString());
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
			setLeft("Showing " ~
			         std.string.toString(shownServers) ~ " of " ~
			         std.string.toString(totalServers) ~ " servers");
		}
		else {
			setLeft("Showing " ~ std.string.toString(totalServers) ~
			         " servers");
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
				if (button1_.getSelection()) {
					button2_.setSelection(false);
					activeServerList.filterHasHumans(false);
				}
				activeServerList.filterNotEmpty(button1_.getSelection() != 0);
			}
		});

		button2_ = new Button(filterComposite_, DWT.CHECK);
		button2_.setText("Has humans");
		button2_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				activeServerList.filterHasHumans(cast(bool) (cast(Button) e.widget).
				                                               getSelection());
			}
		});

		// game type selection
		/*Combo combo = new Combo(filterComposite_, DWT.READ_ONLY);
		combo.setItems(gametypes);
		combo.select(0);*/

		// mod selection
		modCombo_ = new Combo(filterComposite_, DWT.DROP_DOWN);
		setMods(settings.mods);
		if (getSetting("startWithLastMod") == "true") {
			char[] s = getSetting("lastMod");
			int i = findString(settings.mods, s);
			if (i == -1) {
				modCombo_.add(s);
				modCombo_.select(modCombo_.getItemCount() - 1);
			}
			else {
				modCombo_.select(i);
			}
			settings.modName = s;
		}

		modCombo_.clearSelection();  // FIXME: doesn't seem to work
		modCombo_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				settings.modName = (cast(Combo) e.widget).getText();				
				serverTable.getTable.setFocus();
				if (!setActiveServerList(modName)) {
					if (common.useGslist)
						threadDispatcher.run(&getNewList);
					else
						threadDispatcher.run(&refreshList);
				}
				else {
					threadDispatcher.run(&switchToActiveMod);
				}
			}

			public void widgetDefaultSelected(SelectionEvent e)
			{
				char[] s = strip((cast(Combo) e.widget).getText());
				if (s.length == 0) {
					return;
				}

				int i = findString(mods, s);
				Combo combo = (cast(Combo) e.widget);
				if (i == -1) {
					combo.add(s);
					combo.select(combo.getItemCount() - 1);
				}
				else {
					combo.select(i);
				}
				settings.modName = s;
				serverTable.getTable.setFocus();
				if (!setActiveServerList(modName)) {
					if (common.useGslist)
						threadDispatcher.run(&getNewList);
					else
						threadDispatcher.run(&refreshList);
				}
				else {
					threadDispatcher.run(&switchToActiveMod);
				}				
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
   	ToolBar toolBar = new ToolBar(parent, DWT.HORIZONTAL);

   	ToolItem item = new ToolItem(toolBar, DWT.PUSH);
	item.setText("Get new list");
	item.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			threadDispatcher.run(&getNewList);
		}
	});

 	item = new ToolItem(toolBar, DWT.SEPARATOR);

	item = new ToolItem(toolBar, DWT.PUSH);
	item.setText("Refresh list");
	item.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			threadDispatcher.run(&refreshList);
		}
	});

	item = new ToolItem(toolBar, DWT.SEPARATOR);

	item = new ToolItem(toolBar, DWT.PUSH);
    item.setText("Monitor...");
    item.setEnabled(false);

   	item = new ToolItem(toolBar, DWT.SEPARATOR);

	item = new ToolItem(toolBar, DWT.PUSH);
	item.setText("Settings...");
	item.addSelectionListener(new class SelectionAdapter {
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

		if (serverThread && serverThread.getState() != Thread.TS.TERMINATED) {
			volatile abort = true;
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
