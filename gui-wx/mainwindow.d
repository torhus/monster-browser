module gui.mainwindow;

import std.conv : toInt;
debug import std.stdio : writefln;
import std.string;
import std.thread;

//import wx.wx : Frame, App, MenuIDs, Point, Size, Event, MessageBox, Dialog;
import wx.wx;

import common;
import main;
import runtools;
import serveractions;
import serverlist;
import settings;
//import gui.cvartable;
//import gui.dialogs;
//import gui.playertable;
import gui.servertable;


FilterBar filterBar;
StatusBar statusBar;

//package Shell mainShell;

private {
	Minimal theApp;
	Frame mainFrame;
	Object execMutex;
	Thread mainThread;

	void delegate() initDelegate;	
	void delegate() cleanupDelegate;
}


///
class MainWindow
{
	this()
	{
		execMutex = new Object;
		mainThread = Thread.getThis();
		
		//info("1");
		theApp = new Minimal();
		//info("2");

/+
		// restore saved size and state
		char[] size = getSetting("windowSize");
		int pos = find(size, 'x');
		// FIXME: ArrayBoundsError if 'x' wasn't found
		mainShell.setSize(toInt(size[0..pos]), toInt(size[pos+1..length]));
		if (getSetting("windowMaximized") == "true") {
			mainShell.setMaximized(true);
		}

		GridLayout gridLayout = new GridLayout();
		gridLayout.numColumns = 2;
		mainShell.setLayout(gridLayout);


		// *********** MAIN WINDOW TOP ***************
		Composite topComposite = new Composite(mainShell, DWT.NONE);
		GridData gridData = new GridData(GridData.HORIZONTAL_ALIGN_FILL |
		                                 GridData.GRAB_HORIZONTAL);
		gridData.horizontalSpan = 2;
		topComposite.setLayoutData(gridData);
		topComposite.setLayout(new FillLayout(DWT.HORIZONTAL));

		createToolbar(topComposite);
+/
		// filtering options
		filterBar = new FilterBar(/*topComposite*/);
/+

		// ************** SERVER LIST, PLAYER LIST, CVARS LIST ***************
		SashForm middleForm = new SashForm(mainShell, DWT.HORIZONTAL);
		gridData = new GridData(GridData.FILL_BOTH);
		middleForm.setLayoutData(gridData);
+/
		// server table widget
		//serverTable = new ServerTable(/*middleForm*/);
/+		gridData = new GridData(GridData.FILL_VERTICAL);
		// FIXME: doesn't work
		//gridData.widthHint = 610;  // FIXME: automate using table's info
		serverTable.getTable().setLayoutData(gridData);
+/
		// has to be instantied after the table
		//setActiveServerList(activeMod.name);
/+
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
		Composite statusComposite = new Composite(mainShell, DWT.NONE);
		gridData = new GridData(GridData.HORIZONTAL_ALIGN_FILL |
		                        GridData.GRAB_HORIZONTAL);
		gridData.horizontalSpan = 2;
		statusComposite.setLayoutData(gridData);
		statusComposite.setLayout(new FillLayout(DWT.HORIZONTAL));
+/

		// **********************************************************
/+
		mainShell.addKeyListener(new class KeyAdapter {
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

		serverTable.getTable.setFocus();
		mainShell.open();
+/
	}

	/**
	 * dg will be called after the main window is opened, but before entering
	 * the event loop.
	 */
	void setInitDelegate(void delegate() dg) { initDelegate = dg; }


	/**
	 * dg will be called when the main window is about to be closed.
	 */
	void setCleanupDelegate(void delegate() dg)
	{/+
		assert(mainShell !is null);

		mainShell.addShellListener(new class(handler) ShellAdapter {
			typeof(handler) handler_;

			this(typeof(handler) handler) { handler_ = handler; }

			public void shellClosed(ShellEvent e) { handler_(); }
		});+/

		cleanupDelegate = dg;
	}

	/**
	 * Run the GUI library's event loop.
	 * 
	 * Basic order of actions:
	 * 1. Create and show the main window
	 * 2. Call the delegate set by setInitDelegate
	 * 3. Run the event loop until the main window is closed
	 * 4. Call the delegate set by setCleanupDelegate
	 * 5. Destroy the main window and do all GUI-related cleanup 
	 */
	void mainLoop()
	{
		theApp.Run();
	}

/+	int isDisposed() { return mainShell.isDisposed(); }+/

	int minimized() { return 0; }
	void minimized(bool v) { /+mainShell.setMinimized(v);+/ }

	int maximized() { return 0; }

	SizeStruct size()
	{
		auto size = mainFrame.size();
		return SizeStruct(size.Width, size.Height);
	}
}


private class MyFrame : Frame
{
	enum Cmd
	{
		Quit = MenuIDs.wxID_EXIT,
	}

	//---------------------------------------------------------------------

	public this(string title, Point pos, Size size)
	{
		super(title, pos, size);

		// Set the window icon
		icon = new Icon("mondrian.png");

		// ************** SERVER LIST, PLAYER LIST, CVARS LIST ***************
		// server table widget
		serverTable = new ServerTable(this);

		/*CreateStatusBar(2);
		StatusText = "Welcome to wxWidgets!";*/

		.statusBar = new StatusBar(this);
		.statusBar.setLeft(APPNAME ~ " is ready.");

		// Set up the event table
		EVT_MENU(Cmd.Quit, &OnQuit);

		// has to be instantied after the ServerTable
		setActiveServerList(activeMod.name);
	}

	//---------------------------------------------------------------------

	public void OnQuit(Object sender, Event e)
	{
		cleanupDelegate();
		Close();
	}

	//---------------------------------------------------------------------

	public void OnDialog(Object sender, Event e)
	{
        Dialog dialog = new Dialog( this, -1, "Test dialog", Point(50,50), Size(450,340) );
        BoxSizer main_sizer = new BoxSizer( Orientation.wxVERTICAL );

        StaticBoxSizer top_sizer = new StaticBoxSizer(
                                        new StaticBox( dialog, -1, "Bitmaps" ),
                                        Orientation.wxHORIZONTAL );
        main_sizer.Add( top_sizer, 0, Direction.wxALL, 5 );

        BitmapButton bb = new BitmapButton( dialog, -1, new Bitmap("mondrian.png") );
        top_sizer.Add( bb, 0, Direction.wxALL, 10 );

        StaticBitmap sb = new StaticBitmap( dialog, -1, new Bitmap("mondrian.png") );
        top_sizer.Add( sb, 0, Direction.wxALL, 10 );

        Button button = new Button( dialog, 5100, "OK" );
        main_sizer.Add( button, 0, Direction.wxALL|Alignment.wxALIGN_CENTER, 5 );

        dialog.SetSizer( main_sizer, true );
        main_sizer.Fit( dialog );
        main_sizer.SetSizeHints( dialog );

        dialog.CentreOnParent();
        dialog.ShowModal();
	}

	//---------------------------------------------------------------------

	public void OnAbout(Object sender, Event e)
	{
		string msg = "This is the About dialog of the minimal sample.\nWelcome to " ~ wxVERSION_STRING;
		MessageBox(this, msg, "About Minimal", Dialog.wxOK | Dialog.wxICON_INFORMATION);
	}

	//---------------------------------------------------------------------
}

public class Minimal : App
{
	//---------------------------------------------------------------------

	public override bool OnInit()
	{
		mainFrame = new MyFrame(APPNAME ~ " " ~ VERSION,
		                            Point(50, 50), Size(836, 594));
		mainFrame.Show(true);
		
		initDelegate();

		return true;
	}

	//---------------------------------------------------------------------

	/+static void Main()
	{
		Minimal app = new Minimal();
		app.Run();
	}+/

	//---------------------------------------------------------------------
}


void createToolbar(/*Composite parent*/)
{
/+	auto toolBar = new ToolBar(parent, DWT.HORIZONTAL);

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
			auto dialog = new SpecifyServerDialog(mainShell);
			dialog.open();
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
			startMonitor(mainShell);
			//SettingsDialog dialog = new SettingsDialog(mainShell);
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
			SettingsDialog dialog = new SettingsDialog(mainShell);
			if (dialog.open() == DWT.OK)
				saveSettings();
		}
	});
+/
	//return toolBar;
}


///
class StatusBar
{

	this(Frame parent)
	{
		parent_ = parent;
		parent_.CreateStatusBar(1);
		parent_.StatusText = APPNAME ~ " is ready.";
	}

	void setLeft(char[] text)
	{/+
		if (!leftLabel_.isDisposed) {
			leftLabel_.setText(text);
		}+/
		debug writefln("setLeft 1");
		synchronized (execMutex) {
			if (!mainThread.isSelf())
				MutexGuiEnter();
			parent_.StatusText = text;
			if (!mainThread.isSelf())
				MutexGuiLeave();
		}
		debug writefln("setLeft 2");
	}

	void setDefaultStatus(size_t totalServers, size_t shownServers)
	{
		if (shownServers != totalServers) {
			setLeft("Showing " ~
			         .toString(shownServers) ~ " of " ~
			         .toString(totalServers) ~ " servers");
		}
		else {
			setLeft("Showing " ~ .toString(totalServers) ~
			         " servers");
		}
	}

private:
	Frame parent_;

}


///
class FilterBar// : Composite
{
/+	this(Composite parent)
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
				char[] s = strip((cast(Combo) e.widget).getText());
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
+/
}


///
void asyncExec(Object o, void delegate(Object) dg)
{
	debug (exec) writefln("asyncExec starting");
	bool isMain = mainThread.isSelf();
	
	// FIXME: use wxIdleEvent or wxUpdateUIEvent?

	synchronized (execMutex) {
		if (!isMain)
			MutexGuiEnter();
		dg(o);
		if (!isMain)
			MutexGuiLeave();
	}
	debug (exec) writefln("asyncExec returning");
}


///
void syncExec(Object o, void delegate(Object) dg)
{
	debug (exec) writefln("syncExec starting");
	bool isMain = mainThread.isSelf();

	synchronized (execMutex) {
		if (!isMain)
			MutexGuiEnter();
		dg(o);
		if (!isMain)
			MutexGuiLeave();
	}
	debug (exec) writefln("syncExec returning");
}
