module dialogs;

/* Dialog boxes */

private {
	import std.file;
	import std.regexp;
	import std.string;

	import dwt.all;

	import common;
	import main;
	import serverlist;
	import settings;
}


class MonitorNotify {

	char[] password;

	this(Shell parent, char[] message)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, DWT.DIALOG_TRIM | DWT.APPLICATION_MODAL/* | DWT.ON_TOP*/);
		GridLayout topLayout = new GridLayout();
		shell_.setLayout(topLayout);
		shell_.setText("Join Server");

		shell_.open();
		shell_.forceActive();
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
		pwdData.horizontalAlignment = GridData.CENTER;
		pwdComposite.setLayoutData(pwdData);

		RowLayout pwdLayout = new RowLayout();
		pwdComposite.setLayout(pwdLayout);
		Label labelB = new Label(pwdComposite, DWT.NONE);
		labelB.setText("Password:");
		pwdText_ = new Text(pwdComposite, DWT.SINGLE | DWT.BORDER);

		// main buttons
		Composite buttonComposite = new Composite(shell_, DWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = GridData.CENTER;
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


class JoinDialog {

	char[] password;

	this(Shell parent, char[] serverName, char[] message)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, DWT.DIALOG_TRIM | DWT.APPLICATION_MODAL);
		GridLayout topLayout = new GridLayout();
		shell_.setLayout(topLayout);
		shell_.setText("Join Server");

		// command line
		Label labelA = new Label(shell_, DWT.NONE);
		labelA.setText("Join \"" ~ serverName ~ "\"\n\n" ~ message ~ "\n");

		// password input
		Composite pwdComposite = new Composite(shell_, DWT.NONE);
		GridData pwdData = new GridData();
		pwdData.horizontalAlignment = GridData.CENTER;
		pwdComposite.setLayoutData(pwdData);

		RowLayout pwdLayout = new RowLayout();
		pwdComposite.setLayout(pwdLayout);
		Label labelB = new Label(pwdComposite, DWT.NONE);
		labelB.setText("Password:");
		pwdText_ = new Text(pwdComposite, DWT.SINGLE | DWT.BORDER);

		// main buttons
		Composite buttonComposite = new Composite(shell_, DWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = GridData.CENTER;
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
	}

	int open()
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
	}

private:
	Shell parent_, shell_;
	Button okButton_, cancelButton_;
	Text pwdText_;
	int result_ = DWT.CANCEL;
}


class SpecifyServerDialog {

	char[] address;

	this(Shell parent)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, DWT.DIALOG_TRIM | DWT.APPLICATION_MODAL);
		GridLayout topLayout = new GridLayout();
		shell_.setLayout(topLayout);
		shell_.setText("Specify Server");

		// command line
		//Label labelA = new Label(shell_, DWT.NONE);
		//labelA.setText("Join \"" ~ serverName ~ "\"\n\n" ~ message ~ "\n");

		// address input
		Composite addressComposite = new Composite(shell_, DWT.NONE);
		GridData addressData = new GridData();
		addressData.horizontalAlignment = GridData.CENTER;
		addressComposite.setLayoutData(addressData);

		auto addressLayout = new GridLayout();
		addressComposite.setLayout(addressLayout);
		Label labelB = new Label(addressComposite, DWT.NONE);
		//Label labelB = new Label(shell_, DWT.NONE);
		labelB.setText("Address (123.123.123.123 or 123.123.123.123:12345):");
		addressText_ = new Text(addressComposite, DWT.SINGLE | DWT.BORDER);
		//pwdText_ = new Text(shell_, DWT.SINGLE | DWT.BORDER);
		auto addressTextData = new GridData(/*GridData.HORIZONTAL_ALIGN_FILL*/);
		addressTextData.horizontalAlignment = GridData.CENTER;
		//labelB.setLayoutData(data);
		//adressTextData.minimumWidth = 200;
		addressTextData.widthHint = 140;
		addressText_.setLayoutData(addressTextData);

		saveButton_ = new Button (shell_, DWT.CHECK);
		saveButton_.setText("Save server on file");

		// main buttons
		Composite buttonComposite = new Composite(shell_, DWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = GridData.CENTER;
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
				bool closeDialog = true;

				if (event.widget == okButton_) {
					result_ = DWT.OK;
					address = addressText_.getText;

					// validate address
					RegExp re = new RegExp(r"(\d{1,3}\.){3}\d{1,3}(:\d{1,5})?");
					char[][] matches = re.exec(address);
					if(matches.length == 0 || matches[0].length != address.length) {
						error("Invalid address");
						addressText_.setFocus();
						addressText_.selectAll();
						closeDialog = false;
					}
					else {
						if (getActiveServerList.getIndex(address) == -1) {
							if (saveButton_.getSelection()) {
								append(activeMod.extraServersFile, address ~ newline);
								// FIXME: error check here (FileException)
							}
							queryAndAddServer(address);
						}
						else {
							info("That server is already on the list.  If you can't see it, "
							        "try turning off the filters.");
							int i = getActiveServerList.getFilteredIndex(address);
							if (i != -1)
								serverTable.reset(new IntWrapper(i));
						}
					}
				}

				if (closeDialog)
					shell_.close();
			}
		};

		okButton_.addListener(DWT.Selection, listener);
		cancelButton_.addListener(DWT.Selection, listener);
		shell_.setDefaultButton(okButton_);
		shell_.pack();
		shell_.setLocation(center(parent_, shell_));
	}

	int open()
	{
		addressText_.setText(address);
		addressText_.selectAll();
		shell_.open();
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
	Text addressText_;
	int result_ = DWT.CANCEL;
}


class SettingsDialog {
	this(Shell parent)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, DWT.DIALOG_TRIM | DWT.APPLICATION_MODAL);
		shell_.setLayout(new GridLayout());
		shell_.setText("Settings");

		Composite mainComposite = new Composite(shell_, DWT.NONE);
		GridData gridData = new GridData();
		gridData.horizontalAlignment = GridData.CENTER;
		mainComposite.setLayoutData(gridData);
		GridLayout mainLayout = new GridLayout();
		mainComposite.setLayout(mainLayout);

		// executable path
		Label labelB = new Label(mainComposite, DWT.NONE);
		labelB.setText("Location of your Quake 3 executable:");
		pathText_ = new Text(mainComposite, DWT.SINGLE | DWT.BORDER);
		pathText_.setText(getSetting("gamePath"));
		gridData = new GridData(GridData.HORIZONTAL_ALIGN_FILL);
		pathText_.setLayoutData(gridData);

		// startup mod
		Group startupGroup = new Group(mainComposite, DWT.SHADOW_ETCHED_IN);
		startupGroup.setText("Start with");
		auto startupLayout = new GridLayout();
		startupGroup.setLayout(startupLayout);
		startupDefaultButton_ = new Button(startupGroup, DWT.RADIO);
		startupDefaultButton_.setText("Default mod");
		startupLastButton_ = new Button(startupGroup, DWT.RADIO);
		startupLastButton_.setText("Last used mod");

		if (getSetting("startWithLastMod") == "true")
			startupLastButton_.setSelection(true);
		else
			startupDefaultButton_.setSelection(true);

		// mods button
		Button modsButton = new Button(mainComposite, DWT.PUSH);
		modsButton.setText("Mods...");
		modsButton.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				Program.launch(settings.modFileName);
			}
		});

		// main buttons
		Composite buttonComposite = new Composite(shell_, DWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = GridData.CENTER;
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
					char s[];
					result_ = DWT.OK;
					setSetting("gamePath", pathText_.getText);

					s = (startupLastButton_.getSelection()) ? "true" : "false";
					setSetting("startWithLastMod", s);
				}
				// in case the mod list was edited
				settings.loadModFile();
				main.filterBar.setMods(settings.mods);

				shell_.close();
			}
		};

		okButton_.addListener(DWT.Selection, listener);
		cancelButton_.addListener(DWT.Selection, listener);
		shell_.setDefaultButton(okButton_);
		shell_.pack();
		shell_.setLocation(center(parent_, shell_));
	}

	int open() {
		shell_.open();
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
	int result_ = DWT.CANCEL;
}


private Point center(Control parent, Control child)
{
	Rectangle p = parent.getBounds();
	Rectangle c = child.getBounds();
	int x = p.x + (p.width - c.width) / 2;
	int y = p.y + (p.height - c.height) / 2;

	return new Point(x, y);
}
