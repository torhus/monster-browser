/** The main window, including tool bar and status bar. */

module mainwindow;

import std.algorithm;
import std.conv;
import std.path : dirName;
import std.regex;
import std.string;

import java.io.ByteArrayInputStream;
import java.lang.Runnable;
import org.eclipse.swt.SWT;
import org.eclipse.swt.custom.SashForm;
import org.eclipse.swt.events.ModifyListener;
import org.eclipse.swt.events.ModifyEvent;
import org.eclipse.swt.events.SelectionAdapter;
import org.eclipse.swt.events.SelectionEvent;
import org.eclipse.swt.events.ShellAdapter;
import org.eclipse.swt.events.ShellEvent;
import org.eclipse.swt.graphics.Image;
import org.eclipse.swt.graphics.Point;
import org.eclipse.swt.graphics.Rectangle;
import org.eclipse.swt.layout.FillLayout;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.layout.GridLayout;
import org.eclipse.swt.layout.RowLayout;
import org.eclipse.swt.program.Program;
import org.eclipse.swt.widgets.Button;
import org.eclipse.swt.widgets.Combo;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Group : Group;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.Menu;
import org.eclipse.swt.widgets.MenuItem;
import org.eclipse.swt.widgets.MessageBox;
import org.eclipse.swt.widgets.Shell;
import org.eclipse.swt.widgets.Text;
import org.eclipse.swt.widgets.ToolBar;
import org.eclipse.swt.widgets.ToolItem;

import actions;
import common;
import cvartable;
import dialogs;
import gameconfig;
import launch;
import messageboxes;
import playertable;
import runtools : killServerBrowser;
import serveractions;
import serverlist;
import servertable;
import settings;
import statusbar;
import swtutil;
import threadmanager;
import updatecheck;

__gshared GameBar gameBar;  ///
__gshared FilterBar filterBar;  ///
__gshared MainWindow mainWindow;  ///

// Image objects that needs to be disposed of before shut down.
__gshared private Image[] imageList;


///
class MainWindow
{
	/**
	 *  Initializes all of the gui.
	 */
	this()
	{
		shell_ = new Shell(Display.getDefault);
		mainShell = shell_;
		shell_.setText(APPNAME ~ " " ~ getVersionString());
		shell_.addShellListener(new MyShellListener);

		auto layout = new GridLayout(2, false);
		layout.horizontalSpacing = 0;
		shell_.setLayout(layout);

		// *********** MAIN WINDOW TOP ***************
		auto topComposite = new Composite(shell_, SWT.NONE);
		auto topData = new GridData(SWT.FILL, SWT.CENTER, true, false, 2, 1);
		topComposite.setLayoutData(topData);

		// This layout works better when the buttons have images.
		auto topLayout = new GridLayout(3, false);
		topLayout.marginHeight = 0;
		topLayout.horizontalSpacing = 10;
		topComposite.setLayout(topLayout);

		new ToolBarWrapper(shell_, topComposite);

		gameBar = new GameBar(topComposite);
		filterBar = new FilterBar(topComposite);

		// ************** SERVER LIST, PLAYER LIST, CVARS LIST ***************
		middleForm_ = new SashForm(shell_, SWT.HORIZONTAL);
		auto middleData = new GridData(SWT.FILL, SWT.FILL, true, true);
		middleForm_.setLayoutData(middleData);

		// server table widget
		serverTable = new ServerTable(middleForm_);
		auto serverTableData = new GridData(SWT.LEFT, SWT.FILL, false, false);
		serverTable.getTable().setLayoutData(serverTableData);

		// parent for player and cvar tables
		rightForm_ = new SashForm(middleForm_, SWT.VERTICAL);
		auto rightData = new GridData(SWT.FILL, SWT.FILL, true, true);
		rightForm_.setLayoutData(rightData);

		rightForm_.setLayout(new FillLayout(SWT.VERTICAL));

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
		auto statusData = new GridData(SWT.FILL, SWT.CENTER, true, false);
		statusData.horizontalSpan = 2;
		statusBar.setLayoutData(statusData);


		// restore window size and state
		int[] windowSize = parseIntList(getSessionState("windowSize"), 2);
		if (windowSize[0] > 0) {
			shell_.setSize(windowSize[0], windowSize[1]);
		}
		else {
			Point size = topComposite.computeSize(SWT.DEFAULT, SWT.DEFAULT);
			// FIXME: Not sure how to get the actual needed width here.
			shell_.setSize(size.x + 21, windowSize[1]);
		}

		if (getSetting("windowMaximized") == "true")
			shell_.setMaximized(true);

		// restore window position
		int[] oldres = parseIntList(getSessionState("resolution"), 2);
		Rectangle res = Display.getDefault().getBounds();
		if (oldres[0] == res.width && oldres[1] == res.height) {
			int[] pos = parseIntList(getSessionState("windowPosition"), 2);
			shell_.setLocation(pos[0], pos[1]);
		}
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

			Point size = shell_.getSize();
			setSessionState("windowSize", toCsv([size.x, size.y]));
		}

		setSessionState("middleWeights", toCsv(middleForm_.getWeights()));
		setSessionState("rightWeights", toCsv(rightForm_.getWeights()));

		gameBar.saveState();
		filterBar.saveState();
	}


	/// Handles the shell close event.
	private class MyShellListener : ShellAdapter {
		override void shellClosed(ShellEvent e)  ///
		{
			log("Shutting down...");
			statusBar.setLeft("Exiting...");
			stopAction();
			threadManager.shutDown();
			killServerBrowser();
			foreach (shell; Display.getDefault.getShells) {
				if (shell !is shell_)
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
final class GameBar : Group
{
	///
	this(Composite parent)
	{
		super(parent, SWT.SHADOW_NONE);
		setText("Games and mods");
		auto layoutData = new GridData(SWT.CENTER, SWT.CENTER, false, true);
		layoutData.verticalAlignment = GridData.FILL;
		setLayoutData(layoutData);

		// game selection
		gamesCombo_ = new Combo(this, SWT.DROP_DOWN | SWT.READ_ONLY);
		setGames(gameNames);
		if (getSetting("startWithLastMod") == "true") {
			string s = getSetting("lastMod");
			int i = findString(gameNames, s);
			gamesCombo_.select(i != -1 ? i : 0);
		}

		lastSelectedGame_ = gamesCombo_.getText();

		gamesCombo_.clearSelection();
		gamesCombo_.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
			{
				serverTable.getTable.setFocus();
				string s = (cast(Combo)e.widget).getText();

				if (s.all!"a == '-'") {
					// Can't select a separator.
					int i = findString(gameNames, lastSelectedGame_);
					gamesCombo_.select(i);
				}
				else {
					lastSelectedGame_ = s;
					switchToGame(lastSelectedGame_);
				}
			}
		});

		auto editButton = new Button(this, 0);
		editButton.setText("Edit");
		editButton.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
			{
				Program.launch(gamesFilePath);
			}
		});

		auto layout = new GridLayout(2, false);
		layout.marginTop = 5;
		layout.horizontalSpacing = 7;
		setLayout(layout);
	}


	/// The last selected game name.
	string selectedGame()
	{
		return lastSelectedGame_;
	}


	/// Set the contents of the game name drop-down list.
	void setGames(string[] list)
	{
		gamesCombo_.setItems(list);

		int n = gamesCombo_.getItemCount();
		gamesCombo_.setVisibleItemCount(max(n, 25));

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
	}


private:
	string lastSelectedGame_;
	Combo gamesCombo_;
}


///
final class FilterBar : Group
{
	///
	this(Composite parent)
	{
		super(parent, SWT.SHADOW_NONE);
		setText("Filters");
		setLayoutData(new GridData);

		auto composite = new Composite(this, 0);
		auto layout = new GridLayout(1, false);
		composite.setLayout(layout);

		notEmptyButton_ = new Button(composite, SWT.CHECK);
		notEmptyButton_.setText("Not empty");
		notEmptyButton_.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
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

		hasHumansButton_ = new Button(composite, SWT.CHECK);
		hasHumansButton_.setText("Has humans");
		hasHumansButton_.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
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

		favoritesOnlyButton_ = new Button(this, SWT.CHECK);
		favoritesOnlyButton_.setText("Favorites only");
		favoritesOnlyButton_.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
			{
				ServerList list = serverTable.serverList;

				if (favoritesOnlyButton_.getSelection())
					list.setFilters(list.getFilters() | Filter.FAVORITES_ONLY);
				else
					list.setFilters(list.getFilters() & ~Filter.FAVORITES_ONLY);

				refreshServerTable();
			}
		});

		// Restore saved filter state
		Filter state = cast(Filter)getSessionStateInt("filterState");
		if (state & Filter.NOT_EMPTY)
			notEmptyButton_.setSelection(true);
		if (state & Filter.HAS_HUMANS)
			hasHumansButton_.setSelection(true);
		if (state & Filter.FAVORITES_ONLY)
			favoritesOnlyButton_.setSelection(true);

		filterText_ = new Text(this, SWT.SINGLE | SWT.BORDER | SWT.SEARCH /*|
		                                  SWT.ICON_SEARCH | SWT.ICON_CANCEL*/);
		filterText_.setMessage("Search");
		auto filterTextData = new GridData();
		filterTextData.horizontalIndent = 3;
		filterTextData.widthHint = calcFieldWidth(filterText_, 13);
		filterText_.setLayoutData(filterTextData);
		filterText_.addSelectionListener(new class SelectionAdapter {
			public override void widgetDefaultSelected(SelectionEvent e)
			{
				updateSearchResults();
			}
		});
		filterText_.addModifyListener(new class ModifyListener {
			public override void modifyText(ModifyEvent e)
			{
				Display.getDefault().timerExec(500, dgRunnable(
				{
					string s = (cast(Text)e.widget).getText();
					if (s == filterText_.getText())
						updateSearchResults();
				}));
			}
		});

		auto clearButton = new Button(this, 0);
		clearButton.setText("Clear");
		clearButton.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent _)
			{
				clearSearch();
				updateSearchResults();
			}
		});

		auto filterTypes = new Composite(this, 0);
		auto filterTypesLayout = new GridLayout(1, false);
		filterTypesLayout.marginLeft = 5;
		filterTypes.setLayout(filterTypesLayout);

		serverFilterButton_ = new Button(filterTypes, SWT.RADIO);
		serverFilterButton_.setText("Servers");
		serverFilterButton_.addSelectionListener(new SearchTypeHandler);
		auto playerFilterButton = new Button(filterTypes, SWT.RADIO);
		playerFilterButton.setText("Players");
		playerFilterButton.addSelectionListener(new SearchTypeHandler);

		// Restore saved search type
		if (getSessionStateInt("searchType") == 0)
			serverFilterButton_.setSelection(true);
		else
			playerFilterButton.setSelection(true);

		layout = new GridLayout(5, false);
		layout.marginHeight = 0;
		layout.marginLeft = 2;
		layout.horizontalSpacing = 0;
		setLayout(layout);
	}


	/// State of filter selection buttons.
	Filter filterState()
	{
		Filter f;

		if(notEmptyButton_.getSelection())
			f |= Filter.NOT_EMPTY;
		if (hasHumansButton_.getSelection())
			f |= Filter.HAS_HUMANS;
		if(favoritesOnlyButton_.getSelection())
			f |= Filter.FAVORITES_ONLY;

		return f;
	}


	/// Empty the search field.
	void clearSearch()
	{
		filterText_.setText("");
	}


	///  Saves the session state.
	private void saveState()
	{
		setSessionState("filterState", to!string(cast(int)filterState));
		setSessionState("searchType", serverFilterButton_.getSelection() ?
		                                                            "0" : "1");
	}


	private void refreshServerTable()
	{
		Display.getDefault.asyncExec(dgRunnable( {
			serverTable.fullRefresh;
		}));
	}

	private void updateSearchResults()
	{
		bool r = serverTable.serverList.setSearchString(filterText_.getText(),
		                                   serverFilterButton_.getSelection());
		if (r)
			refreshServerTable();
	}


	private class SearchTypeHandler : SelectionAdapter {
		public override void widgetSelected(SelectionEvent e)
		{
			updateSearchResults();
		}
	}

private:
	Button favoritesOnlyButton_, notEmptyButton_, hasHumansButton_;
	Text filterText_;
	Button serverFilterButton_;
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
		toolBar_ = new ToolBar(parent, SWT.HORIZONTAL | SWT.FLAT);

		checkForNewButton_ = new ToolItem(toolBar_, SWT.PUSH);
		checkForNewButton_.setText("Check for new");
		checkForNewButton_.setImage(loadImage!("box_download_32.png"));
		checkForNewButton_.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
			{
				startAction(Action.checkForNew);
			}
		});

		refreshAllButton_ = new ToolItem(toolBar_, SWT.PUSH);
		refreshAllButton_.setText("Refresh all");
		refreshAllButton_.setImage(loadImage!("refresh_32.png"));
		refreshAllButton_.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
			{
				startAction(Action.refreshAll);
			}
		});

		addButton_ = new ToolItem(toolBar_, SWT.PUSH);
		addButton_.setText("    Add...    ");
		addButton_.setImage(loadImage!("add_32.png"));
		addButton_.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
			{
				auto dialog = new SpecifyServerDialog(mainShell);
				dialog.open();
			}
		});

		stopButton_ = new ToolItem(toolBar_, SWT.PUSH);
		stopButton_.setText("   Stop   ");
		stopButton_.setImage(loadImage!("cancel_32.png"));
		stopButton_.setEnabled(false);
		stopButton_.addSelectionListener(new class SelectionAdapter {
			override public void widgetSelected(SelectionEvent e)
			{
				stopAction();
			}
		});

		launchButton_ = new ToolItem(toolBar_, SWT.DROP_DOWN);
		launchButton_.setText("    Join    ");
		launchButton_.setImage(loadImage!("launch_32.png"));
		launchButton_.addSelectionListener(new LaunchButtonListener(shell));

		settingsButton_ = new ToolItem(toolBar_, SWT.PUSH);
		settingsButton_.setText("    Tools    ");
		settingsButton_.setImage(loadImage!("spanner_32.png"));
		settingsButton_.addSelectionListener(new ToolsButtonListener(toolBar_));

		addActionHandler(new ToolBarActionHandler);
	}

	ToolBar getToolBar() { return toolBar_; }

	private class LaunchButtonListener : SelectionAdapter {
		this (Shell shell)
		{
			menu_ = new Menu(shell);
			menu_.addItem("Launch without joining").tag("launch");
			menu_.addSeparator();
			menu_.addItem("Select game executable...").tag("executable");
			menu_.addItem("Open game folder").tag("game folder");

			auto listener = new MenuItemListener;

			foreach (item; menu_.getItems())
				item.addSelectionListener(listener);
		}

		override void widgetSelected(SelectionEvent e)
		{
			if (e.detail != SWT.ARROW) {
				serverTable.onJoin();
			}
			else {
				auto parent = (cast(ToolItem)e.widget).getParent();
				auto display = Display.getDefault();
				menu_.setLocation(display.map(parent, null, e.x, e.y));

				// Making the button toggle the menu on/off is complicated, as
				// the menu is automatically hidden when you click the button.
				// We do it the easy way by just always showing it.
				menu_.setVisible(true);
			}
		}

		private Menu menu_;
	}

	private class ToolsButtonListener : SelectionAdapter {
		this(ToolBar toolBar)
		{
			menu_ = new Menu(toolBar);
			menu_.addItem("Settings").tag("settings");
			menu_.addSeparator();
			menu_.addItem("Open settings and data folder").tag("data folder");
			menu_.addItem("Open log file").tag("log file");
			menu_.addSeparator();
			menu_.addItem("Reset game configuration file").tag("reset config");
			menu_.addSeparator();
			menu_.addItem("Check for updates").tag("update check");
			menu_.addItem("Visit web site").tag("web site");

			auto listener = new MenuItemListener;

			foreach (item; menu_.getItems)
				item.addSelectionListener(listener);
		}

		override void widgetSelected(SelectionEvent e)
		{
			// Align the menu to the button and show it
			auto parent = (cast(ToolItem)e.widget).getParent();
			Rectangle rect = (cast(ToolItem)e.widget).getBounds();
			menu_.setLocation(parent.toDisplay(rect.x, rect.y + rect.height));
			menu_.setVisible(true);
		}

		private {
			Menu menu_;
		}
	}

	private class MenuItemListener : SelectionAdapter
	{
		override void widgetSelected(SelectionEvent e)
		{
			switch (lookUp(cast(MenuItem)e.widget)) {
				// Join button menu
				case "launch":
					launchGame(gameBar.selectedGame);
					break;
				case "executable":
					askForGamePath(serverTable.serverList.gameName);
					break;
				case "game folder": {
					auto game = getGameConfig(serverTable.serverList.gameName);
					if (game.exePath.length == 0) {
						info("Please select the executable for this game first.");
						askForGamePath(serverTable.serverList.gameName);
					}
					if (game.exePath.length > 0)
						Program.launch(dirName(game.exePath));
					break;
				}

				// Tools button menu
				case "settings": {
					auto dialog = new SettingsDialog(mainShell);
					if (dialog.open())
						saveSettings();
					break;
				}
				case "data folder":
					Program.launch(dataDir);
					break;
				case "log file":
					Program.launch(logDir ~ logFileName);
					break;
				case "reset config":
					auto mb = new MessageBox(mainShell, SWT.ICON_WARNING |
					                                         SWT.YES | SWT.NO);
					mb.setText("Reset Game Configuration");
					mb.setMessage("The game configuration file will be " ~
					        "backed up, and a new one created. Are you sure?");
					if (mb.open() == SWT.YES)
						updateGameConfiguration();
					break;
				case "update check":
					startUpdateChecker(false);
					break;
				case "web site":
					Program.launch(
					          "https://sites.google.com/site/monsterbrowser/");
					break;
				default:
					assert(0);
			}
		}
	}

	private class ToolBarActionHandler : ActionHandler
	{
		override void actionStarting(Action action)
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

		override void actionQueued(Action action) { actionStarting(action); }

		override void actionStopping(Action action)
		{
			enableAllButtons();
			if (!stopButton_.isDisposed())
				stopButton_.setEnabled(false);
		}

		override void actionDone(Action action) { actionStopping(action); }
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
		ToolItem launchButton_;
		ToolItem addButton_;
		ToolItem stopButton_;
		ToolItem settingsButton_;
	}
}


private Image loadImage(string name)()
{
	return _loadImage(cast(byte[])import(name));
}

private Image _loadImage(byte[] data)
{
	Image img = new Image(Display.getDefault, new ByteArrayInputStream(data));
	imageList ~= img;
	return img;
}
