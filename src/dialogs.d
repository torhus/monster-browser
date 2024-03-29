/** Various dialog boxes. */

module dialogs;

import std.conv;
import std.file;
import std.socket;
import std.string;

import org.eclipse.swt.SWT;
import org.eclipse.swt.events.SelectionAdapter;
import org.eclipse.swt.events.SelectionEvent;
import org.eclipse.swt.graphics.Point;
import org.eclipse.swt.graphics.Rectangle;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.layout.GridLayout;
import org.eclipse.swt.layout.RowData;
import org.eclipse.swt.layout.RowLayout;
import org.eclipse.swt.widgets.Button;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Control;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Event;
import org.eclipse.swt.widgets.Group;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.Listener;
import org.eclipse.swt.widgets.Shell;
import org.eclipse.swt.widgets.Spinner;
import org.eclipse.swt.widgets.Text;

import common;
import gameconfig;
import masterlist;
import messageboxes;
import serveractions;
import serverdata;
import serverlist;
import servertable;
import settings;
import updatecheck;


template Tuple(E...) { alias Tuple = E; }

/// Default Windows button size.
alias BUTTON_SIZE = Tuple!(75, 23);

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
	string password = "";
	bool savePassword = true;  /// ditto

	/**
	 * If pwdMandatory is true, the OK button will be disabled whenever the
	 * password field is empty.
	 */
	this(Shell parent, string title, string message,
	                             bool pwdMandatory=false, bool askToSave=false)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, SWT.DIALOG_TRIM | SWT.APPLICATION_MODAL);
		shell_.setLayout(new GridLayout);
		shell_.setText(title);

		// message
		Label labelA = new Label(shell_, SWT.NONE);
		labelA.setText(message);

		// password input
		Composite pwdComposite = new Composite(shell_, SWT.NONE);
		GridData pwdData = new GridData();
		pwdData.horizontalAlignment = SWT.CENTER;
		pwdComposite.setLayoutData(pwdData);

		pwdComposite.setLayout(new RowLayout);
		Label labelB = new Label(pwdComposite, SWT.NONE);
		labelB.setText("Password:");
		pwdText_ = new Text(pwdComposite, SWT.SINGLE | SWT.BORDER |
		                                                         SWT.PASSWORD);
		if (pwdMandatory) {
			pwdText_.addListener(SWT.Modify, new class Listener {
				void handleEvent(Event e)
				{
					okButton_.setEnabled(pwdText_.getText().length > 0);
				}
			});
		}
		if (askToSave) {
			saveButton_ = new Button (shell_, SWT.CHECK);
			saveButton_.setText("Save this password");
			auto saveButtonData = new GridData;
			saveButtonData.horizontalAlignment = SWT.CENTER;
			saveButton_.setLayoutData(saveButtonData);
		}

		// main buttons
		Composite buttonComposite = new Composite(shell_, SWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = SWT.CENTER;
		buttonComposite.setLayoutData(buttonData);

		RowLayout buttonLayout = new RowLayout();
		buttonLayout.spacing = BUTTON_SPACING;
		buttonComposite.setLayout(buttonLayout);

		okButton_ = new Button (buttonComposite, SWT.PUSH);
		okButton_.setText ("OK");
		okButton_.setLayoutData(new RowData(BUTTON_SIZE));

		cancelButton_ = new Button (buttonComposite, SWT.PUSH);
		cancelButton_.setText ("Cancel");
		cancelButton_.setLayoutData(new RowData(BUTTON_SIZE));

		auto listener = new ButtonListener;
		okButton_.addListener(SWT.Selection, listener);
		cancelButton_.addListener(SWT.Selection, listener);

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
		return result_ == SWT.OK;
	}


private:
	Shell parent_, shell_;
	Button okButton_, cancelButton_, saveButton_;
	Text pwdText_;
	int result_ = SWT.CANCEL;

	class ButtonListener : Listener {
		void handleEvent (Event event)
		{
			if (event.widget == okButton_)
				result_ = SWT.OK;
			password = pwdText_.getText();
			if (saveButton_ !is null)
				savePassword = saveButton_.getSelection();
			shell_.close();
		}
	}
}


///
class SpecifyServerDialog
{
	///
	this(Shell parent)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, SWT.DIALOG_TRIM | SWT.APPLICATION_MODAL);
		shell_.setLayout(new GridLayout);
		shell_.setText("Add Server");

		// address input
		Composite addressComposite = new Composite(shell_, SWT.NONE);
		GridData addressData = new GridData();
		addressData.horizontalAlignment = SWT.CENTER;
		addressComposite.setLayoutData(addressData);

		addressComposite.setLayout(new GridLayout);
		Label labelB = new Label(addressComposite, SWT.NONE);
		labelB.setText("Please specify an IP address or host name, " ~
		                               "with an optional port number:");
		addressText_ = new Text(addressComposite, SWT.SINGLE | SWT.BORDER);
		auto addressTextData = new GridData();
		addressTextData.horizontalAlignment = SWT.CENTER;
		addressTextData.widthHint = 140;
		addressText_.setLayoutData(addressTextData);

		saveButton_ = new Button(shell_, SWT.CHECK);
		saveButton_.setText("Never remove this server automatically");
		saveButton_.setToolTipText("This is useful for servers that are not" ~
		                           " known to the master server");
		saveButton_.setSelection(
		                  getSessionState("addServersAsPersistent") == "true");
		auto saveButtonData = new GridData;
		saveButtonData.horizontalAlignment = SWT.CENTER;
		saveButton_.setLayoutData(saveButtonData);

		// main buttons
		Composite buttonComposite = new Composite(shell_, SWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = SWT.CENTER;
		buttonComposite.setLayoutData(buttonData);

		RowLayout buttonLayout = new RowLayout();
		buttonLayout.spacing = BUTTON_SPACING;
		buttonComposite.setLayout(buttonLayout);

		okButton_ = new Button (buttonComposite, SWT.PUSH);
		okButton_.setText ("OK");
		okButton_.setLayoutData(new RowData(BUTTON_SIZE));
		cancelButton_ = new Button (buttonComposite, SWT.PUSH);
		cancelButton_.setText ("Cancel");
		cancelButton_.setLayoutData(new RowData(BUTTON_SIZE));

		okButton_.addListener(SWT.Selection, new OkButtonListener);
		cancelButton_.addListener(SWT.Selection, new class Listener {
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
		return result_ == SWT.OK;
	}

	private class OkButtonListener : Listener {
		void handleEvent (Event event)
		{
			shell_.setEnabled(false);

			result_ = SWT.OK;
			string address;

			try {
				// Parse the address using the default Quake 3 port, 27960, as
				// the default.
				string ipOrHost = strip(addressText_.getText());
				ushort port = 27960;
				ptrdiff_t colon = lastIndexOf(ipOrHost, ':');

				if (colon != -1) {
					port = to!ushort(ipOrHost[colon+1..$]);
					ipOrHost = ipOrHost[0..colon];
				}
				log("User adding server: %s port: %s", ipOrHost, port);

				if (ipOrHost.length) {
					address = getAddress(ipOrHost, port)[0].toString();
					log("getAddress returned: %s", address);
				}
			}
			catch (ConvException e) {
				error(e.msg);
			}
			catch (SocketOSException e) {
				error(e.msg);
			}


			if (address.length == 0) {
				shell_.setEnabled(true);
				addressText_.setFocus();
				addressText_.selectAll();
			}
			else {
				ServerList serverList = serverTable.serverList;
				MasterList master = serverList.master;
				ServerHandle sh = master.findServer(address);
				bool persistent = saveButton_.getSelection();

				setSessionState("addServersAsPersistent",
				                                persistent ? "true" : "false");

				if (sh == invalidServerHandle) {
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
						info("That server is already on the list.  If you " ~
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
		int result_ = SWT.CANCEL;
	}
}


///
class SettingsDialog
{
	///
	this(Shell parent)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, SWT.DIALOG_TRIM | SWT.APPLICATION_MODAL);
		shell_.setLayout(new GridLayout());
		shell_.setText("Settings");

		Composite mainComposite = new Composite(shell_, SWT.NONE);
		GridData gridData = new GridData();
		gridData.horizontalAlignment = SWT.CENTER;
		mainComposite.setLayoutData(gridData);
		mainComposite.setLayout(new GridLayout);

		// executable path
		Label labelB = new Label(mainComposite, SWT.NONE);
		labelB.setText("Location of your Quake 3 executable:");
		pathText_ = new Text(mainComposite, SWT.SINGLE | SWT.BORDER);
		pathText_.setText(getSetting("gamePath"));
		gridData = new GridData(GridData.HORIZONTAL_ALIGN_FILL);
		pathText_.setLayoutData(gridData);

		// startup game
		Group startupGroup = new Group(mainComposite, SWT.SHADOW_ETCHED_IN);
		startupGroup.setText("Start with");
		auto startupLayout = new GridLayout();
		startupGroup.setLayout(startupLayout);
		startupDefaultButton_ = new Button(startupGroup, SWT.RADIO);
		startupDefaultButton_.setText("First game");
		startupLastButton_ = new Button(startupGroup, SWT.RADIO);
		startupLastButton_.setText("Last used game");

		if (getSetting("startWithLastMod") == "true")
			startupLastButton_.setSelection(true);
		else
			startupDefaultButton_.setSelection(true);

		// simultaneousQueries
		auto sqComposite = new Composite(mainComposite, SWT.NONE);
		sqComposite.setLayout(new GridLayout(2, false));
		Label sqLabel = new Label(sqComposite, SWT.WRAP);
		sqLabel.setText("Number of servers to query\n" ~
		                "simultaneously, default is 10:");
		sqSpinner_ = new Spinner(sqComposite, SWT.BORDER);
		sqSpinner_.setMinimum(1);
		sqSpinner_.setMaximum(99);
		sqSpinner_.setSelection(getSettingInt("simultaneousQueries"));

		// Colored names
		auto colorComposite = new Composite(mainComposite, 0);
		colorComposite.setLayout(new GridLayout());
		colorButton_ = new Button(colorComposite, SWT.CHECK);
		colorButton_.setText("Show server and player name colors");
		colorButton_.setSelection(getSetting("coloredNames") == "true");

		// Numerical game type column
		auto gtComposite = new Composite(mainComposite, 0);
		gtComposite.setLayout(new GridLayout());
		numGtButton_ = new Button(gtComposite, SWT.CHECK);
		numGtButton_.setText("Show numerical game type column");
		numGtButton_.setSelection(serverTable.numericalGtColumnShown());

		// Cvar columns
		auto cvarComposite = new Composite(mainComposite, 0);
		cvarComposite.setLayout(new GridLayout());
		cvarButton_ = new Button(cvarComposite, SWT.CHECK);
		cvarButton_.setText("Show columns for the game and gamename cvars");
		cvarButton_.setSelection(serverTable.extraColumnsShown());

		// Update checker
		auto updComposite = new Composite(mainComposite, 0);
		updComposite.setLayout(new GridLayout());
		updButton_ = new Button(updComposite, SWT.CHECK);
		updButton_.setText("Check for new version on startup");
		updButton_.setSelection(cast(bool)getSettingInt("checkForUpdates"));

		// main buttons
		Composite buttonComposite = new Composite(shell_, SWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = SWT.CENTER;
		buttonComposite.setLayoutData(buttonData);

		auto buttonLayout = new RowLayout;
		buttonLayout.spacing = BUTTON_SPACING;
		buttonComposite.setLayout(buttonLayout);

		okButton_ = new Button (buttonComposite, SWT.PUSH);
		okButton_.setText ("OK");
		okButton_.setLayoutData(new RowData(BUTTON_SIZE));

		cancelButton_ = new Button (buttonComposite, SWT.PUSH);
		cancelButton_.setText ("Cancel");
		cancelButton_.setLayoutData(new RowData(BUTTON_SIZE));

		Listener listener = new class Listener {
			public void handleEvent (Event event)
			{
				if (event.widget == okButton_) {
					string s;
					result_ = SWT.OK;
					setSetting("gamePath", pathText_.getText);

					s = (startupLastButton_.getSelection()) ? "true" : "false";
					setSetting("startWithLastMod", s);

					int sq = sqSpinner_.getSelection();
					setSetting("simultaneousQueries", to!string(sq));

					s = updButton_.getSelection() ? "1" : "0";
					if (s != "0" && getSettingInt("checkForUpdates") == 0)
						startUpdateChecker();
					setSetting("checkForUpdates", s);

					s = colorButton_.getSelection() ? "true" : "false";
					setSetting("coloredNames", s);
					serverTable.showColoredNames(colorButton_.getSelection());

					serverTable.showNumericalGtColumn(
						                          numGtButton_.getSelection());
					serverTable.showExtraColumns(cvarButton_.getSelection());
				}

				shell_.close();
			}
		};

		okButton_.addListener(SWT.Selection, listener);
		cancelButton_.addListener(SWT.Selection, listener);
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
		return result_ == SWT.OK;
	}

private:
	Shell parent_, shell_;
	Button okButton_, cancelButton_;
	Button startupDefaultButton_, startupLastButton_;
	Text pathText_;
	int result_ = SWT.CANCEL;
	Spinner sqSpinner_;
	Button colorButton_, numGtButton_, cvarButton_, updButton_;
}



/**
 * Takes care of loading and saving passwords, and updating the
 * "saveServerPasswords" setting.  Otherwise like PasswordDialog.
 */
class ServerPasswordDialog : PasswordDialog
{
	///
	this(Shell parent, string title, string message, string address,
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

	private string address_;
	private bool askToSave_;
}


/**
 * Takes care of saving but not loading passwords, and updating the
 * "saveRconPasswords" setting.  Otherwise like PasswordDialog.
 */
class RconPasswordDialog : PasswordDialog
{
	///
	this(Shell parent, in char[] serverName, string address)
	{
		address_ = address;
		super(parent, "Remote Console",
		                "Set password for \"" ~ cast(string)serverName ~ "\"",
		                                                           true, true);
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

	private string address_;
}


private Point center(Control parent, Control child)
{
	Rectangle p = parent.getBounds();
	Rectangle c = child.getBounds();
	int x = p.x + (p.width - c.width) / 2;
	int y = p.y + (p.height - c.height) / 2;

	return new Point(x, y);
}
