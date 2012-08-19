/** The main window, including tool bar and status bar. */

module mainwindow;

import tango.math.Math : max;
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
import dwt.widgets.Group;
import dwt.widgets.Label;
import dwt.widgets.Menu;
import dwt.widgets.MenuItem;
import dwt.widgets.ProgressBar;
import dwt.widgets.Shell;
import dwt.widgets.ToolBar;
import dwt.widgets.ToolItem;

import actions;
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

// For the taskbar progress display feature of Windows 7 and later
version (Windows) {
	import mswindows.taskbarprogress;
}

StatusBar statusBar;  ///
FilterBar filterBar;  ///
MainWindow mainWindow;  ///
/// The close() method will be called for these shells, before everything is
/// disposed of.
Shell[] subWindows;

// Image objects that needs to be disposed of before shut down.
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
		shell_.setText(APPNAME ~ " " ~ getVersionString());
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

		// This layout works better when the buttons have images.
		auto topLayout = new GridLayout(2, false);
		topLayout.marginHeight = 0;
		topLayout.horizontalSpacing = 50;
		topComposite.setLayout(topLayout);

		ToolBar toolBar = (new ToolBarWrapper(shell_, topComposite)).
		                                                getToolBar();

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
			log("Shutting down...");
			statusBar.setLeft("Exiting...");
			stopAction();
			threadManager.shutDown();
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

		version (Windows) {
			initTaskbarProgress();
		}
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

		char[] fmt;

		if (shownServers != totalServers)
			fmt = "{1} of {0} servers";
		else
			fmt = "{1} servers";

		/*if (noReply > 0)
			fmt ~= " ({2} did not reply)";*/

		char[] s = Format(fmt, totalServers, shownServers, noReply);
		serverLabel_.setText(s);

		playerLabel_.setText(Format("{} human players", humans));

		layout();
		setRedraw(true);
	}


	void showProgress(in char[] label, bool indeterminate=false, int total=0,
	                                                           int progress=0)
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

		version (Windows) if (tbProgress_) {
			if (indeterminate) {
				tbProgress_.setProgressState(TBPF_INDETERMINATE);
			}
			else {
				tbProgress_.setProgressState(TBPF_NORMAL);
				tbProgress_.setProgressValue(progress, total);
			}
		}

		setProgressLabel(label);
		progressBar_.setState(DWT.NORMAL);
		progressBar_.setMaximum(total);
		progressBar_.setSelection(progress);
		progressLabel_.setVisible(true);
		progressBar_.setVisible(true);
	}


	void hideProgress(in char[] text="")
	{
		if (isDisposed())
			return;
		progressBar_.setVisible(false);
		version (Windows) if (tbProgress_)
				tbProgress_.setProgressState(TBPF_NOPROGRESS);
		setLeft(text);
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

		version (Windows) if (tbProgress_) {
			if (!(progressBar_.getStyle() & DWT.INDETERMINATE))
				tbProgress_.setProgressValue(current, total);
		}
	}


	void setProgressError()
	{
		if (isDisposed())
			return;
		
		progressBar_.setState(DWT.ERROR);

		version (Windows) if (tbProgress_)
			tbProgress_.setProgressState(TBPF_ERROR);
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


	// For the Windows 7 and later taskbar.
	version (Windows) private void initTaskbarProgress()
	{
		try {
			tbProgress_ = new TaskbarProgress(parent.getShell().handle);
		}
		catch (Exception e) {
			//logx(__FILE__, __LINE__, e);
		}

		if (tbProgress_)
			callAtShutdown ~= &tbProgress_.dispose;
	}


private:
	Label serverLabel_;
	Label playerLabel_;
	Label progressLabel_;
	ProgressBar progressBar_;
	version (Windows) {
		TaskbarProgress tbProgress_ = null;
	}
}


///
class FilterBar : Group
{
	///
	this(Composite parent)
	{
		super(parent, DWT.SHADOW_NONE);
		setText("Filters and game selection");
		setLayoutData(new GridData);

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
		Filter state = cast(Filter)getSessionStateInt("filterState");
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

		auto layout = new RowLayout;
		layout.fill = true;
		layout.marginHeight = 2;
		layout.marginWidth = 2;
		setLayout(layout);
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
		gamesCombo_.setItems(list);

		int n = gamesCombo_.getItemCount();
		if (n > 8)
			n = 8;
		gamesCombo_.setVisibleItemCount(max(n, 5));

		int i = gamesCombo_.indexOf(lastSelectedGame_);
		gamesCombo_.select((i == -1) ? 0 : i);
	}


	///  Saves the session state.
	private void saveState()
	{
		// avoid saving a bogus value for lastMod
		if (gamesCombo_.indexOf(lastSelectedGame_) == -1) {
			foreach (s; gamesCombo_.getItems()) {
				if (s.length) {
					lastSelectedGame_ = s;
					break;
				}
			}
		}

		setSetting("lastMod", lastSelectedGame_);
		setSessionState("filterState", Integer.toString(filterState));
	}


	private void refreshServerTable()
	{
		Display.getDefault.asyncExec(dgRunnable( {
			serverTable.fullRefresh;
		}));
	}


private:
	Button notEmptyButton_, hasHumansButton_;
	char[] lastSelectedGame_;
	Combo gamesCombo_;
}


/**
 * Note: Toolbars and ToolItems do not participate in tab traversal.  And as
 *       ToolItems are not Controls, it is not possible to use
 *       Composite.setTabList in this case.  A more involved solution would be
 *       needed.
 */
private class ToolBarWrapper
{
	this(Shell shell, Composite parent)
	{
		toolBar_ = new ToolBar(parent, DWT.HORIZONTAL);

		checkForNewButton_ = new ToolItem(toolBar_, DWT.PUSH);
		checkForNewButton_.setText("Check for new");
		checkForNewButton_.setImage(loadImage!("box_download_32.png"));
		checkForNewButton_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				startAction(Action.checkForNew);
			}
		});

		// Need some space between the buttons to reduce the chance of the 
		// drop down part getting stuck in the hot state.
		(new ToolItem(toolBar_, DWT.SEPARATOR)).setWidth(5);

		refreshAllButton_ = new ToolItem(toolBar_, DWT.DROP_DOWN);
		refreshAllButton_.setText("Refresh all");
		refreshAllButton_.setImage(loadImage!("refresh_32.png"));
		refreshAllButton_.addSelectionListener(
		                       new RefreshButtonListener(shell));

		// Need some space between the buttons to reduce the chance of the 
		// drop down part getting stuck in the hot state.
		(new ToolItem(toolBar_, DWT.SEPARATOR)).setWidth(5);

		addButton_ = new ToolItem(toolBar_, DWT.PUSH);
		addButton_.setText("  Add...  ");
		addButton_.setImage(loadImage!("add_32.png"));
		addButton_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				auto dialog = new SpecifyServerDialog(mainWindow.handle);
				dialog.open();
			}
		});

		(new ToolItem(toolBar_, DWT.SEPARATOR)).setWidth(16);

		stopButton_ = new ToolItem(toolBar_, DWT.PUSH);
		stopButton_.setText("   Stop   ");
		stopButton_.setImage(loadImage!("cancel_32.png"));
		stopButton_.setEnabled(false);
		stopButton_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				stopAction();
			}
		});

		(new ToolItem(toolBar_, DWT.SEPARATOR)).setWidth(16);

		settingsButton_ = new ToolItem(toolBar_, DWT.PUSH);
		settingsButton_.setText("Settings");
		settingsButton_.setImage(loadImage!("spanner_32.png"));
		settingsButton_.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				SettingsDialog dialog = new SettingsDialog(mainWindow.handle);
				if (dialog.open())
					saveSettings();
			}
		});

		addActionHandler(new ToolBarActionHandler);
	}

	ToolBar getToolBar() { return toolBar_; }

	private class ToolBarActionHandler : ActionHandler
	{
		void actionStarting(Action action)
		{
			enableAllButtons();
			switch (action) {
				case Action.checkForNew:
					if (!checkForNewButton_.isDisposed())
						checkForNewButton_.setEnabled(false);
					break;
				case Action.refreshAll:
					if (!refreshAllButton_.isDisposed())
						refreshAllButton_.setEnabled(false);
					break;
				case Action.addServer:
					if (!addButton_.isDisposed())
						addButton_.setEnabled(false);
					break;
				default:
				break;
			}
		}

		void actionQueued(Action action) { actionStarting(action); }

		void actionStopping(Action action)
		{
			enableAllButtons();
			if (!stopButton_.isDisposed())
				stopButton_.setEnabled(false);
		}

		void actionDone(Action action) { actionStopping(action); }
	}
	
	private void enableAllButtons()
	{
		if (toolBar_.isDisposed())
			return;

		foreach (item; toolBar_.getItems())
			if (!item.isDisposed())
				item.setEnabled(true);
	}

	private {
		ToolBar toolBar_;
		ToolItem checkForNewButton_;
		ToolItem refreshAllButton_;
		ToolItem addButton_;
		ToolItem stopButton_;
		ToolItem settingsButton_;
	}
}


private class RefreshButtonListener : SelectionAdapter {
	this(Shell shell)
	{
		menu_ = new Menu(shell);
		(new MenuItem(menu_, DWT.NONE)).setText(
		              "Refresh servers that did not respond (\&infin;)");
		(new MenuItem(menu_, DWT.NONE)).setText(
		             "Refresh servers that were not queried (?)");
	}

	void widgetSelected(SelectionEvent e)
	{
		if (e.detail != DWT.ARROW) {
			startAction(Action.refreshAll);
		}
		else {
			// Align the menu to the button and show it
			auto parent = (cast(ToolItem)e.widget).getParent();
			auto display = Display.getDefault();
			menu_.setLocation(display.map(parent, null, e.x, e.y));

			// Making the button toggle the menu on/off is complicated, as
			// the menu is automatically hidden when you click the button. We
			// do it the easy way by just always showing it.
			menu_.setVisible(true);
		}
	}

	private Menu menu_;
}


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
