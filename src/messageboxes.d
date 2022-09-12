/**
 * Message boxes, regular and debug ones.
 */

module messageboxes;

import std.string;
import std.utf;
import undead.doformat;

import java.lang.Runnable;
import org.eclipse.swt.SWT;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.MessageBox;

import common;
import mainwindow;


/// Displays a message box.
void messageBox(string msg, string title, int style)
{
	Display.getDefault().syncExec(dgRunnable({
		MessageBox mb;
		if (mainWindow !is null)
			mb = new MessageBox(mainWindow.handle, style);
		else
			mb = new MessageBox(style);

		mb.setText(title);
		mb.setMessage(msg);
		log("messageBox (" ~ title ~ "): " ~ msg);
		mb.open();
	}));
}


void _messageBox(string title, int style)(...)
{
	char[] msg;
	void f(dchar c) { encode(msg, c); }
	doFormat(&f, _arguments, _argptr);
	messageBox(cast(string)msg, title, style);
}

/**
 * Displays message boxes with preset titles and icons.
 * Does formatting, the argument list is (...)
 */
alias _messageBox!(APPNAME, SWT.ICON_INFORMATION) info;
alias _messageBox!("Warning", SWT.ICON_WARNING) warning;  /// ditto
alias _messageBox!("Error", SWT.ICON_ERROR) error;        /// ditto


/// Display a debug message in a dialog box.
void db(...)
{
	debug {
		char[] msg;
		void f(dchar c) { encode(msg, c); }
		doFormat(&f, _arguments, _argptr);
		messageBox(cast(string)msg, "Debug", SWT.NONE);
	}
}


/// Display a multi-line debug message in a dialog box.
void db(string[] array)
{
	debug db(join(array, "\n"));
}
