/** The main window, including tool bar and status bar. */

module mainwindow;

import std.algorithm : max;
import std.conv;
import std.regex;
import std.string;

import java.io.ByteArrayInputStream;
import java.lang.Runnable;
import org.eclipse.swt.SWT;
import org.eclipse.swt.custom.SashForm;
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
import org.eclipse.swt.layout.RowData;
import org.eclipse.swt.layout.RowLayout;
import org.eclipse.swt.widgets.Button;
import org.eclipse.swt.widgets.Combo;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Group;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.ProgressBar;
import org.eclipse.swt.widgets.Shell;
import org.eclipse.swt.widgets.Text;
import org.eclipse.swt.widgets.ToolBar;
import org.eclipse.swt.widgets.ToolItem;

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

__gshared StatusBar statusBar;  ///
__gshared GameBar gameBar;  ///
__gshared FilterBar filterBar;  ///
__gshared MainWindow mainWindow;  ///
/// The close() method will be called for these shells, before everything is
/// disposed of.
__gshared Shell[] subWindows;

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
		shell_.setText(APPNAME ~ " " ~ getVersionString());
		shell_.addShellListener(new MyShellListener);

		// restore window size and state
		if (auto m = getSetting("windowSize").matchFirst(r"^(\d+)x(\d+)$"))
			shell_.setSize(to!int(m[1]), to!int(m[2]));

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
		Composite topComposite = new Composite(shell_, SWT.NONE);
		auto topData = new GridData(SWT.FILL, SWT.CENTER, true, false, 2, 1);
		topComposite.setLayoutData(topData);

		// This layout works better when the buttons have images.
		auto topLayout = new GridLayout(3, false);
		topLayout.marginHeight = 0;
		topLayout.horizontalSpacing = 20;
		topComposite.setLayout(topLayout);

		new ToolBarWrapper(topComposite);

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

			string width  = to!string(shell_.getSize().x);
			string height = to!string(shell_.getSize().y);
			setSetting("windowSize", width ~ "x" ~ height);
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
			serverTable.stopRefresh(false);
			threadManager.shutDown();
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
final class StatusBar : Composite
{
	///
	this(Composite parent)
	{
		super(parent, SWT.NONE);
		auto layout = new GridLayout(7, false);
		layout.marginWidth = 2;
		layout.marginHeight = 0;
		setLayout(layout);

		progressLabel_ = new Label(this, SWT.NONE);
		progressLabel_.setVisible(false);

		progressBar_ = createProgressBar(false);
		progressBar_.setVisible(false);

		// an empty Label to push the rest of the labels to the far right of
		// the status bar
		auto empty = new Label(this, SWT.NONE);
		auto emptyData = new GridData(SWT.CENTER, SWT.CENTER, true, false);
		empty.setLayoutData(emptyData);

		int sepHeight = progressLabel_.computeSize(SWT.DEFAULT, SWT.DEFAULT).y;

		createSeparator(sepHeight);

		serverLabel_ = new Label(this, SWT.NONE);
		auto serverData = new GridData(SWT.CENTER, SWT.CENTER, false, false);
		serverLabel_.setLayoutData(serverData);

		createSeparator(sepHeight);

		playerLabel_ = new Label(this, SWT.NONE);
		auto playerData = new GridData(SWT.CENTER, SWT.CENTER, false, false);
		playerLabel_.setLayoutData(playerData);

		version (Windows) {
			initTaskbarProgress();
		}
	}

	void setLeft(string text)  ///
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

		string s;

		if (shownServers != totalServers)
			s = text(shownServers, " of ", totalServers, " servers");
		else
			s = text(shownServers, " servers");

		serverLabel_.setText(s);
		playerLabel_.setText(text(humans, " human players"));

		layout();
		setRedraw(true);
	}


	void showProgress(string label, bool indeterminate=false, int total=0,
	                                                        int progress=0)
	{
		if (isDisposed())
			return;

		assert(progressBar_ !is null);

		if ((progressBar_.getStyle() & SWT.INDETERMINATE) != indeterminate) {
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
		progressBar_.setState(SWT.NORMAL);
		progressBar_.setMaximum(total);
		progressBar_.setSelection(progress);
		progressLabel_.setVisible(true);
		progressBar_.setVisible(true);
	}


	void hideProgress(string text="")
	{
		if (isDisposed())
			return;
		progressBar_.setVisible(false);
		version (Windows) if (tbProgress_)
				tbProgress_.setProgressState(TBPF_NOPROGRESS);
		setLeft(text);
	}


	private void setProgressLabel(string text)
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
			if (!(progressBar_.getStyle() & SWT.INDETERMINATE))
				tbProgress_.setProgressValue(current, total);
		}
	}


	void setProgressError()
	{
		if (isDisposed())
			return;
		
		progressBar_.setState(SWT.ERROR);

		version (Windows) if (tbProgress_)
			tbProgress_.setProgressState(TBPF_ERROR);
	}


	private ProgressBar createProgressBar(bool indeterminate)
	{
		auto pb = new ProgressBar(this, indeterminate ?
		                                        SWT.INDETERMINATE : SWT.NONE);
		auto data = new GridData;
		data.widthHint = 100;
		pb.setLayoutData(data);
		return pb;
	}


	private Label createSeparator(int height)
	{
		auto sep = new Label(this, SWT.SEPARATOR);
		auto sepData = new GridData(SWT.CENTER, SWT.CENTER, false, false);
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
final class GameBar : Group
{
	///
	this(Composite parent)
	{
		super(parent, SWT.SHADOW_NONE);
		setText("Game");
		setLayoutData(new GridData(SWT.CENTER, SWT.CENTER, false, true));

		// game selection
		gamesCombo_ = new Combo(this, SWT.DROP_DOWN | SWT.READ_ONLY);
		setGames(settings.gameNames);
		if (getSetting("startWithLastMod") == "true") {
			string s = getSetting("lastMod");
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
			public override void widgetSelected(SelectionEvent e)
			{
				serverTable.getTable.setFocus();
				lastSelectedGame_ = (cast(Combo)e.widget).getText();
				switchToGame(lastSelectedGame_);
			}

			public override void widgetDefaultSelected(SelectionEvent e)
			{
				string s = strip((cast(Combo)e.widget).getText());
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
	string selectedGame()
	{
		return lastSelectedGame_;
	}


	/// Set the contents of the game name drop-down list.
	void setGames(string[] list)
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

		notEmptyButton_ = new Button(this, SWT.CHECK);
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

		hasHumansButton_ = new Button(this, SWT.CHECK);
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

		// Restore saved filter state
		Filter state = cast(Filter)getSessionStateInt("filterState");
		if (state & Filter.NOT_EMPTY)
			notEmptyButton_.setSelection(true);
		if (state & Filter.HAS_HUMANS)
			hasHumansButton_.setSelection(true);

		filterText_ = new Text(this, SWT.SINGLE | SWT.BORDER | SWT.SEARCH /*|
		                                  SWT.ICON_SEARCH | SWT.ICON_CANCEL*/);
		filterText_.setMessage("Search");
		auto filterTextData = new RowData();
		filterTextData.width = 80;
		filterText_.setLayoutData(filterTextData);
		filterText_.addSelectionListener(new class SelectionAdapter {
			public override void widgetDefaultSelected(SelectionEvent e)
			{
				string s = strip((cast(Text)e.widget).getText());

				serverTable.serverList.setSearchString(s,
				                           serverFilterButton_.getSelection());
				refreshServerTable();
			}
		});

		auto clearButton = new Button(this, 0);
		clearButton.setText("Clear");
		clearButton.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent _)
			{
				clearSearch();
				serverTable.serverList.setSearchString("",
				                           serverFilterButton_.getSelection());
				refreshServerTable();
			}
		});

		auto filterTypes = new Composite(this, 0);
		filterTypes.setLayout(new GridLayout(1, false));
		filterTypes.setLayoutData(new GridData(SWT.CENTER, SWT.CENTER,
		                                                      false, false));
		serverFilterButton_ = new Button(filterTypes, SWT.RADIO);
		serverFilterButton_.setText("Servers");
		serverFilterButton_.setSelection(true);
		auto playerFilterButton = new Button(filterTypes, SWT.RADIO);
		playerFilterButton.setText("Players");

		auto layout = new RowLayout;
		layout.center = true;
		layout.marginHeight = 0;
		layout.marginWidth = 2;
		layout.spacing = 0,
		layout.pack = true;
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
	}


	private void refreshServerTable()
	{
		Display.getDefault.asyncExec(dgRunnable( {
			serverTable.fullRefresh;
		}));
	}


private:
	Button notEmptyButton_, hasHumansButton_;
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
	this(Composite parent)
	{
		auto toolBar_ = new ToolBar(parent, SWT.HORIZONTAL);

		auto checkForNewButton_ = new ToolItem(toolBar_, SWT.PUSH);
		checkForNewButton_.setText("Check for new");
		checkForNewButton_.setImage(loadImage!("box_download_32.png"));
		checkForNewButton_.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
			{
				threadManager.run(&checkForNewServers);
			}
		});

		new ToolItem(toolBar_, SWT.SEPARATOR);
		refreshAllButton_ = new ToolItem(toolBar_, SWT.PUSH);
		refreshAllButton_.setText("Refresh all");
		refreshAllButton_.setImage(loadImage!("refresh_32.png"));
		refreshAllButton_.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
			{
				threadManager.run(&refreshAll);
			}
		});

		new ToolItem(toolBar_, SWT.SEPARATOR);

		addButton_ = new ToolItem(toolBar_, SWT.PUSH);
		addButton_.setText("   Add... ");
		addButton_.setImage(loadImage!("add_32.png"));
		addButton_.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
			{
				auto dialog = new SpecifyServerDialog(mainWindow.handle);
				dialog.open();
			}
		});

		new ToolItem(toolBar_, SWT.SEPARATOR);

		settingsButton_ = new ToolItem(toolBar_, SWT.PUSH);
		settingsButton_.setText(" Settings");
		settingsButton_.setImage(loadImage!("spanner_32.png"));
		settingsButton_.addSelectionListener(new class SelectionAdapter {
			public override void widgetSelected(SelectionEvent e)
			{
				SettingsDialog dialog = new SettingsDialog(mainWindow.handle);
				if (dialog.open())
					saveSettings();
			}
		});

	}

	ToolBar getToolBar() { return toolBar_; }

	private {
		ToolBar toolBar_;
		ToolItem checkForNewButton_;
		ToolItem refreshAllButton_;
		ToolItem addButton_;
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
