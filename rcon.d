module rcon;

import dwt.DWT;
import dwt.dwthelper.Runnable;
import dwt.events.KeyAdapter;
import dwt.events.KeyEvent;
import dwt.events.SelectionAdapter;
import dwt.events.SelectionEvent;
import dwt.graphics.Device;
import dwt.graphics.Font;
import dwt.layout.GridData;
import dwt.layout.GridLayout;
import dwt.widgets.Display;
import dwt.widgets.Label;
import dwt.widgets.Shell;
import dwt.widgets.Text;

import tango.core.Array;
import tango.core.Thread;
import tango.net.DatagramConduit;
import tango.net.InternetAddress;
import tango.text.convert.Format;

import colorednames;
import common;
import mainwindow;
import messageboxes;


///
class RconWindow
{
	///
	this(in char[] serverName, in char[] address, int port, in char[] password)
	{
		shell_ = new Shell(Display.getDefault());
		shell_.setText("Remote Console for " ~ serverName);
		shell_.setSize(640, 480);  // FIXME: save and restore size
		shell_.setImages(mainWindow.handle.getImages());
		shell_.setLayout(new GridLayout);

		outputText_ = new Text(shell_, DWT.MULTI | DWT.READ_ONLY | DWT.BORDER |
		                                                         DWT.V_SCROLL);
		auto outputTextData = new GridData(DWT.FILL, DWT.FILL, true, true);
		outputText_.setLayoutData(outputTextData);
		outputText_.setFont(getFixedWidthFont());

		inputText_ = new Text(shell_, DWT.BORDER);
		auto inputTextData = new GridData(DWT.FILL, DWT.CENTER, true, false);
		inputText_.setLayoutData(inputTextData);
		inputText_.addSelectionListener(new MySelectionListener);
		//inputText_.setMessage("Type an rcon command and press Enter");
		inputText_.addKeyListener(new InputKeyListener);
		inputText_.setFocus();

		statusLabel_ = new Label(shell_, DWT.NONE);
		statusLabel_.setText("Type an rcon command and press Enter");

		// handle shortcut keys that are global (for this window)
		auto commonKeyListener = new CommonKeyListener;
		shell_.addKeyListener(commonKeyListener);
		outputText_.addKeyListener(commonKeyListener);
		inputText_.addKeyListener(commonKeyListener);

		rcon_ = new Rcon(address, port, password, &deliverOutput);

		shell_.open();
	}

	/// Add a command to the command history.
	private void storeCommand(in char[] cmd)
	{
		// add cmd at the end, or move it there if already present
		if (remove(history_, cmd) == history_.length)
			history_ ~= cmd;
		position_ = history_.length;
	}


	///
	private void deliverOutput(in char[] s, bool timeout)
	{
		Display.getDefault().syncExec(new class Runnable {
			void run()
			{
				if (outputText_.isDisposed())
					return;

				if (s.length > 0) {
					outputText_.append(stripColorCodes(s));
					statusLabel_.setText("");
				}
				else if (timeout) {
					statusLabel_.setText("Timed out");
				}
				else {
					statusLabel_.setText("Got nothing");
				}
			}
		});
	}


	private class MySelectionListener : SelectionAdapter
	{
		void widgetDefaultSelected(SelectionEvent e)
		{
			char[] cmd = inputText_.getText();
			if (cmd.length > 0) {
				rcon_.command(cmd);
				inputText_.setText("");
				storeCommand(cmd);
			}
		}

	}

	private class CommonKeyListener : KeyAdapter
	{
		void keyPressed(KeyEvent e)
		{
			switch (e.keyCode) {
				case DWT.ESC:
					if ((e.stateMask & DWT.MODIFIER_MASK) == 0) {
						shell_.close();
					}
					break;
				case 'a':
					// CTRL+A doesn't work by default
					if (e.stateMask == DWT.MOD1) {
						(cast(Text)e.widget).selectAll();
						e.doit = false;
					}
					break;
				default:
					break;
			}
		}
	}

	private class InputKeyListener : KeyAdapter
	{
		void keyPressed(KeyEvent e)
		{
			switch (e.keyCode) {
				case DWT.ARROW_UP:
					if ((e.stateMask & DWT.MODIFIER_MASK) == 0) {
						e.doit = false;
						if (history_.length == 0)
							return;
						if (position_ > 0)
							position_--;
						inputText_.setText(history_[position_]);
						// move cursor to end of line
						inputText_.setSelection (inputText_.getCharCount());
					}
					break;
				case DWT.ARROW_DOWN:
					if ((e.stateMask & DWT.MODIFIER_MASK) == 0) {
						e.doit = false;
						if (history_.length > 0 &&
						                     position_ < history_.length - 1) {
							inputText_.setText(history_[++position_]);
						}
						else {
							inputText_.setText("");
							position_ = history_.length;
						}
						// move cursor to end of line
						inputText_.setSelection (inputText_.getCharCount());
					}
					break;
				case DWT.PAGE_UP:
					if ((e.stateMask & DWT.MODIFIER_MASK) == 0)
						outputPageScroll(false);
					break;
				case DWT.PAGE_DOWN:
					if ((e.stateMask & DWT.MODIFIER_MASK) == 0)
						outputPageScroll(true);
					break;
				default:
					break;
			}
		}
	}

	/// Scroll output field up or down by a page.
	private void outputPageScroll(bool down)
	{
		// FIXME: getClientArea().height seems to include some sort of margin,
		// so linesPerPage will be one too many sometimes.
		int visibleHeight = outputText_.getClientArea().height;
		int linesPerPage = visibleHeight / outputText_.getLineHeight();
		int scrollBy = down ? linesPerPage - 1 : -linesPerPage + 1;
		outputText_.setTopIndex(outputText_.getTopIndex() + scrollBy);
	}

	private static Font getFixedWidthFont()
	{
		if (fixedWidthFont is null) {
			fixedWidthFont = new Font(cast(Device)Display.getDefault(),
			                                    "Courier new", 10, DWT.NORMAL);
			callAtShutdown ~= &fixedWidthFont.dispose;
		}
		return fixedWidthFont;
	}

	private {
		Shell shell_;
		Text outputText_;
		Text inputText_;
		Label statusLabel_;
		Rcon rcon_;
		char[][] history_;
		int position_ = 0;  // index into history_

		static Font fixedWidthFont;  /// A monospaced font.
	}
}


///
private class Rcon
{
	///
	this(in char[] address, int port, in char[] password,
	                                        void delegate(char[], bool) output)
	{
		conn_ = new DatagramConduit;
		conn_.connect(new InternetAddress(address, port));
		conn_.setTimeout(4);
		password_ = password;
		output_ = output;
	}


	/// Send a command to the server.
	void command(in char[] cmd)
	{
		//conn_ = new DatagramConduit;
		//conn_.connect(new InternetAddress("91.121.207.93", 27964));
		char[] s = "\xff\xff\xff\xff" ~ "rcon \"" ~ password_ ~ "\" " ~ cmd;
		size_t written = conn_.write(s);
		if (written < s.length) {
			log(Format("Rcon: Only {} of {} bytes sent.", written, s.length));
			error("An error occurred while sending the\n"
			      "command, please check your connection.");
		}
		else {
			// FIXME: use only one thread, with timeout.
			// maybe need to use semaphore
			Thread t = new Thread(&receive);
			t.name = "rcon";
			t.start();
		}
	}

	private void receive()
	{
		char[1024] buf = void;

		size_t received = conn_.read(buf);
		assert(received != IConduit.Eof);

		const prefix = "\xff\xff\xff\xffprint\n";
		assert(received >= prefix.length);
		if (received < prefix.length) {
			output_(null, conn_.hadTimeout);
		}
		else {
			assert(buf[0..prefix.length] == prefix);
			output_(buf[prefix.length..received].dup, conn_.hadTimeout);
		}
	}

	private {
		char[] password_;
		DatagramConduit conn_;
		void delegate(char[], bool) output_;
	}

}

