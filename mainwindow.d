/** The main window and related stuff. */

module mainwindow;

import tango.text.Util;
import Integer = tango.text.convert.Integer;

import dwt.DWT;
import dwt.custom.SashForm;
import dwt.dwthelper.ByteArrayInputStream;
import dwt.dwthelper.Runnable;
import dwt.events.SelectionAdapter;
import dwt.events.SelectionEvent;
import dwt.events.ShellAdapter;
import dwt.events.ShellEvent;
import dwt.graphics.Image;
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
import dwt.widgets.Shell;
import dwt.widgets.ToolBar;
import dwt.widgets.ToolItem;

import common;
import cvartable;
import dialogs;
import playertable;
import runtools;
import serveractions;
import serverlist;
import servertable;
import settings;
import threadmanager;


StatusBar statusBar;  ///
FilterBar filterBar;  ///
SashForm middleForm, rightForm;  ///
MainWindow mainWindow;  ///


///
class MainWindow
{
	/**
	 *  Initializes all of the gui.
	 */
	this()
	{
		shell_ = new Shell(Display.getDefault);
		shell_.setText(APPNAME ~ " " ~ VERSION);
		shell_.addShellListener(new MyShellListener);

		// restore saved size and state
		char[] size = getSetting("windowSize");
		int pos = locate(size, 'x');
		// FIXME: handle the case of 'x' not being found
		shell_.setSize(Integer.convert(size[0..pos]),
		        Integer.convert(size[pos+1..length]));
		if (getSetting("windowMaximized") == "true")
			shell_.setMaximized(true);

		shell_.setLayout(new GridLayout(2, false));


		// *********** MAIN WINDOW TOP ***************
		Composite topComposite = new Composite(shell_, DWT.NONE);
		auto topData = new GridData(DWT.FILL, DWT.CENTER, true, false, 2, 1);
		topComposite.setLayoutData(topData);
		version (none) {
			// This layout works better when the buttons have images.
			auto topLayout = new GridLayout(2, false);
			topLayout.horizontalSpacing = 50;
			topComposite.setLayout(topLayout);
		}
		else {
			topComposite.setLayout(new FillLayout);
		}

		ToolBar toolBar = createToolbar(topComposite);

		// filtering options
		filterBar = new FilterBar(topComposite);

		// ************** SERVER LIST, PLAYER LIST, CVARS LIST ***************
		middleForm = new SashForm(shell_, DWT.HORIZONTAL);
		auto middleData = new GridData(DWT.FILL, DWT.FILL, true, true);
		middleForm.setLayoutData(middleData);

		// server table widget
		serverTable = new ServerTable(middleForm);
		auto serverTableData = new GridData(DWT.LEFT, DWT.FILL, false, false);
		serverTable.getTable().setLayoutData(serverTableData);

		// parent for player and cvar tables
		rightForm = new SashForm(middleForm, DWT.VERTICAL);
		auto rightData = new GridData(DWT.FILL, DWT.FILL, true, true);
		rightForm.setLayoutData(rightData);

		rightForm.setLayout(new FillLayout(DWT.VERTICAL));

		int[] weights = parseIntegerSequence(getSessionState("middleWeights"));
		weights.length = 2;  // FIXME: use defaults instead?
		middleForm.setWeights(weights);;

		// player list
		playerTable = new PlayerTable(rightForm);

		// Server info, cvars, etc
		cvarTable = new CvarTable(rightForm);

		weights = parseIntegerSequence(getSessionState("rightWeights"));
		weights.length = 2;  // FIXME: use defaults instead?
		rightForm.setWeights(weights);


		// **************** STATUS BAR ******************************
		Composite statusComposite = new Composite(shell_, DWT.NONE);
		auto statusData = new GridData(DWT.FILL, DWT.CENTER, true, false);
		statusData.horizontalSpan = 2;
		statusComposite.setLayoutData(statusData);
		statusComposite.setLayout(new FillLayout);
		statusBar = new StatusBar(statusComposite);
		statusBar.setLeft(APPNAME ~ " is ready.");
	}

	Shell handle() { return shell_; }  ///

	void open() { shell_.open; }  ///

	void close() { shell_.close; }  ///

	bool maximized()       { return shell_.getMaximized; }  ///
	void maximized(bool v) { shell_.setMaximized(v); }  ///

	bool minimized()       { return shell_.getMinimized; }  ///
	void minimized(bool v) { shell_.setMinimized(v); }  ///

	Point size() { return shell_.getSize; }  ///
	
	void disposeAll() { serverTable.disposeAll(); }  ///


	///
	private class MyShellListener : ShellAdapter {
		/// Handler for the shellClosed event.
		void shellClosed(ShellEvent e)
		{
			bool stopped = serverTable.stopRefresh(false);
			assert(stopped);  // doesn't seem to be a problem in release builds
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
					log("Waiting for thread " ~ Integer.toString(i) ~ "...");
					t.join();
					log("    ...thread " ~ Integer.toString(i) ~ " done.");
				}
			}*/
		}
	}

	private {
		Shell shell_;
	}
}


///
class StatusBar
{
	///
	this(Composite parent)
	{
		leftLabel_ = new Label(parent, DWT.NONE);
		leftLabel_.setText(APPNAME ~ " is ready.");
	}

	void setLeft(char[] text)  ///
	{
		if (!leftLabel_.isDisposed) {
			leftLabel_.setText(text);
		}
	}

	void setDefaultStatus(uint totalServers, uint shownServers,
	                      uint noReply=0)  ///
	{
		char[] msg;
		char[] total = Integer.toString(totalServers);

		if (shownServers != totalServers) {
			msg = "Showing " ~ Integer.toString(shownServers) ~ " of " ~
			                                                total ~ " servers";
		}
		else {
			msg = "Showing " ~ total ~ " servers";
		}
		if (noReply > 0) {
			char[] n = Integer.toString(noReply);
			msg ~= " (" ~ n ~ " did not reply)";
		}

		setLeft(msg);
	}

private:
	Label leftLabel_;
}


///
class FilterBar : Composite
{
	///
	this(Composite parent)
	{
		super(parent, DWT.NONE);
		notEmptyButton_ = new Button(this, DWT.CHECK);
		notEmptyButton_.setText("Not empty");
		notEmptyButton_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				ServerList list = serverTable.serverList;
				bool notEmpty = notEmptyButton_.getSelection() != 0;

				if (notEmptyButton_.getSelection()) {
					hasHumansButton_.setSelection(false);
					list.setFilters(list.getFilters() & ~Filter.HAS_HUMANS);
				}

				if (notEmpty)
					list.setFilters(list.getFilters() | Filter.NOT_EMPTY);
				else
					list.setFilters(list.getFilters() & ~Filter.NOT_EMPTY);

				refreshServerTable();
			}
		});

		hasHumansButton_ = new Button(this, DWT.CHECK);
		hasHumansButton_.setText("Has humans");
		hasHumansButton_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				ServerList list = serverTable.serverList;
				bool hasHumans = hasHumansButton_.getSelection() != 0;

				if (hasHumans)
					list.setFilters(list.getFilters() | Filter.HAS_HUMANS);
				else
					list.setFilters(list.getFilters() & ~Filter.HAS_HUMANS);

				refreshServerTable();

			}
		});

		// Restore saved filter state
		Filter state = cast(Filter)Integer.convert(
		                                       getSessionState("filterState"));
		if (state & Filter.NOT_EMPTY)
			notEmptyButton_.setSelection(true);
		if (state & Filter.HAS_HUMANS)
			hasHumansButton_.setSelection(true);

		// game type selection
		/*Combo combo = new Combo(filterComposite_, DWT.READ_ONLY);
		combo.setItems(gametypes);
		combo.select(0);*/

		// game selection
		gamesCombo_ = new Combo(this, DWT.DROP_DOWN);
		setGames(settings.gameNames);
		if (getSetting("startWithLastMod") == "true") {
			char[] s = getSetting("lastMod");
			int i = findString(settings.gameNames, s);
			if (i == -1) {
				gamesCombo_.add(s);
				gamesCombo_.select(gamesCombo_.getItemCount() - 1);
				createGameConfig(s);
			}
			else {
				gamesCombo_.select(i);
			}
		}

		lastSelectedGame_ = gamesCombo_.getText();

		gamesCombo_.clearSelection();
		gamesCombo_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				serverTable.getTable.setFocus();
				lastSelectedGame_ = (cast(Combo)e.widget).getText();
				switchToGame(lastSelectedGame_);
			}

			public void widgetDefaultSelected(SelectionEvent e)
			{
				char[] s = trim((cast(Combo)e.widget).getText());
				if (s.length == 0) {
					return;
				}

				int i = findString(gameNames, s);
				Combo combo = (cast(Combo) e.widget);
				if (i == -1) {
					combo.add(s);
					combo.select(combo.getItemCount() - 1);
					createGameConfig(s);
				}
				else {
					combo.select(i);
				}

				serverTable.getTable.setFocus();
				lastSelectedGame_ = s;
				switchToGame(s);
			}
		});

		setLayout(new RowLayout);
	}


	/// The last selected game name.
	char[] selectedGame()
	{
		return lastSelectedGame_;
	}


	/// State of filter selection buttons.
	Filter filterState()
	{
		Filter f;
		
		if(notEmptyButton_.getSelection())
			f |= Filter.NOT_EMPTY;
		if (hasHumansButton_.getSelection())
			f |= Filter.HAS_HUMANS;

		return f;
	}


	/// Set the contents of the game name drop-down list.
	void setGames(char[][] list)
	{
		int sel, n, height;
		Point p;
		char[][] items;

		if (list is null)
			return;

		sel = gamesCombo_.getSelectionIndex();
		items = gamesCombo_.getItems();
		foreach (s; list) {
			if (findString(items, s) == -1) {
				gamesCombo_.add(s);
			}
		}
		n = gamesCombo_.getItemCount();
		if (n > 10) {
			n = 10;
		}
		p = gamesCombo_.getSize();
		height = gamesCombo_.getItemHeight() * n;
		// FIXME: setSize doesn't seem to do anything here :(
		gamesCombo_.setSize(p.x, height);

		if (sel == -1) {
			gamesCombo_.select(0);
		}
		else {
			gamesCombo_.select(sel);
		}
	}


	private void refreshServerTable()
	{
		Display.getDefault.asyncExec(new class Runnable {
			void run()
			{
				serverTable.fullRefresh;

				auto list = serverTable.serverList;
				synchronized (list)
				if (!serverTable.refreshInProgress) {
					statusBar.setDefaultStatus(list.length,
			                                   list.filteredLength);
				}
			}
		});
	}


private:
	Button notEmptyButton_, hasHumansButton_;
	char[] lastSelectedGame_;
	Combo gamesCombo_;
}


ToolBar createToolbar(Composite parent) ///
{
	auto toolBar = new ToolBar(parent, DWT.HORIZONTAL);

	auto button1 = new ToolItem(toolBar, DWT.PUSH);
	button1.setText("Get new list");
	//button1.setImage(loadImage!("res/32px-Crystal_Clear_action_down.png"));
	button1.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			threadManager.run(&getNewList);
		}
	});

	new ToolItem(toolBar, DWT.SEPARATOR);

	ToolItem button2 = new ToolItem(toolBar, DWT.PUSH);
	button2.setText("Refresh list");
	//button2.setImage(loadImage!("res/32px-Crystal_Clear_action_reload.png"));
	button2.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			threadManager.run(&refreshList);
		}
	});

	new ToolItem(toolBar, DWT.SEPARATOR);

	auto button3 = new ToolItem(toolBar, DWT.PUSH);
	button3.setText("Specify...");
	//button3.setImage(loadImage!("res/32px-Crystal_Clear_action_edit_add.png"));
	button3.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			auto dialog = new SpecifyServerDialog(mainWindow.handle);
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
			startMonitor(mainWindow.handle);
			//SettingsDialog dialog = new SettingsDialog(mainWindow.handle);
			/*if (dialog.open() == DWT.OK)
				saveSettings();*/
		}
	});
+/
	new ToolItem(toolBar, DWT.SEPARATOR);

	auto button5 = new ToolItem(toolBar, DWT.PUSH);
	button5.setText("Settings...");
	//button5.setImage(loadImage!("res/32px-Crystal_Clear_action_configure.png"));
	button5.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			SettingsDialog dialog = new SettingsDialog(mainWindow.handle);
			if (dialog.open() == DWT.OK)
				saveSettings();
		}
	});

	return toolBar;
}


private Image loadImage(char[] name)()
{
	return _loadImage(cast(byte[])import(name));
}


private Image _loadImage(byte[] data)
{
	return new Image(Display.getDefault, new ByteArrayInputStream(data));
}
