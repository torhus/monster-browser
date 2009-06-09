/** Various dialog boxes. */

module dialogs;

import tango.io.device.File;
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


class MonitorNotify
{
	char[] password; ///

	///
	this(Shell parent, char[] message)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, DWT.DIALOG_TRIM | DWT.APPLICATION_MODAL/* | DWT.ON_TOP*/);
		shell_.setLayout(new GridLayout);
		shell_.setText("Join Server");

		shell_.open();
		shell_.forceActive();
		Display display = Display.getDefault;
		while (!shell_.isDisposed()) {
			if (!display.readAndDispatch()) {
				display.sleep ();
			}
		}

		/*// command line
		Label labelA = new Label(shell_, DWT.NONE);
		labelA.setText("Join \"" ~ serverName ~ "\"\n\n" ~ message ~ "\n");

		// password input
		Composite pwdComposite = new Composite(shell_, DWT.NONE);
		GridData pwdData = new GridData();
		pwdData.horizontalAlignment = DWT.CENTER;
		pwdComposite.setLayoutData(pwdData);

		RowLayout pwdLayout = new RowLayout();
		pwdComposite.setLayout(pwdLayout);
		Label labelB = new Label(pwdComposite, DWT.NONE);
		labelB.setText("Password:");
		pwdText_ = new Text(pwdComposite, DWT.SINGLE | DWT.BORDER);

		// main buttons
		Composite buttonComposite = new Composite(shell_, DWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = DWT.CENTER;
		buttonComposite.setLayoutData(buttonData);

		RowLayout buttonLayout = new RowLayout();
		buttonComposite.setLayout(buttonLayout);

		okButton_ = new Button (buttonComposite, DWT.PUSH);
		okButton_.setText ("OK");
		cancelButton_ = new Button (buttonComposite, DWT.PUSH);
		cancelButton_.setText ("Cancel");

		Listener listener = new class Listener {
			public void handleEvent (Event event)
			{
				if (event.widget == okButton_) {
					result_ = DWT.OK;
					password = pwdText_.getText;
				}
				shell_.close();
			}
		};

		okButton_.addListener(DWT.Selection, listener);
		cancelButton_.addListener(DWT.Selection, listener);
		shell_.setDefaultButton(okButton_);
		shell_.pack();
		shell_.setLocation(center(parent_, shell_));
		*/
	}

	/*int open()
	{
		pwdText_.setText(password);
		pwdText_.selectAll();
		shell_.open();
		while (!shell_.isDisposed()) {
			if (!display.readAndDispatch()) {
				display.sleep ();
			}
		}
		return result_;
	}*/

private:
	Shell parent_, shell_;

}


///
class JoinDialog
{
	char[] password = ""; ///

	///
	this(Shell parent, char[] serverName, char[] message, bool pwdMandatory)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, DWT.DIALOG_TRIM | DWT.APPLICATION_MODAL);
		shell_.setLayout(new GridLayout);
		shell_.setText("Join Server");

		// command line
		Label labelA = new Label(shell_, DWT.NONE);
		labelA.setText("Join \"" ~ serverName ~ "\"\n\n" ~ message ~ "\n");

		// password input
		Composite pwdComposite = new Composite(shell_, DWT.NONE);
		GridData pwdData = new GridData();
		pwdData.horizontalAlignment = DWT.CENTER;
		pwdComposite.setLayoutData(pwdData);

		pwdComposite.setLayout(new RowLayout);
		Label labelB = new Label(pwdComposite, DWT.NONE);
		labelB.setText("Password:");
		pwdText_ = new Text(pwdComposite, DWT.SINGLE | DWT.BORDER);

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

		Listener listener = new MyListener;

		okButton_.addListener(DWT.Selection, listener);
		cancelButton_.addListener(DWT.Selection, listener);
		if (pwdMandatory)
			pwdText_.addListener(DWT.Modify, listener);

		shell_.setDefaultButton(okButton_);
		shell_.pack();
		shell_.setLocation(center(parent_, shell_));
	}

	bool open() ///
	{
		pwdText_.setText(password);
		pwdText_.selectAll();
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
	Button okButton_, cancelButton_;
	Text pwdText_;
	int result_ = DWT.CANCEL;

	class MyListener : Listener {
		void handleEvent (Event event)
		{
			switch (event.type) {
				case DWT.Selection:
					if (event.widget == okButton_) {
						result_ = DWT.OK;
						password = pwdText_.getText;
					}
					shell_.close();
					break;
				case DWT.Modify:
					if (pwdText_.getText().length > 0)
						okButton_.setEnabled(true);
					else
						okButton_.setEnabled(false);
					break;
			}
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
		shell_.setText("Specify Server");

		// address input
		Composite addressComposite = new Composite(shell_, DWT.NONE);
		GridData addressData = new GridData();
		addressData.horizontalAlignment = DWT.CENTER;
		addressComposite.setLayoutData(addressData);

		addressComposite.setLayout(new GridLayout);
		Label labelB = new Label(addressComposite, DWT.NONE);
		labelB.setText("Address (123.123.123.123 or 123.123.123.123:12345):");
		addressText_ = new Text(addressComposite, DWT.SINGLE | DWT.BORDER);
		auto addressTextData = new GridData();
		addressTextData.horizontalAlignment = DWT.CENTER;
		addressTextData.widthHint = 140;
		addressText_.setLayoutData(addressTextData);

		saveButton_ = new Button (shell_, DWT.CHECK);
		char[] file = getGameConfig(filterBar.selectedGame).extraServersFile;
		saveButton_.setText("Save server on file ('" ~ file ~ "')");
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
		addressText_.setText(address);
		addressText_.selectAll();
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
			result_ = DWT.OK;
			address = trim(addressText_.getText);

			if (!isValidIpAddress(address)) {
				error("Invalid address");
				addressText_.setFocus();
				addressText_.selectAll();
			}
			else {
				ServerList serverList = serverTable.serverList;
				MasterList master = serverList.master;
				ServerHandle sh = master.findServer(address);

				if (sh == InvalidServerHandle) {
					if (saveButton_.getSelection()) {
						if (!(address in serverList.extraServers)) {
							GameConfig game =
							                getGameConfig(serverList.gameName);
							char[] file = game.extraServersFile;
							// FIXME: error check here (IOException)
							File.append(file, address ~ newline);
						}
					}
					serverList.addExtraServer(address);
					queryServers([address], false, true);
				}
				else {
					ServerData sd = master.getServerData(sh);
					GameConfig game = getGameConfig(serverList.gameName);

					if (matchMod(&sd, game.mod)) {
						info("That server is already on the list.  If you "
						         "can't see it, try turning off the filters.");
						int i = serverList.getFilteredIndex(address);
						if (i != -1)
							serverTable.setSelection([i], true);
					}
					else {
						info("That server is already known, but belongs to a "
						                             "different game or mod.");
					}
				}
				shell_.close();
			}
		}
	}


	private {
		Shell parent_, shell_;
		Button okButton_, cancelButton_, saveButton_;
		char[] address = "";
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
		startupDefaultButton_.setText("Default game");
		startupLastButton_ = new Button(startupGroup, DWT.RADIO);
		startupLastButton_.setText("Last used game");

		if (getSetting("startWithLastMod") == "true")
			startupLastButton_.setSelection(true);
		else
			startupDefaultButton_.setSelection(true);

		// simultaneousQueries
		auto sqComposite = new Composite(mainComposite, DWT.NONE);
		sqComposite.setLayout(new RowLayout);
		Label sqLabel = new Label(sqComposite, DWT.WRAP);
		sqLabel.setText("Number of servers to query\n"
		                "simultaneously, default is 20:");
		sqSpinner_ = new Spinner(sqComposite, DWT.BORDER);
		sqSpinner_.setMinimum(1);
		sqSpinner_.setMaximum(99);
		uint ate;
		int val = Integer.convert(getSetting("simultaneousQueries"), 10, &ate);
		sqSpinner_.setSelection(ate > 0 ? val : 20);

		// games button
		Button gamesButton = new Button(mainComposite, DWT.PUSH);
		gamesButton.setText("Games...");
		gamesButton.setLayoutData(new GridData(BUTTON_SIZE));
		gamesButton.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				Program.launch(settings.gamesFileName);
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
				settings.loadGamesFile();
				filterBar.setGames(settings.gameNames);

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
	Text pathText_;
	int result_ = DWT.CANCEL;
	Spinner sqSpinner_;
}


private Point center(Control parent, Control child)
{
	Rectangle p = parent.getBounds();
	Rectangle c = child.getBounds();
	int x = p.x + (p.width - c.width) / 2;
	int y = p.y + (p.height - c.height) / 2;

	return new Point(x, y);
}
