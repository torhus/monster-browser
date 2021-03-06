/** Various dialog boxes. */

module dialogs;

import tango.core.Exception;
import tango.io.device.File;
import tango.io.Path;
import tango.net.InternetAddress;
import Integer = tango.text.convert.Integer;
import tango.text.Util;

import dwt.DWT;
import dwt.events.SelectionAdapter;
import dwt.events.SelectionEvent;
import dwt.graphics.Point;
import dwt.graphics.Rectangle;
import dwt.layout.GridData;
import dwt.layout.GridLayout;
import dwt.layout.RowData;
import dwt.layout.RowLayout;
import dwt.program.Program;
import dwt.widgets.Button;
import dwt.widgets.Composite;
import dwt.widgets.Control;
import dwt.widgets.Display;
import dwt.widgets.Event;
import dwt.widgets.Group;
import dwt.widgets.Label;
import dwt.widgets.Listener;
import dwt.widgets.Shell;
import dwt.widgets.Spinner;
import dwt.widgets.Text;

import common;
import mainwindow;
import masterlist;
import messageboxes;
import serveractions;
import serverdata;
import serverlist;
import servertable;
import settings;


template Tuple(E...) { alias E Tuple; }

/// Default Windows button size.
alias Tuple!(75, 23) BUTTON_SIZE;

/// Default Windows button spacing.
const BUTTON_SPACING = 6;


/**
 * A generic dialog with OK and Cancel buttons, that asks for a password and
 * optionally whether to save it.
 */
class PasswordDialog
{
	/**
	 * Set these before calling open(). After open() returns, their values will
	 * have been updated to reflect the user's input.
	 *
	 * The default is an empty password, and yes to saving it.
	 */
	char[] password = "";
	bool savePassword = true;  /// ditto

	/**
	 * If pwdMandatory is true, the OK button will be disabled whenever the
	 * password field is empty.
	 */
	this(Shell parent, in char[] title, in char[] message,
	                             bool pwdMandatory=false, bool askToSave=false)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, DWT.DIALOG_TRIM | DWT.APPLICATION_MODAL);
		shell_.setLayout(new GridLayout);
		shell_.setText(title);

		// message
		Label labelA = new Label(shell_, DWT.NONE);
		labelA.setText(message);

		// password input
		Composite pwdComposite = new Composite(shell_, DWT.NONE);
		GridData pwdData = new GridData();
		pwdData.horizontalAlignment = DWT.CENTER;
		pwdComposite.setLayoutData(pwdData);

		pwdComposite.setLayout(new RowLayout);
		Label labelB = new Label(pwdComposite, DWT.NONE);
		labelB.setText("Password:");
		pwdText_ = new Text(pwdComposite, DWT.SINGLE | DWT.BORDER |
		                                                         DWT.PASSWORD);
		if (pwdMandatory) {
			pwdText_.addListener(DWT.Modify, new class Listener {
				void handleEvent(Event e)
				{
					okButton_.setEnabled(pwdText_.getText().length > 0);
				}
			});
		}
		if (askToSave) {
			saveButton_ = new Button (shell_, DWT.CHECK);
			saveButton_.setText("Save this password");
			auto saveButtonData = new GridData;
			saveButtonData.horizontalAlignment = DWT.CENTER;
			saveButton_.setLayoutData(saveButtonData);
		}

		// main buttons
		Composite buttonComposite = new Composite(shell_, DWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = DWT.CENTER;
		buttonComposite.setLayoutData(buttonData);

		RowLayout buttonLayout = new RowLayout();
		buttonLayout.spacing = BUTTON_SPACING;
		buttonComposite.setLayout(buttonLayout);

		okButton_ = new Button (buttonComposite, DWT.PUSH);
		okButton_.setText ("OK");
		okButton_.setLayoutData(new RowData(BUTTON_SIZE));

		cancelButton_ = new Button (buttonComposite, DWT.PUSH);
		cancelButton_.setText ("Cancel");
		cancelButton_.setLayoutData(new RowData(BUTTON_SIZE));

		auto listener = new ButtonListener;
		okButton_.addListener(DWT.Selection, listener);
		cancelButton_.addListener(DWT.Selection, listener);

		shell_.setDefaultButton(okButton_);
		shell_.pack();
		shell_.setLocation(center(parent_, shell_));
	}

	/**
	 * Show the dialog.
	 *
	 * Returns true if the user pressed OK, false if Cancel.
	 */
	bool open()
	{
		pwdText_.setText(password);
		pwdText_.selectAll();
		if (saveButton_ !is null)
			saveButton_.setSelection(savePassword);
		shell_.open();
		Display display = Display.getDefault;
		while (!shell_.isDisposed()) {
			if (!display.readAndDispatch()) {
				display.sleep ();
			}
		}
		return result_ == DWT.OK;
	}


private:
	Shell parent_, shell_;
	Button okButton_, cancelButton_, saveButton_;
	Text pwdText_;
	int result_ = DWT.CANCEL;

	class ButtonListener : Listener {
		void handleEvent (Event event)
		{
			if (event.widget == okButton_)
				result_ = DWT.OK;
			password = pwdText_.getText();
			if (saveButton_ !is null)
				savePassword = saveButton_.getSelection();
			shell_.close();
		}
	};
}


///
class SpecifyServerDialog
{
	///
	this(Shell parent)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, DWT.DIALOG_TRIM | DWT.APPLICATION_MODAL);
		shell_.setLayout(new GridLayout);
		shell_.setText("Add Server");

		// address input
		Composite addressComposite = new Composite(shell_, DWT.NONE);
		GridData addressData = new GridData();
		addressData.horizontalAlignment = DWT.CENTER;
		addressComposite.setLayoutData(addressData);

		addressComposite.setLayout(new GridLayout);
		Label labelB = new Label(addressComposite, DWT.NONE);
		labelB.setText("Please specify an IP address or host name, " ~
		                               "with an optional port number:");
		addressText_ = new Text(addressComposite, DWT.SINGLE | DWT.BORDER);
		auto addressTextData = new GridData();
		addressTextData.horizontalAlignment = DWT.CENTER;
		addressTextData.widthHint = 140;
		addressText_.setLayoutData(addressTextData);

		saveButton_ = new Button(shell_, DWT.CHECK);
		saveButton_.setText("Never remove this server automatically");
		saveButton_.setToolTipText("This is useful for servers that are not"
		                           " known to the master server");
		saveButton_.setSelection(
		                  getSessionState("addServersAsPersistent") == "true");
		auto saveButtonData = new GridData;
		saveButtonData.horizontalAlignment = DWT.CENTER;
		saveButton_.setLayoutData(saveButtonData);

		// main buttons
		Composite buttonComposite = new Composite(shell_, DWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = DWT.CENTER;
		buttonComposite.setLayoutData(buttonData);

		RowLayout buttonLayout = new RowLayout();
		buttonLayout.spacing = BUTTON_SPACING;
		buttonComposite.setLayout(buttonLayout);

		okButton_ = new Button (buttonComposite, DWT.PUSH);
		okButton_.setText ("OK");
		okButton_.setLayoutData(new RowData(BUTTON_SIZE));
		cancelButton_ = new Button (buttonComposite, DWT.PUSH);
		cancelButton_.setText ("Cancel");
		cancelButton_.setLayoutData(new RowData(BUTTON_SIZE));

		okButton_.addListener(DWT.Selection, new OkButtonListener);
		cancelButton_.addListener(DWT.Selection, new class Listener {
			void handleEvent(Event event)
			{
				shell_.close();
			}
		});
		shell_.setDefaultButton(okButton_);

		shell_.pack();
		shell_.setLocation(center(parent_, shell_));
	}


	bool open()
	{
		shell_.open();
		Display display = Display.getDefault;
		while (!shell_.isDisposed()) {
			if (!display.readAndDispatch()) {
				display.sleep ();
			}
		}
		return result_ == DWT.OK;
	}


	private class OkButtonListener : Listener {
		void handleEvent (Event event)
		{
			shell_.setEnabled(false);

			result_ = DWT.OK;
			char[] input = trim(addressText_.getText());
			char[] address = null;

			try {
				// Parse the address using the default Quake 3 port, 27960, as
				// the default.
				address = (new InternetAddress(input, 27960)).toString();
			}
			catch (SocketException e) {
				error(e.toString());
				shell_.setEnabled(true);
				addressText_.setFocus();
				addressText_.selectAll();
			}

			if (address && input.length) {
				ServerList serverList = serverTable.serverList;
				MasterList master = serverList.master;
				ServerHandle sh = master.findServer(address);
				bool persistent = saveButton_.getSelection();

				setSessionState("addServersAsPersistent",
				                                persistent ? "true" : "false");

				if (sh == InvalidServerHandle) {
					ServerData sd;

					sd.server.length = ServerColumn.max + 1;
					sd.server[ServerColumn.ADDRESS] = address;
					sd.persistent = persistent;
					master.addServer(sd);

					queryServers([address], true, true);
				}
				else {
					ServerData sd = master.getServerData(sh);
					GameConfig game = getGameConfig(serverList.gameName);

					if (matchGame(&sd, game)) {
						info("That server is already on the list.  If you "
						         "can't see it, try turning off the filters.");
						int i = serverList.getFilteredIndex(address);
						if (i != -1)
							serverTable.setSelection([i], true);
					}
					else {
						queryServers([address], true, true);
					}
				}
			}

			shell_.close();
		}
	}


	private {
		Shell parent_, shell_;
		Button okButton_, cancelButton_, saveButton_;
		Text addressText_;
		int result_ = DWT.CANCEL;
	}
}


///
class SettingsDialog
{
	///
	this(Shell parent)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, DWT.DIALOG_TRIM | DWT.APPLICATION_MODAL);
		shell_.setLayout(new GridLayout());
		shell_.setText("Settings");

		Composite mainComposite = new Composite(shell_, DWT.NONE);
		GridData gridData = new GridData();
		gridData.horizontalAlignment = DWT.CENTER;
		mainComposite.setLayoutData(gridData);
		mainComposite.setLayout(new GridLayout);

		// executable path
		Label labelB = new Label(mainComposite, DWT.NONE);
		labelB.setText("Location of your Quake 3 executable:");
		pathText_ = new Text(mainComposite, DWT.SINGLE | DWT.BORDER);
		pathText_.setText(getSetting("gamePath"));
		gridData = new GridData(GridData.HORIZONTAL_ALIGN_FILL);
		pathText_.setLayoutData(gridData);

		// startup game
		Group startupGroup = new Group(mainComposite, DWT.SHADOW_ETCHED_IN);
		startupGroup.setText("Start with");
		auto startupLayout = new GridLayout();
		startupGroup.setLayout(startupLayout);
		startupDefaultButton_ = new Button(startupGroup, DWT.RADIO);
		startupDefaultButton_.setText("First game");
		startupLastButton_ = new Button(startupGroup, DWT.RADIO);
		startupLastButton_.setText("Last used game");

		if (getSetting("startWithLastMod") == "true")
			startupLastButton_.setSelection(true);
		else
			startupDefaultButton_.setSelection(true);

		// simultaneousQueries
		auto sqComposite = new Composite(mainComposite, DWT.NONE);
		sqComposite.setLayout(new GridLayout(2, false));
		Label sqLabel = new Label(sqComposite, DWT.WRAP);
		sqLabel.setText("Number of servers to query\n"
		                "simultaneously, default is 10:");
		sqSpinner_ = new Spinner(sqComposite, DWT.BORDER);
		sqSpinner_.setMinimum(1);
		sqSpinner_.setMaximum(99);
		uint ate;
		int val = Integer.convert(getSetting("simultaneousQueries"), 10, &ate);
		sqSpinner_.setSelection(ate > 0 ? val : 10);

		// game configuration
		Button gamesButton = new Button(mainComposite, DWT.PUSH);
		gamesButton.setText("Game configuration");
		gamesButton.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				try {
					lastModified_ = modified(settings.gamesFileName);
					Program.launch(settings.gamesFileName);
					checkGameConfig_ = true;
				}
				catch (IOException e) {
					error(e.toString());
				}
			}
		});

		// main buttons
		Composite buttonComposite = new Composite(shell_, DWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = DWT.CENTER;
		buttonComposite.setLayoutData(buttonData);

		auto buttonLayout = new RowLayout;
		buttonLayout.spacing = BUTTON_SPACING;
		buttonComposite.setLayout(buttonLayout);

		okButton_ = new Button (buttonComposite, DWT.PUSH);
		okButton_.setText ("OK");
		okButton_.setLayoutData(new RowData(BUTTON_SIZE));

		cancelButton_ = new Button (buttonComposite, DWT.PUSH);
		cancelButton_.setText ("Cancel");
		cancelButton_.setLayoutData(new RowData(BUTTON_SIZE));

		Listener listener = new class Listener {
			public void handleEvent (Event event)
			{
				if (event.widget == okButton_) {
					char s[];
					result_ = DWT.OK;
					setSetting("gamePath", pathText_.getText);

					s = (startupLastButton_.getSelection()) ? "true" : "false";
					setSetting("startWithLastMod", s);

					int sq = sqSpinner_.getSelection();
					setSetting("simultaneousQueries", Integer.toString(sq));
				}

				// in case the game list was edited
				if (checkGameConfig_) {
					try {
						if (modified(gamesFileName) > lastModified_) {
							settings.loadGamesFile();
							filterBar.setGames(settings.gameNames);
						}
					}
					catch (IOException e) {
						error(e.toString());
					}
				}

				shell_.close();
			}
		};

		okButton_.addListener(DWT.Selection, listener);
		cancelButton_.addListener(DWT.Selection, listener);
		shell_.setDefaultButton(okButton_);
		shell_.pack();
		shell_.setLocation(center(parent_, shell_));
	}

	bool open() ///
	{
		shell_.open();
		Display display = Display.getDefault;
		while (!shell_.isDisposed()) {
			if (!display.readAndDispatch()) {
				display.sleep();
			}
		}
		return result_ == DWT.OK;
	}

private:
	Shell parent_, shell_;
	Button okButton_, cancelButton_;
	Button startupDefaultButton_, startupLastButton_;
	bool checkGameConfig_ = false;
	Time lastModified_;
	Text pathText_;
	int result_ = DWT.CANCEL;
	Spinner sqSpinner_;
}



/**
 * Takes care of loading and saving passwords, and updating the
 * "saveServerPasswords" setting.  Otherwise like PasswordDialog.
 */
class ServerPasswordDialog : PasswordDialog
{
	///
	this(Shell parent, in char[] title, in char[] message, in char[] address,
	                             bool pwdMandatory=false, bool askToSave=false)
	{
		address_ = address;
		askToSave_ = askToSave;
		super(parent, title, message, pwdMandatory, askToSave);
		password = getPassword(address);
		if (askToSave)
			savePassword = getSessionState("saveServerPasswords") == "true";
		else
			savePassword = true;
	}

	override bool open() ///
	{
		bool result = super.open();
		if (result) {
			bool oldSave = getSessionState("saveServerPasswords") == "true";
			if (savePassword)
				setPassword(address_, password);
			if (askToSave_ && oldSave != savePassword)
				setSessionState("saveServerPasswords",
				                              savePassword ? "true" : "false");
		}
		return result;
	}

	private char[] address_;
	private bool askToSave_;
}


/**
 * Takes care of saving but not loading passwords, and updating the
 * "saveRconPasswords" setting.  Otherwise like PasswordDialog.
 */
class RconPasswordDialog : PasswordDialog
{
	///
	this(Shell parent, in char[] serverName, in char[] address)
	{
		address_ = address;
		super(parent, "Remote Console",
		                "Set password for \"" ~ serverName ~ "\"", true, true);
		savePassword = getSessionState("saveRconPasswords") == "true";
	}

	override bool open() ///
	{
		bool result = super.open();
		if (result) {
			bool oldSave = getSessionState("saveRconPasswords") == "true";
			if (savePassword)
				setRconPassword(address_, password);
			if (oldSave != savePassword)
				setSessionState("saveRconPasswords",
				                              savePassword ? "true" : "false");
		}
		return result;
	}

	private char[] address_;
}


private Point center(Control parent, Control child)
{
	Rectangle p = parent.getBounds();
	Rectangle c = child.getBounds();
	int x = p.x + (p.width - c.width) / 2;
	int y = p.y + (p.height - c.height) / 2;

	return new Point(x, y);
}
