/** Various dialog boxes. */

module dialogs;

import tango.io.device.File;
import tango.text.Util;

import org.eclipse.swt.SWT;
import org.eclipse.swt.events.SelectionAdapter;
import org.eclipse.swt.events.SelectionEvent;
import org.eclipse.swt.graphics.Point;
import org.eclipse.swt.graphics.Rectangle;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.layout.GridLayout;
import org.eclipse.swt.layout.RowData;
import org.eclipse.swt.layout.RowLayout;
import org.eclipse.swt.program.Program;
import org.eclipse.swt.widgets.Button;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Control;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Event;
import org.eclipse.swt.widgets.Group;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.Listener;
import org.eclipse.swt.widgets.Shell;
import org.eclipse.swt.widgets.Text;

import common;
import mainwindow;
import messageboxes;
import serveractions;
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
		shell_ = new Shell(parent_, SWT.DIALOG_TRIM | SWT.APPLICATION_MODAL/* | SWT.ON_TOP*/);
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
		Label labelA = new Label(shell_, SWT.NONE);
		labelA.setText("Join \"" ~ serverName ~ "\"\n\n" ~ message ~ "\n");

		// password input
		Composite pwdComposite = new Composite(shell_, SWT.NONE);
		GridData pwdData = new GridData();
		pwdData.horizontalAlignment = SWT.CENTER;
		pwdComposite.setLayoutData(pwdData);

		RowLayout pwdLayout = new RowLayout();
		pwdComposite.setLayout(pwdLayout);
		Label labelB = new Label(pwdComposite, SWT.NONE);
		labelB.setText("Password:");
		pwdText_ = new Text(pwdComposite, SWT.SINGLE | SWT.BORDER);

		// main buttons
		Composite buttonComposite = new Composite(shell_, SWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = SWT.CENTER;
		buttonComposite.setLayoutData(buttonData);

		RowLayout buttonLayout = new RowLayout();
		buttonComposite.setLayout(buttonLayout);

		okButton_ = new Button (buttonComposite, SWT.PUSH);
		okButton_.setText ("OK");
		cancelButton_ = new Button (buttonComposite, SWT.PUSH);
		cancelButton_.setText ("Cancel");

		Listener listener = new class Listener {
			public void handleEvent (Event event)
			{
				if (event.widget == okButton_) {
					result_ = SWT.OK;
					password = pwdText_.getText;
				}
				shell_.close();
			}
		};

		okButton_.addListener(SWT.Selection, listener);
		cancelButton_.addListener(SWT.Selection, listener);
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
	this(Shell parent, char[] serverName, char[] message)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, SWT.DIALOG_TRIM | SWT.APPLICATION_MODAL);
		shell_.setLayout(new GridLayout);
		shell_.setText("Join Server");

		// command line
		Label labelA = new Label(shell_, SWT.NONE);
		labelA.setText("Join \"" ~ serverName ~ "\"\n\n" ~ message ~ "\n");

		// password input
		Composite pwdComposite = new Composite(shell_, SWT.NONE);
		GridData pwdData = new GridData();
		pwdData.horizontalAlignment = SWT.CENTER;
		pwdComposite.setLayoutData(pwdData);

		pwdComposite.setLayout(new RowLayout);
		Label labelB = new Label(pwdComposite, SWT.NONE);
		labelB.setText("Password:");
		pwdText_ = new Text(pwdComposite, SWT.SINGLE | SWT.BORDER);

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

		Listener listener = new class Listener {
			public void handleEvent (Event event)
			{
				if (event.widget == okButton_) {
					result_ = SWT.OK;
					password = pwdText_.getText;
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

	int open() ///
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
		return result_;
	}

private:
	Shell parent_, shell_;
	Button okButton_, cancelButton_;
	Text pwdText_;
	int result_ = SWT.CANCEL;
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
		shell_.setText("Specify Server");

		// address input
		Composite addressComposite = new Composite(shell_, SWT.NONE);
		GridData addressData = new GridData();
		addressData.horizontalAlignment = SWT.CENTER;
		addressComposite.setLayoutData(addressData);

		addressComposite.setLayout(new GridLayout);
		Label labelB = new Label(addressComposite, SWT.NONE);
		labelB.setText("Address (123.123.123.123 or 123.123.123.123:12345):");
		addressText_ = new Text(addressComposite, SWT.SINGLE | SWT.BORDER);
		auto addressTextData = new GridData();
		addressTextData.horizontalAlignment = SWT.CENTER;
		addressTextData.widthHint = 140;
		addressText_.setLayoutData(addressTextData);

		saveButton_ = new Button (shell_, SWT.CHECK);
		char[] file = getGameConfig(filterBar.selectedGame).extraServersFile;
		saveButton_.setText("Save server on file ('" ~ file ~ "')");
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

		Listener listener = new class Listener {
			public void handleEvent (Event event)
			{
				bool closeDialog = true;

				if (event.widget == okButton_) {
					result_ = SWT.OK;
					address = trim(addressText_.getText);

					if (!isValidIpAddress(address)) {
						error("Invalid address");
						addressText_.setFocus();
						addressText_.selectAll();
						closeDialog = false;
					}
					else {
						auto serverList = serverTable.serverList;
						if (serverList.getIndex(address) == -1) {
							if (saveButton_.getSelection()) {
								if (!(address in serverList.extraServers)) {
									GameConfig game =
									        getGameConfig(serverList.gameName);
									char[] file = game.extraServersFile;
									// FIXME: error check here (FileException)
									File.append(file, address ~ newline);
								}
							}
							serverList.addExtraServer(address);
							queryServers([address], false, true);
						}
						else {
							info("That server is already on the list.  If you can't see it, "
							        "try turning off the filters.");
							int i = serverList.getFilteredIndex(address);
							if (i != -1)
								serverTable.fullRefresh(i);
						}
					}
				}

				if (closeDialog)
					shell_.close();
			}
		};

		okButton_.addListener(SWT.Selection, listener);
		cancelButton_.addListener(SWT.Selection, listener);
		shell_.setDefaultButton(okButton_);
		shell_.pack();
		shell_.setLocation(center(parent_, shell_));
	}

	int open()
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
		return result_;
	}

private:
	Shell parent_, shell_;
	Button okButton_, cancelButton_, saveButton_;
	char[] address = "";
	Text addressText_;
	int result_ = SWT.CANCEL;
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
		startupDefaultButton_.setText("Default game");
		startupLastButton_ = new Button(startupGroup, SWT.RADIO);
		startupLastButton_.setText("Last used game");

		if (getSetting("startWithLastMod") == "true")
			startupLastButton_.setSelection(true);
		else
			startupDefaultButton_.setSelection(true);

		// games button
		Button gamesButton = new Button(mainComposite, SWT.PUSH);
		gamesButton.setText("Games...");
		gamesButton.setLayoutData(new GridData(BUTTON_SIZE));
		gamesButton.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				Program.launch(settings.gamesFileName);
			}
		});

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
					char s[];
					result_ = SWT.OK;
					setSetting("gamePath", pathText_.getText);

					s = (startupLastButton_.getSelection()) ? "true" : "false";
					setSetting("startWithLastMod", s);
				}
				// in case the game list was edited
				settings.loadGamesFile();
				filterBar.setGames(settings.gameNames);

				shell_.close();
			}
		};

		okButton_.addListener(SWT.Selection, listener);
		cancelButton_.addListener(SWT.Selection, listener);
		shell_.setDefaultButton(okButton_);
		shell_.pack();
		shell_.setLocation(center(parent_, shell_));
	}

	int open() ///
	{
		shell_.open();
		Display display = Display.getDefault;
		while (!shell_.isDisposed()) {
			if (!display.readAndDispatch()) {
				display.sleep();
			}
		}
		return result_;
	}

private:
	Shell parent_, shell_;
	Button okButton_, cancelButton_;
	Button startupDefaultButton_, startupLastButton_;
	Text pathText_;
	int result_ = SWT.CANCEL;
}


private Point center(Control parent, Control child)
{
	Rectangle p = parent.getBounds();
	Rectangle c = child.getBounds();
	int x = p.x + (p.width - c.width) / 2;
	int y = p.y + (p.height - c.height) / 2;

	return new Point(x, y);
}
