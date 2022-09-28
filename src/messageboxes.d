/**
 * Message boxes, regular and debug ones.
 */

module messageboxes;

import std.format;
import std.string;
import std.utf;

import java.lang.Runnable;
import org.eclipse.swt.SWT;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.MessageBox;

import common;
import mainwindow;


/// Displays a message box.
void messageBox(string msg, string title, int style)
{
	if (Display.getDefault().isDisposed())
		return;

	Display.getDefault().syncExec(dgRunnable({
		MessageBox mb;

		
		if (mainWindow && mainWindow.handle.isDisposed())
			return;

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


private template _messageBox(string title, int style)
{
	void _messageBox(T...)(T args)
	{
		messageBox(format(args), title, style);
	}
}

/**
 * Displays message boxes with preset titles and icons.
 * Does formatting, the argument list is (...).
 */
alias _messageBox!(APPNAME, SWT.ICON_INFORMATION) info;
alias _messageBox!("Warning", SWT.ICON_WARNING) warning;  /// ditto
alias _messageBox!("Error", SWT.ICON_ERROR) error;        /// ditto


/// Display a debug message in a dialog box.
void db(T...)(T args)
{
	debug messageBox(format(args), "Debug", SWT.NONE);
}


/// Display a multi-line debug message in a dialog box.
void db(string[] array)
{
	debug db(join(array, "\n"));
}
