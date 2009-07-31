module rcon;

import dwt.DWT;
import dwt.dwthelper.Runnable;
import dwt.events.KeyAdapter;
import dwt.events.KeyEvent;
import dwt.events.SelectionAdapter;
import dwt.events.SelectionEvent;
import dwt.events.ShellAdapter;
import dwt.events.ShellEvent;
import dwt.graphics.Device;
import dwt.graphics.Font;
import dwt.graphics.Point;
import dwt.graphics.Rectangle;
import dwt.layout.GridData;
import dwt.layout.GridLayout;
import dwt.widgets.Button;
import dwt.widgets.Display;
import dwt.widgets.Label;
import dwt.widgets.Shell;
import dwt.widgets.Text;

import tango.core.Array;
import tango.core.Thread;
import tango.io.selector.Selector;
import tango.net.DatagramConduit;
import tango.net.InternetAddress;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;

import colorednames;
import common;
import dialogs;
import mainwindow;
import messageboxes;
import settings;


///
class RconWindow
{
	///
	this(in char[] serverName, in char[] address, in char[] password)
	{
		serverName_ = serverName;
		address_ = address;

		shell_ = new Shell(Display.getDefault());
		shell_.setText(serverName ~ " - Remote Console");

		// restore window size and position
		int[] size = parseIntList(getSessionState("rconWindowSize"), 2, 480);
		shell_.setSize(size[0], size[1]);
		int[] oldres = parseIntList(getSessionState("resolution"), 2);
		Rectangle res = Display.getDefault().getBounds();
		if (oldres[0] == res.width && oldres[1] == res.height) {
			int[] pos = parseIntList(getSessionState("rconWindowPosition"), 2,
		                                                                  100);
			shell_.setLocation(pos[0], pos[1]);
		}

		shell_.setImages(mainWindow.handle.getImages());
		shell_.setLayout(new GridLayout(2, false));

		outputText_ = new Text(shell_, DWT.MULTI | DWT.READ_ONLY | DWT.BORDER |
		                                                         DWT.V_SCROLL);
		auto outputTextData = new GridData(DWT.FILL, DWT.FILL, true, true);
		outputTextData.horizontalSpan = 2;
		outputText_.setLayoutData(outputTextData);
		outputText_.setFont(getFixedWidthFont());

		inputText_ = new Text(shell_, DWT.BORDER);
		auto inputTextData = new GridData(DWT.FILL, DWT.CENTER, true, false);
		inputText_.setLayoutData(inputTextData);
		inputText_.addSelectionListener(new MySelectionListener);
		inputText_.setMessage("Type an rcon command and press Enter");
		inputText_.addKeyListener(new InputKeyListener);
		inputText_.setFocus();

		auto passwordButton = new Button(shell_, DWT.PUSH);
		passwordButton.setText("Change Password...");
		passwordButton.addSelectionListener(new class SelectionAdapter
		{
			void widgetSelected(SelectionEvent e)
			{
				onChangePassword();
			}
		});

		// handle shortcut keys that are global (for this window)
		auto commonKeyListener = new CommonKeyListener;
		shell_.addKeyListener(commonKeyListener);
		outputText_.addKeyListener(commonKeyListener);
		inputText_.addKeyListener(commonKeyListener);

		rcon_ = new Rcon(address, password, &deliverOutput);

		shell_.addShellListener(new class ShellAdapter
		{
			void shellClosed(ShellEvent e)
			{
				rcon_.shutdown();  // stop thread
				saveSessionState();
			}
		});
		subWindows ~= shell_;
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
	private void deliverOutput(in char[] s)
	{
		Display.getDefault().syncExec(new class Runnable {
			void run()
			{
				if (outputText_.isDisposed())
					return;
				if (s.length > 0)
					outputText_.append(stripColorCodes(s));
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


	///
	void onChangePassword()
	{
		auto dialog = new RconPasswordDialog(shell_, serverName_, address_);
		dialog.password = rcon_.password;
		if (dialog.open())
			rcon_.password = dialog.password;
	}


	///
	private void saveSessionState()
	{
		if (!shell_.getMaximized()) {
			Point pos = shell_.getLocation();
			setSessionState("rconWindowPosition", toCsv([pos.x, pos.y]));

			Point size = shell_.getSize();
			setSessionState("rconWindowSize", toCsv([size.x, size.y]));
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
		char[] serverName_;
		char[] address_;
		Text outputText_;
		Text inputText_;
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
	char[] password;


	///
	this(in char[] address, in char[] password, void delegate(char[]) output)
	{
		conn_ = new DatagramConduit;
		auto colon = locate(address, ':', 0);
		char[] ip = address[0..colon];
		int port = 27960;
		if (colon < address.length)
			port = Integer.toInt(address[colon+1..$]);
		conn_.connect(new InternetAddress(address, port));
		this.password = password;
		output_ = output;

		Thread thread = new Thread(&receive);
		thread.isDaemon = true;
		thread.name = "rcon";
		thread.start();
	}


	/// Send a command to the server.
	void command(in char[] cmd)
	{
		char[] s = "\xff\xff\xff\xff" ~ "rcon \"" ~ password ~ "\" " ~ cmd;
		size_t written = conn_.write(s);
		if (written < s.length) {
			log(Format("Rcon: Only {} of {} bytes sent.", written, s.length));
			error("An error occurred while sending the command, please check "
			                                               "your connection.");
		}
	}


	///
	void shutdown() { stop_ = true; }


	/// Waits for data in a separate thread, dumps it to output window.
	private void receive()
	{
		char[1024] buf = '\0';
		scope selector = new Selector;

		selector.open(1, 2);
		selector.register(conn_, Event.Read);

		while (true) {
			int eventCount = selector.select(1);
			assert(eventCount >= 0);
			if (stop_)
				break;

			while (eventCount > 0) {
				size_t received = conn_.read(buf);
				assert(received != IConduit.Eof);
				assert(!conn_.hadTimeout);

				const prefix = "\xff\xff\xff\xffprint\n";
				assert(received >= prefix.length);
				assert(buf[0..prefix.length] == prefix);
				output_(buf[prefix.length..received].dup);

				eventCount--;
			}
		}
	}

	private {
		DatagramConduit conn_;
		bool stop_ = false;
		void delegate(char[]) output_;
	}

}

