module rcon;

import java.lang.Runnable;
import org.eclipse.swt.SWT;
import org.eclipse.swt.events.KeyAdapter;
import org.eclipse.swt.events.KeyEvent;
import org.eclipse.swt.events.SelectionAdapter;
import org.eclipse.swt.events.SelectionEvent;
import org.eclipse.swt.events.ShellAdapter;
import org.eclipse.swt.events.ShellEvent;
import org.eclipse.swt.graphics.Device;
import org.eclipse.swt.graphics.Font;
import org.eclipse.swt.graphics.Point;
import org.eclipse.swt.graphics.Rectangle;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.layout.GridLayout;
import org.eclipse.swt.widgets.Button;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.Shell;
import org.eclipse.swt.widgets.Text;

import core.thread;
import std.conv;
import std.socket;
import std.string;
version (Windows)
	import std.c.windows.winsock;
import tango.core.Array;
import Integer = tango.text.convert.Integer;

import colorednames;
import common;
import dialogs;
import mainwindow;
import messageboxes;
import settings;



///
bool openRconWindow(string serverName, string address, string password) {

	Rcon rcon;

	try {
		rcon = new Rcon(address, password);
	}
	catch (SocketException e) {
		error(e.toString());
	}

	if (rcon) {
		new RconWindow(serverName, rcon);
		return true;
	}

	return false;
}


///
class RconWindow
{
	///
	this(string serverName, Rcon rcon)
	{
		serverName_ = serverName;
		assert(rcon);
		rcon_ = rcon;
		rcon_.output = &deliverOutput;

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

		outputText_ = new Text(shell_, SWT.MULTI | SWT.READ_ONLY | SWT.BORDER |
		                                                         SWT.V_SCROLL);
		auto outputTextData = new GridData(SWT.FILL, SWT.FILL, true, true);
		outputTextData.horizontalSpan = 2;
		outputText_.setLayoutData(outputTextData);
		outputText_.setFont(getFixedWidthFont());

		inputText_ = new Text(shell_, SWT.BORDER);
		auto inputTextData = new GridData(SWT.FILL, SWT.CENTER, true, false);
		inputText_.setLayoutData(inputTextData);
		inputText_.addSelectionListener(new MySelectionListener);
		inputText_.setMessage("Type an rcon command and press Enter");
		inputText_.addKeyListener(new InputKeyListener);
		inputText_.setFocus();

		auto passwordButton = new Button(shell_, SWT.PUSH);
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
	private void storeCommand(string cmd)
	{
		// add cmd at the end, or move it there if already present
		if (remove(history_, cmd) == history_.length)
			history_ ~= cmd;
		position_ = history_.length;
	}


	///
	private void deliverOutput(const(char)[] s)
	{
		Display.getDefault().syncExec(dgRunnable( {
			if (outputText_.isDisposed())
				return;
			if (s.length > 0)
				outputText_.append(stripColorCodes(s));
		}));
	}


	private class MySelectionListener : SelectionAdapter
	{
		void widgetDefaultSelected(SelectionEvent e)
		{
			string cmd = inputText_.getText();
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
				case SWT.ESC:
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0) {
						shell_.close();
					}
					break;
				case 'a':
					// CTRL+A doesn't work by default
					if (e.stateMask == SWT.MOD1) {
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
				case SWT.ARROW_UP:
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0) {
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
				case SWT.ARROW_DOWN:
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0) {
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
				case SWT.PAGE_UP:
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0)
						outputPageScroll(false);
					break;
				case SWT.PAGE_DOWN:
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0)
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
		auto dialog = new RconPasswordDialog(shell_, serverName_,
		                                                        rcon_.address);
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
			                                    "Courier new", 10, SWT.NORMAL);
			callAtShutdown ~= &fixedWidthFont.dispose;
		}
		return fixedWidthFont;
	}

	private {
		Shell shell_;
		string serverName_;
		Text outputText_;
		Text inputText_;
		Rcon rcon_;
		string[] history_;
		int position_ = 0;  // index into history_

		static Font fixedWidthFont;  /// A monospaced font.
	}
}


///
private class Rcon
{
	///
	string password;


	/**
	* Throws: SocketException if unable to connect.
	*/
	this(string address, string password)
	{
		address_ = address;

		// Workaround for Phobos 2 calling WSACleanup in its per-thread module
		// destructor. http://d.puremagic.com/issues/show_bug.cgi?id=4344
		version (Windows) {
			WSADATA wd;
			WSAStartup(0x2020, &wd);
		}

		socket_ = new UdpSocket;
		socket_.connect(parseAddress(address_));
		this.password = password;

		Thread thread = new Thread(&receive);
		thread.isDaemon = true;
		thread.name = "rcon";
		thread.start();
	}


	/// Send a command to the server.
	void command(in char[] cmd)
	{
		assert(output_);

		char[] s = "\xff\xff\xff\xff" ~ "rcon \"" ~ password ~ "\" " ~ cmd;
		size_t written = socket_.sendTo(s);
		if (written == Socket.ERROR || written < s.length) {
			log("Rcon: Only %s of %s bytes sent.", written, s.length);
			error("An error occurred while sending the command, please check "
			                                               "your connection.");
		}
	}


	///
	string address() { return address_; }


	///
	void shutdown() { closed_ = true; socket_.close(); }


	/// Sets the sink that receives the output.
	private void output(void delegate(const(char)[]) dg) { output_ = dg;  }


	/// Waits for data, dumps it to output window.
	private void receive()
	{
		char[1024] buf = '\0';

		while (true) {
			auto received = socket_.receiveFrom(buf);

			if (received == 0) {
				error("remote side closed connection");
			}
			else if (received == Socket.ERROR) {
				if (!closed_)
					error("socket.receive returned ERROR");
				else
					break;
			}
			else {
				const prefix = "\xff\xff\xff\xffprint\n";
				assert(received >= prefix.length);
				assert(buf[0..prefix.length] == prefix);
				output_(buf[prefix.length..received].dup);
			}
		}
	}


	/// Parse a.b.c.d:e.
	private InternetAddress parseAddress(string addr)
	{
		ushort port;

		int colon = addr.lastIndexOf(':');
		if (colon == -1 || addr.length < colon + 2) {
			log("Missing port number for " ~ addr ~ ", using PORT_ANY");
			db("Missing port number for " ~ addr);
			port = InternetAddress.PORT_ANY;
		}
		else {
			port = to!ushort(addr[colon+1..$]);
		}
		return new InternetAddress(addr[0..colon], port);
	}

	private {
		Socket socket_;
		bool closed_ = false;
		string address_;
		void delegate(const(char)[]) output_;
	}

}

