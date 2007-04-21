module dialogs;

/* Dialog boxes */

import dejavu.lang.JObjectImpl;
import dejavu.lang.String;

import org.eclipse.swt.SWT;
import org.eclipse.swt.graphics.Point;
import org.eclipse.swt.events.SelectionAdapter;
import org.eclipse.swt.events.SelectionEvent;
import org.eclipse.swt.graphics.Rectangle;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.layout.GridLayout;
import org.eclipse.swt.layout.RowLayout;
import org.eclipse.swt.program.Program;
import org.eclipse.swt.widgets.Button;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Control;
import org.eclipse.swt.widgets.Dialog;
import org.eclipse.swt.widgets.Event;
import org.eclipse.swt.widgets.Group;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.Listener;
import org.eclipse.swt.widgets.Shell;
import org.eclipse.swt.widgets.Text;

import common;
import main;
import settings;


class JoinDialog {

	char[] password;

	this(Shell parent, char[] serverName, char[] message)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, SWT.DIALOG_TRIM | SWT.APPLICATION_MODAL);
		GridLayout topLayout = new GridLayout();
		shell_.setLayout(topLayout);
		shell_.setText(new String("Join Server"));

		// command line
		Label labelA = new Label(shell_, SWT.NONE);
		labelA.setText(String.fromUtf8("Join \"" ~ serverName ~ "\"\n\n" ~ message ~ "\n"));

		// password input
		Composite pwdComposite = new Composite(shell_, SWT.NONE);
		GridData pwdData = new GridData();
		pwdData.horizontalAlignment = GridData.CENTER;
		pwdComposite.setLayoutData(pwdData);

		RowLayout pwdLayout = new RowLayout();
		pwdComposite.setLayout(pwdLayout);
		Label labelB = new Label(pwdComposite, SWT.NONE);
		labelB.setText(new String("Password:"));
		pwdText_ = new Text(pwdComposite, SWT.SINGLE | SWT.BORDER);

		// main buttons
		Composite buttonComposite = new Composite(shell_, SWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = GridData.CENTER;
		buttonComposite.setLayoutData(buttonData);

		RowLayout buttonLayout = new RowLayout();
		buttonComposite.setLayout(buttonLayout);

		okButton_ = new Button (buttonComposite, SWT.PUSH);
		okButton_.setText (new String("OK"));
		cancelButton_ = new Button (buttonComposite, SWT.PUSH);
		cancelButton_.setText (new String("Cancel"));

		Listener listener = new class JObjectImpl, Listener {
			public void handleEvent (Event event)
			{
				if (event.widget == okButton_) {
					result_ = SWT.OK;
					password = pwdText_.getText.toUtf8();
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

	int open()
	{
		pwdText_.setText(String.fromUtf8(password));
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
	int result_ = SWT.CANCEL;
}


class SettingsDialog {
	this(Shell parent)
	{
		parent_ = parent;
		shell_ = new Shell(parent_, SWT.DIALOG_TRIM | SWT.APPLICATION_MODAL);
		shell_.setLayout(new GridLayout());
		shell_.setText(new String("Settings"));

		Composite mainComposite = new Composite(shell_, SWT.NONE);
		GridData gridData = new GridData();
		gridData.horizontalAlignment = GridData.CENTER;
		mainComposite.setLayoutData(gridData);
		GridLayout mainLayout = new GridLayout();
		mainComposite.setLayout(mainLayout);

		// executable path
		Label labelB = new Label(mainComposite, SWT.NONE);
		labelB.setText(new String("Location of your Quake 3 executable:"));
		pathText_ = new Text(mainComposite, SWT.SINGLE | SWT.BORDER);
		pathText_.setText(String.fromUtf8(getSetting("gamePath")));
		gridData = new GridData(GridData.HORIZONTAL_ALIGN_FILL);
		pathText_.setLayoutData(gridData);

		// startup mod
		Group startupGroup = new Group(mainComposite, SWT.SHADOW_ETCHED_IN);
		startupGroup.setText(new String("Start with"));
		auto startupLayout = new GridLayout();
		startupGroup.setLayout(startupLayout);
		startupDefaultButton_ = new Button(startupGroup, SWT.RADIO);
		startupDefaultButton_.setText(new String("Default mod"));
		startupLastButton_ = new Button(startupGroup, SWT.RADIO);
		startupLastButton_.setText(new String("Last used mod"));

		if (getSetting("startWithLastMod") == "true")
			startupLastButton_.setSelection(true);
		else
			startupDefaultButton_.setSelection(true);

		// mods button
		Button modsButton = new Button(mainComposite, SWT.PUSH);
		modsButton.setText(new String("Mods..."));
		modsButton.addSelectionListener(new class SelectionAdapter {
			public void widgetSelected(SelectionEvent e)
			{
				Program.launch(String.fromUtf8(settings.modFileName));
			}
		});

		// main buttons
		Composite buttonComposite = new Composite(shell_, SWT.NONE);
		GridData buttonData = new GridData();
		buttonData.horizontalAlignment = GridData.CENTER;
		buttonComposite.setLayoutData(buttonData);

		RowLayout buttonLayout = new RowLayout();
		buttonComposite.setLayout(buttonLayout);

		okButton_ = new Button (buttonComposite, SWT.PUSH);
		okButton_.setText (new String("OK"));
		cancelButton_ = new Button (buttonComposite, SWT.PUSH);
		cancelButton_.setText (new String("Cancel"));

		Listener listener = new class JObjectImpl, Listener {
			public void handleEvent (Event event)
			{
				if (event.widget == okButton_) {
					char s[];
					result_ = SWT.OK;
					setSetting("gamePath", pathText_.getText().toUtf8());

					s = (startupLastButton_.getSelection()) ? "true" : "false";
					setSetting("startWithLastMod", s);
				}
				// in case the mod list was edited
				settings.loadModFile();
				main.filterBar.setMods(settings.mods);

				shell_.close();
			}
		};

		okButton_.addListener(SWT.Selection, listener);
		cancelButton_.addListener(SWT.Selection, listener);
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
