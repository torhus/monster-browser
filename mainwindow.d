/** The main window and related stuff. */

module mainwindow;

version = icons;

import tango.text.Util;
import Integer = tango.text.convert.Integer;
import tango.text.convert.Format;

import dwt.DWT;
import dwt.custom.SashForm;
import dwt.dwthelper.ByteArrayInputStream;
import dwt.dwthelper.Runnable;
import dwt.events.SelectionAdapter;
import dwt.events.SelectionEvent;
import dwt.events.ShellAdapter;
import dwt.events.ShellEvent;
version (icons)
	import dwt.graphics.Image;
import dwt.graphics.Point;
import dwt.graphics.Rectangle;
import dwt.layout.FillLayout;
import dwt.layout.GridData;
import dwt.layout.GridLayout;
import dwt.layout.RowLayout;
import dwt.widgets.Button;
import dwt.widgets.Combo;
import dwt.widgets.Composite;
import dwt.widgets.Display;
version (icons)
	import dwt.widgets.Group;
import dwt.widgets.Label;
import dwt.widgets.ProgressBar;
import dwt.widgets.Shell;
import dwt.widgets.ToolBar;
import dwt.widgets.ToolItem;

import common;
import cvartable;
import dialogs;
import playertable;
import runtools : killServerBrowser;
import serveractions;
import serverlist;
import servertable;
import settings;
import threadmanager;


StatusBar statusBar;  ///
FilterBar filterBar;  ///
MainWindow mainWindow;  ///
/// The close() method will be called for these shells, before everything is
/// disposed of.
Shell[] subWindows;

// Image objects that needs to be disposed of before shut down.
version (icons)
	private Image[] imageList;


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

		// restore window size and state
		char[] size = getSetting("windowSize");
		uint x = locate(size, 'x');
		if (x < size.length)
			shell_.setSize(Integer.convert(size[0..x]),
			               Integer.convert(size[x+1..length]));
		if (getSetting("windowMaximized") == "true")
			shell_.setMaximized(true);

		// restore window position
		int[] oldres = parseIntList(getSessionState("resolution"), 2);
		Rectangle res = Display.getDefault().getBounds();
		if (oldres[0] == res.width && oldres[1] == res.height) {
			int[] pos = parseIntList(getSessionState("windowPosition"), 2);
			shell_.setLocation(pos[0], pos[1]);
		}

		auto layout = new GridLayout(2, false);
		layout.horizontalSpacing = 0;
		shell_.setLayout(layout);


		// *********** MAIN WINDOW TOP ***************
		Composite topComposite = new Composite(shell_, DWT.NONE);
		auto topData = new GridData(DWT.FILL, DWT.CENTER, true, false, 2, 1);
		topComposite.setLayoutData(topData);
		version (icons) {
			// This layout works better when the buttons have images.
			auto topLayout = new GridLayout(2, false);
			topLayout.marginHeight = 0;
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
		middleForm_ = new SashForm(shell_, DWT.HORIZONTAL);
		auto middleData = new GridData(DWT.FILL, DWT.FILL, true, true);
		middleForm_.setLayoutData(middleData);

		// server table widget
		serverTable = new ServerTable(middleForm_);
		auto serverTableData = new GridData(DWT.LEFT, DWT.FILL, false, false);
		serverTable.getTable().setLayoutData(serverTableData);

		// parent for player and cvar tables
		rightForm_ = new SashForm(middleForm_, DWT.VERTICAL);
		auto rightData = new GridData(DWT.FILL, DWT.FILL, true, true);
		rightForm_.setLayoutData(rightData);

		rightForm_.setLayout(new FillLayout(DWT.VERTICAL));

		int[] weights = parseIntList(getSessionState("middleWeights"), 2);
		middleForm_.setWeights(weights);

		// player list
		playerTable = new PlayerTable(rightForm_);

		// Server info, cvars, etc
		cvarTable = new CvarTable(rightForm_);

		weights = parseIntList(getSessionState("rightWeights"), 2);
		rightForm_.setWeights(weights);


		// **************** STATUS BAR ******************************
		statusBar = new StatusBar(shell_);
		auto statusData = new GridData(DWT.FILL, DWT.CENTER, true, false);
		statusData.horizontalSpan = 2;
		statusBar.setLayoutData(statusData);
		statusBar.setLeft(APPNAME ~ " is ready.");
	}

	Shell handle() { return shell_; }  ///

	void open() { shell_.open; }  ///

	void close() { shell_.close; }  ///

	bool minimized()       { return shell_.getMinimized; }  ///
	void minimized(bool v) { shell_.setMinimized(v); }  ///


	///
	void disposeAll()
	{
		serverTable.disposeAll();
		version (icons)
			foreach (img; imageList)
				img.dispose();
	}


	///  Saves the session state.
	private void saveState()
	{
		serverTable.saveState();

		if (shell_.getMaximized()) {
			setSetting("windowMaximized", "true");
		}
		else {
			setSetting("windowMaximized", "false");

			Rectangle res = Display.getDefault().getBounds();
			setSessionState("resolution", toCsv([res.width, res.height]));

			Point pos = shell_.getLocation();
			setSessionState("windowPosition", toCsv([pos.x, pos.y]));

			char[] width  = Integer.toString(shell_.getSize().x);
			char[] height = Integer.toString(shell_.getSize().y);
			setSetting("windowSize", width ~ "x" ~ height);
		}

		setSessionState("middleWeights", toCsv(middleForm_.getWeights()));
		setSessionState("rightWeights", toCsv(rightForm_.getWeights()));

		filterBar.saveState();
	}


	/// Handles the shell close event.
	private class MyShellListener : ShellAdapter {
		void shellClosed(ShellEvent e)  ///
		{
			serverTable.stopRefresh(false);
			threadManager.shutdown();
			statusBar.setLeft("Exiting...");
			log("Shutting down...");
			killServerBrowser();
			foreach (shell; subWindows) {
				if (!shell.isDisposed())
					shell.close();
			}
			saveState();
		}
	}

	private {
		Shell shell_;
		SashForm middleForm_, rightForm_;
	}
}


///
class StatusBar : Composite
{
	///
	this(Composite parent)
	{
		super(parent, DWT.NONE);
		auto layout = new GridLayout(7, false);
		layout.marginWidth = 2;
		layout.marginHeight = 0;
		setLayout(layout);

		progressLabel_ = new Label(this, DWT.NONE);
		progressLabel_.setVisible(false);

		progressBar_ = createProgressBar(false);
		progressBar_.setVisible(false);

		// an empty Label to push the rest of the labels to the far right of
		// the status bar
		auto empty = new Label(this, DWT.NONE);
		auto emptyData = new GridData(DWT.CENTER, DWT.CENTER, true, false);
		empty.setLayoutData(emptyData);

		int sepHeight = progressLabel_.computeSize(DWT.DEFAULT, DWT.DEFAULT).y;

		createSeparator(sepHeight);

		serverLabel_ = new Label(this, DWT.NONE);
		auto serverData = new GridData(DWT.CENTER, DWT.CENTER, false, false);
		serverLabel_.setLayoutData(serverData);

		createSeparator(sepHeight);

		playerLabel_ = new Label(this, DWT.NONE);
		auto playerData = new GridData(DWT.CENTER, DWT.CENTER, false, false);
		playerLabel_.setLayoutData(playerData);
	}

	void setLeft(char[] text)  ///
	{
		if (progressLabel_.isDisposed())
			return;
		progressLabel_.setText(text);
		layout();
	}

	void setDefaultStatus(uint totalServers, uint shownServers,
	                                            uint noReply, uint humans)  ///
	{
		if (isDisposed())
			return;

		setRedraw(false);

		char[] fmt = "{1} servers";

		/*if (noReply > 0)
			fmt ~= " ({2} did not reply)";*/

		char[] s = Format(fmt, totalServers, shownServers, noReply);
		serverLabel_.setText(s);

		playerLabel_.setText(Format("{} human players", humans));

		layout();
		setRedraw(true);
	}


	void showProgress(in char[] label, bool indeterminate=false)
	{
		if (isDisposed())
			return;

		assert(progressBar_ !is null);

		if ((progressBar_.getStyle() & DWT.INDETERMINATE) != indeterminate) {
			// remove the old ProgressBar, insert a new one
			progressBar_.dispose();
			progressBar_ = createProgressBar(indeterminate);
			progressBar_.moveBelow(progressLabel_);
			layout();
		}
		setProgressLabel(label);
		progressBar_.setSelection(0);
		progressLabel_.setVisible(true);
		progressBar_.setVisible(true);
	}


	void hideProgress()
	{
		if (isDisposed())
			return;
		progressLabel_.setText("Ready");
		progressBar_.setVisible(false);
	}


	private void setProgressLabel(in char[] text)
	{
		setLeft(text ~ "...");
	}


	void setProgress(int total, int current)
	{
		if (progressBar_.isDisposed())
			return;
		progressBar_.setMaximum(total);
		progressBar_.setSelection(current);
	}


	private ProgressBar createProgressBar(bool indeterminate)
	{
		auto pb = new ProgressBar(this, indeterminate ?
		                                         DWT.INDETERMINATE : DWT.NONE);
		auto data = new GridData;
		data.widthHint = 100;
		pb.setLayoutData(data);
		return pb;
	}


	private Label createSeparator(int height)
	{
		auto sep = new Label(this, DWT.SEPARATOR);
		auto sepData = new GridData(DWT.CENTER, DWT.CENTER, false, false);
		sepData.heightHint = height;
		//sepData.widthHint = 5;
		sep.setLayoutData(sepData);
		return sep;
	}


private:
	Label serverLabel_;
	Label playerLabel_;
	Label progressLabel_;
	ProgressBar progressBar_;
}


version (icons)
	alias Group FilterSuper;
else
	alias Composite FilterSuper;

///
class FilterBar : FilterSuper
{
	///
	this(Composite parent)
	{
		version (icons) {
			super(parent, DWT.SHADOW_NONE);
			setText("Filters and Game Selection");
			setLayoutData(new GridData);
		}
		else {
			super(parent, DWT.NONE);
		}

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
				if (s.length == 0)
					return;

				Combo combo = cast(Combo)e.widget;
				int i = findString(combo.getItems(), s);
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

		version (icons) {
			auto layout = new RowLayout;
			layout.fill = true;
			layout.marginHeight = 2;
			layout.marginWidth = 2;
			setLayout(layout);
		}
		else {
			auto layout = new RowLayout;
			layout.fill = true;
			setLayout(layout);
		}
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


	///  Saves the session state.
	private void saveState()
	{
		setSetting("lastMod", lastSelectedGame_);
		setSessionState("filterState", Integer.toString(filterState));
	}


	private void refreshServerTable()
	{
		Display.getDefault.asyncExec(new class Runnable {
			void run() { serverTable.fullRefresh; }
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
	button1.setText("Check for New");
	version (icons)
		button1.setImage(loadImage!("icons/box_download_32.png"));
	button1.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			threadManager.run(&getNewList);
		}
	});

	new ToolItem(toolBar, DWT.SEPARATOR);
	ToolItem button2 = new ToolItem(toolBar, DWT.PUSH);
	button2.setText("Refresh All");
	version (icons)
		button2.setImage(loadImage!("icons/refresh_32.png"));
	button2.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			threadManager.run(&refreshList);
		}
	});

	new ToolItem(toolBar, DWT.SEPARATOR);

	auto button3 = new ToolItem(toolBar, DWT.PUSH);
	button3.setText("    Add...  ");
	version (icons)
		button3.setImage(loadImage!("icons/add_32.png"));
	button3.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			auto dialog = new SpecifyServerDialog(mainWindow.handle);
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
			startMonitor(mainWindow.handle);
		}
	});
+/
	new ToolItem(toolBar, DWT.SEPARATOR);

	auto button5 = new ToolItem(toolBar, DWT.PUSH);
	button5.setText("Settings...");
	version (icons)
		button5.setImage(loadImage!("icons/spanner_32.png"));
	button5.addSelectionListener(new class SelectionAdapter {
		public void widgetSelected(SelectionEvent e)
		{
			SettingsDialog dialog = new SettingsDialog(mainWindow.handle);
			if (dialog.open())
				saveSettings();
		}
	});

	return toolBar;
}


version (icons) {
	private Image loadImage(char[] name)()
	{
		return _loadImage(cast(byte[])import(name));
	}

	private Image _loadImage(byte[] data)
	{
		Image img = new Image(Display.getDefault, new ByteArrayInputStream(data));
		imageList ~= img;
		return img;
	}
}
