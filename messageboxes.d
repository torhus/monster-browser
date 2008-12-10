/**
 * Message boxes, regular and debug ones.
 */

module messageboxes;

import tango.text.Util;
import tango.text.convert.Format;

import dwt.DWT;
import dwt.dwthelper.Runnable;
import dwt.widgets.Display;
import dwt.widgets.MessageBox;

import common;
import mainwindow;


/// Displays a message box.
void messageBox(char[] msg, char[] title, int style)
{
	Display.getDefault().syncExec(new class Runnable {
		void run() {
			scope MessageBox mb;
			if (mainWindow !is null)
				mb = new MessageBox(mainWindow.handle, style);
			else
				mb = new MessageBox(style);

			mb.setText(title);
			mb.setMessage(msg);
			log("messageBox (" ~ title ~ "): " ~ msg);
			mb.open();
		}
	});
}


void _messageBox(char[] title, int style)(char[] fmt, ...)
{
	char[] msg = Format.convert(_arguments, _argptr, fmt);
	messageBox(msg, title, style);
}

/**
 * Displays message boxes with preset titles and icons.
 * Does formatting, the argument list is: (char[] fmt, ...)
 */
alias _messageBox!(APPNAME, DWT.ICON_INFORMATION) info;
alias _messageBox!("Warning", DWT.ICON_WARNING) warning;  /// ditto
alias _messageBox!("Error", DWT.ICON_ERROR) error;        /// ditto


/// Display a debug message in a dialog box.
void db(in char[] fmt, ...)
{
	debug {
		char[] msg = Format.convert(_arguments, _argptr, fmt);
		messageBox(msg, "Debug", DWT.NONE);
	}
}


/// Display a multi-line debug message in a dialog box.
void db(char[][] array)
{
	debug db(join(array, "\n"));
}
