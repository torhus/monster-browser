module gui_wx.dialogs;

/* Dialog boxes */

private {
	import std.file;
	import std.format;
	import std.string;

	import wx.wx;
	
	import common;
	import serveractions;
	import serverlist;	
	import settings;
	
	import gui.mainwindow;
	import gui.servertable;
}


void messageBox(char[] title, int style, TypeInfo[] arguments, void* argptr)
{
	void f(Object o) {
		char[] s;
		void f(dchar c) { std.utf.encode(s, c); }

		std.format.doFormat(&f, arguments, argptr);
		MessageBox(s, title, style);
		       //wxWindow *parent = NULL, int x = -1, int y = -1)
		log("messageBox (" ~ title ~ "): " ~ s);

	}

	//syncExec(null, &f);
	f(null);
}


void _messageBox(char[] caption, int icon=Dialog.wxOK)(...)
{
	messageBox(caption, icon, _arguments, _argptr);
}


alias _messageBox!(APPNAME, Dialog.wxICON_INFORMATION) info;
alias _messageBox!("Warning", Dialog.wxICON_EXCLAMATION) warning;
alias _messageBox!("Error", Dialog.wxICON_ERROR) error;
alias _messageBox!("Debug") db;


void db(char[][] a)
{
	db(std.string.join(a, "\n"));
}


/+class MonitorNotify {

	char[] password;

	this(Shell parent, char[] message)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, DWT.DIALOG_TRIM | DWT.APPLICATION_MODAL/* | DWT.ON_TOP*/);
		GridLayout topLayout = new GridLayout();
		shell_.setLayout(topLayout);
		shell_.setText("Monitor Alert");

		shell_.open();
		shell_.forceActive();
		auto display = Display.getDefault();
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
+/

class JoinDialog {

	char[] password;

	this(char[] serverName, char[] message)
	{
		/+parent_ = mainShell;
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
		shell_.setLocation(center(parent_, shell_))
		+/
	}

	int open()
	{
		/+pwdText_.setText(password);
		pwdText_.selectAll();
		shell_.open();
		auto display = Display.getDefault();
		while (!shell_.isDisposed()) {
			if (!display.readAndDispatch()) {
				display.sleep ();
			}
		}
		return result_ == DWT.OK;+/
		return 0;
	}

/+private:
	Shell parent_, shell_;
	Button okButton_, cancelButton_;
	Text pwdText_;
	int result_ = DWT.CANCEL;
+/
}


class SpecifyServerDialog {

	char[] address;

	this(Window parent)
	{
		parent_ = parent;

		dialog_ = new Dialog(parent_, -1, "Specify Server");
		auto panel = new Panel(dialog_, -1);
		panel.sizer = new BoxSizer(Orientation.wxVERTICAL);
	
		auto addressLabel = new wxStaticText(panel, -1,
		                 "Address (123.123.123.123 or 123.123.123.123:12345):");		
		panel.sizer.Add(addressLabel, 0, Alignment.wxALIGN_CENTER_HORIZONTAL);

		addressField_ = new wxTextCtrl(panel, -1, "testing 1 2 3");
		addressField_.SetSizeHints(140, -1);
		panel.sizer.Add(addressField_, 0, Alignment.wxALIGN_CENTER_HORIZONTAL);
		
		saveButton_ = new wxCheckBox(panel, -1,
			      "Save server on file ('" ~ activeMod.extraServersFile ~ "')");
		panel.sizer.Add(saveButton_,0 , Alignment.wxALIGN_CENTER_HORIZONTAL);
		
		// Ok and cancel buttons
		auto buttonSizer = new BoxSizer(Orientation.wxHORIZONTAL);
		panel.sizer.Add(buttonSizer, 0, Alignment.wxALIGN_CENTER_HORIZONTAL);
		
		okButton_ = new wxButton(panel, MenuIDs.wxID_OK);
		buttonSizer.Add(okButton_);
		cancelButton_ = new wxButton(panel, MenuIDs.wxID_CANCEL);
		buttonSizer.Add(cancelButton_);
	
		panel.Fit();
		dialog_.Fit();
	
/+

		Listener listener = new class Listener {
			public void handleEvent (Event event)
			{
				bool closeDialog = true;

				if (event.widget == okButton_) {
					result_ = DWT.OK;
					address = addressText_.getText;

					if (!isValidIpAddress(address)) {
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
							getActiveServerList.addExtraServer(address);
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
					dialog_.close();
			}
		};

		okButton_.addListener(DWT.Selection, listener);
		cancelButton_.addListener(DWT.Selection, listener);
		dialog_.setDefaultButton(okButton_);
		dialog_.pack();
		dialog_.setLocation(center(parent_, dialog_));
+/
	}

	int open()
	{
/+		addressText_.setText(address);
		addressText_.selectAll();
		dialog_.open();
		auto display = Display.getDefault();
		while (!dialog_.isDisposed()) {
			if (!display.readAndDispatch()) {
				display.sleep ();
			}
		}
		return result_;
+/
		dialog_.ShowModal();
		return 0;
	}

private:
	Window parent_;
	Dialog dialog_;
	Button okButton_, cancelButton_;
	CheckBox saveButton_;
	TextCtrl addressField_;
	//int result_ = DWT.CANCEL;

}


class SettingsDialog {
	/+this(Shell parent)
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
				main.filterBar.setMods(settings.modNames);

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
		auto display = Display.getDefault();
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
+/
}


private Point center(Window parent, Window child)
{
	/*Rectangle p = parent.getBounds();
	Rectangle c = child.getBounds();
	int x = p.x + (p.width - c.width) / 2;
	int y = p.y + (p.height - c.height) / 2;

	return Point(x, y);*/
	return Point(-1, -1);
}
