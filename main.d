module main;

import std.string;
//import std.stdio;
import std.thread;
//import std.conv;

//import tango.core.Thread;
import tango.io.Console;
import tango.stdc.stdio;
import Util = tango.text.Util;
import Integer = tango.text.convert.Integer;

import dejavu.lang.String;
import dejavu.lang.JArray;
import dejavu.lang.JObject;

import org.eclipse.swt.StaticCtorsSwt;
import org.eclipse.swt.SWT;
import org.eclipse.swt.custom.SashForm;
import org.eclipse.swt.events.KeyAdapter;
import org.eclipse.swt.events.KeyEvent;
import org.eclipse.swt.events.SelectionAdapter;
import org.eclipse.swt.events.SelectionEvent;
import org.eclipse.swt.events.ShellAdapter;
import org.eclipse.swt.events.ShellEvent;
import org.eclipse.swt.graphics.Point;
import org.eclipse.swt.layout.FillLayout;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.layout.GridLayout;
import org.eclipse.swt.layout.RowLayout;
import org.eclipse.swt.widgets.Button;
import org.eclipse.swt.widgets.Combo;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.MessageBox;
import org.eclipse.swt.widgets.Shell;
//import org.eclipse.swt.widgets.Table;
import org.eclipse.swt.widgets.ToolBar;
import org.eclipse.swt.widgets.ToolItem;

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


Display display;
ServerTable serverTable;
ServerList serverList;
PlayerTable playerTable;
CvarTable cvarTable;
StatusBar statusBar;
FilterBar filterBar;
Shell mainWindow;
Thread serverThread;
ThreadDispatcher threadDispatcher;


// SWT won't link without this
extern(C) ubyte[] resources_getDataById( char[] aId ){
    return null;
}


void main() {
	version (NO_STDOUT) {
		freopen("STDOUT.TXT", "w", stdout);
	}

	try	{
		// SWT initialization
		callAllStaticCtors();

		loadSettings();

		display = Display.getDefault();
		mainWindow = new Shell(display);
		mainWindow.setText(String.fromUtf8(APPNAME ~ " " ~ VERSION));

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
		try {
			char[] size = getSetting("windowSize");
			int pos = Util.locate(size, 'x');
			mainWindow.setSize(Integer.toInt(size[0..pos]),
			                   Integer.toInt(size[pos+1..length]));
		}
		catch (Exception e) {
			log("Error parsing windowSize setting: " ~ e.toUtf8());
		}

		if (getSetting("windowMaximized") == "true") {
			mainWindow.setMaximized(true);
		}

		GridLayout gridLayout = new GridLayout();
		gridLayout.numColumns = 2;
		mainWindow.setLayout(gridLayout);


		// *********** MAIN WINDOW TOP ***************
		Composite topComposite = new Composite(mainWindow, SWT.NONE);
		GridData gridData = new GridData(GridData.HORIZONTAL_ALIGN_FILL |
		                                 GridData.GRAB_HORIZONTAL);
		gridData.horizontalSpan = 2;
		topComposite.setLayoutData(gridData);
		topComposite.setLayout(new FillLayout(SWT.HORIZONTAL));

		ToolBar toolBar = createToolbar(topComposite);

		// filtering options
		filterBar = new FilterBar(topComposite);


		// ************** SERVER LIST, PLAYER LIST, CVARS LIST ***************
		SashForm middleForm = new SashForm(mainWindow, SWT.HORIZONTAL);
		gridData = new GridData(GridData.FILL_BOTH);
		middleForm.setLayoutData(gridData);

		// server table widget
		serverTable = new ServerTable(middleForm);
		gridData = new GridData(GridData.FILL_VERTICAL);
		// FIXME: doesn't work
		//gridData.widthHint = 610;  // FIXME: automate using table's info
		serverTable.getTable().setLayoutData(gridData);

		// global server list array, has to be instantied after the table
		serverList = new ServerList;

		// parent for player and cvar tables
		SashForm rightForm = new SashForm(middleForm, SWT.VERTICAL);
		gridData = new GridData(GridData.FILL_BOTH);
		rightForm.setLayoutData(gridData);

		FillLayout rightLayout = new FillLayout(SWT.VERTICAL);
		rightForm.setLayout(rightLayout);

		// distribution of space between the tables
		middleForm.setWeights(new JArrayInt([16, 5]));

		// player list
		playerTable = new PlayerTable(rightForm);
		gridData = new GridData();
		playerTable.getTable().setLayoutData(gridData);

		// Server info, cvars, etc
		cvarTable = new CvarTable(rightForm);
		gridData = new GridData();
		cvarTable.getTable().setLayoutData(gridData);

		// **************** STATUS BAR ******************************
		Composite statusComposite = new Composite(mainWindow, SWT.NONE);
		gridData = new GridData(GridData.HORIZONTAL_ALIGN_FILL |
		                        GridData.GRAB_HORIZONTAL);
		gridData.horizontalSpan = 2;
		statusComposite.setLayoutData(gridData);
		statusComposite.setLayout(new FillLayout(SWT.HORIZONTAL));
		statusBar = new StatusBar(statusComposite);
		statusBar.setLeft(APPNAME ~ " is ready.");

		// **********************************************************

		/*mainWindow.addKeyListener(new class KeyAdapter {
			public void keyPressed (KeyEvent e)
			{
				//FIXME: this function never gets called
				debug Cout("Keypressed");
				switch (e.keyCode) {
					case SWT.F4:
						threadDispatcher.run(&getNewList);
						break;
					case SWT.F5:
						threadDispatcher.run(&refreshList);
						break;
					default:
						break;
				}
			}
		});*/

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
		logx(__FILE__, __LINE__, e);
		//MessageBox.showMsg(e.classinfo.name ~ "\n" ~ e.toString());
		error(e.classinfo.name ~ "\n" ~ e.toString());
	}
}


class StatusBar
{

	this(Composite parent)
	{
		leftLabel_ = new Label(parent, SWT.NONE);
		leftLabel_.setText(String.fromUtf8(APPNAME ~ " is ready."));
	}

	void setLeft(char[] text)
	{
		if (!leftLabel_.isDisposed) {
			leftLabel_.setText(String.fromUtf8(text));
		}
	}

	void setDefaultStatus(size_t totalServers, size_t shownServers)
	{
		if (shownServers != totalServers) {
			setLeft("Showing " ~
			         Integer.toUtf8(shownServers) ~ " of " ~
			         Integer.toUtf8(totalServers) ~ " servers");
		}
		else {
			setLeft("Showing " ~ Integer.toUtf8(totalServers) ~
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
		filterComposite_ = new Composite(parent, SWT.NONE);
		button1_ = new Button(filterComposite_, SWT.CHECK);
		button1_.setText(new String("Not empty"));
		button1_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				if (button1_.getSelection()) {
					button2_.setSelection(false);
					serverList.filterHasHumans(false);
				}
				serverList.filterNotEmpty(button1_.getSelection() != 0);
			}
		});

		button2_ = new Button(filterComposite_, SWT.CHECK);
		button2_.setText(new String("Has humans"));
		button2_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				serverList.filterHasHumans(cast(bool) (cast(Button) e.widget).
				                                               getSelection());
			}
		});

		// game type selection
		/*Combo combo = new Combo(filterComposite_, SWT.READ_ONLY);
		combo.setItems(gametypes);
		combo.select(0);*/

		// mod selection
		modCombo_ = new Combo(filterComposite_, SWT.DROP_DOWN);
		setMods(settings.mods);
		if (getSetting("startWithLastMod") == "true") {
			char[] s = getSetting("lastMod");
			int i = findString(settings.mods, s);
			if (i == -1) {
				modCombo_.add(String.fromUtf8(s));
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
				settings.modName = (cast(Combo) e.widget).getText().toUtf8();
				serverTable.getTable.setFocus();
				threadDispatcher.run(&getNewList);
			}

			public void widgetDefaultSelected(SelectionEvent e)
			{
				char[] s = strip((cast(Combo) e.widget).getText().toUtf8());
				if (s.length == 0) {
					return;
				}

				int i = findString(mods, s);
				Combo combo = (cast(Combo) e.widget);
				if (i == -1) {
					combo.add(String.fromUtf8(s));
					combo.select(combo.getItemCount() - 1);
				}
				else {
					combo.select(i);
				}
				settings.modName = s;
				serverTable.getTable.setFocus();
				threadDispatcher.run(&getNewList);
			}
		});

		filterComposite_.setLayout(new RowLayout(SWT.HORIZONTAL));
	}

	void setMods(char[][] list)
	{
		int sel, n, height;
		Point p;
		//char[][] items;
		JObject[] items;

		if (list is null)
			return;

		sel = modCombo_.getSelectionIndex();
		items = modCombo_.getItems().toObjectArray();
		foreach (s; list) {
			String js = String.fromUtf8(s);
			foreach (JObject item; items) {
				if (js == cast(String)item)
					continue;
			}
			//if (findString(items, s) == -1)
			modCombo_.add(js);
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
   	ToolBar toolBar = new ToolBar(parent, SWT.HORIZONTAL);

   	ToolItem item = new ToolItem(toolBar, SWT.PUSH);
	item.setText(new String("Get new list"w));
	item.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			threadDispatcher.run(&getNewList);
		}
	});

 	item = new ToolItem(toolBar, SWT.SEPARATOR);

	item = new ToolItem(toolBar, SWT.PUSH);
	item.setText(new String("Refresh list"));
	item.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			threadDispatcher.run(&refreshList);
		}
	});

	item = new ToolItem(toolBar, SWT.SEPARATOR);

	item = new ToolItem(toolBar, SWT.PUSH);
    item.setText(new String("Monitor..."));
    item.setEnabled(false);

   	item = new ToolItem(toolBar, SWT.SEPARATOR);

	item = new ToolItem(toolBar, SWT.PUSH);
	item.setText(new String("Settings..."));
	item.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			SettingsDialog dialog = new SettingsDialog(mainWindow);
			if (dialog.open() == SWT.OK)
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
			debug Cout("ThreadDispatcher.dispatch: Killing server browser...");
			bool success = killServerBrowser();

			debug if (!success)
				Cout("killServerBrowser() failed.");
			else
				Cout("killServerBrowser() succeeded.");


			fp_();
			fp_ = null;
		}
	}

	private void function() fp_ = null;
}
