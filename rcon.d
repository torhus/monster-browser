module rcon;

import dwt.DWT;
import dwt.events.KeyAdapter;
import dwt.events.KeyEvent;
import dwt.events.SelectionAdapter;
import dwt.events.SelectionEvent;
import dwt.graphics.Device;
import dwt.graphics.Font;
import dwt.layout.GridData;
import dwt.layout.GridLayout;
import dwt.widgets.Display;
import dwt.widgets.Shell;
import dwt.widgets.Text;

import tango.net.DatagramConduit;
import tango.net.InternetAddress;

import common;
import mainwindow;


///
class RconWindow
{
	private static Font font;  /// A monospaced font.

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
		outputText_.setFont(getFont());

		inputText_ = new Text(shell_, DWT.BORDER);
		auto inputTextData = new GridData(DWT.FILL, DWT.CENTER, true, false);
		inputText_.setLayoutData(inputTextData);
		inputText_.addSelectionListener(new MySelectionListener);
		inputText_.setMessage("Type an rcon command and press Enter");
		inputText_.setFocus();

		// handle shortcut keys that are global (for this window)
		auto commonKeyListener = new CommonKeyListener;
		shell_.addKeyListener(commonKeyListener);
		outputText_.addKeyListener(commonKeyListener);
		inputText_.addKeyListener(commonKeyListener);

		rcon_ = new Rcon(address, port, password);

		shell_.open();
	}

	private class MySelectionListener : SelectionAdapter
	{
		void widgetDefaultSelected(SelectionEvent e)
		{
			char[] cmd = inputText_.getText();
			if (cmd.length > 0) {
				char[] s = rcon_.command(cmd);
				inputText_.setText("");
				outputText_.setText(s);
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
				default:
					break;
			}
		}
	}

	private static Font getFont()
	{
		if (font is null) {
			font = new Font(cast(Device)Display.getDefault(), "Courier new",
		                                                       10, DWT.NORMAL);
			callAtShutdown ~= &font.dispose;
		}
		return font;
	}

	private {
		Shell shell_;
		Text outputText_;
		Text inputText_;
		Rcon rcon_;
	}
}


///
private class Rcon
{
	///
	this(in char[] address, int port, in char[] password)
	{
		conn_ = new DatagramConduit;
		conn_.connect(new InternetAddress(address, port));
		password_ = password;
	}


	/// Run a command on the server, return the output.
	char[] command(in char[] cmd)
	{
		const size_t growBy = 1000;
		char[] buf = new char[growBy];
		size_t total = 0;

		//conn_ = new DatagramConduit;
		//conn_.connect(new InternetAddress("91.121.207.93", 27964));
		conn_.write("\xff\xff\xff\xff" ~ "rcon \"" ~ password_ ~ "\" " ~ cmd);

		while (true) {
			size_t received = conn_.read(buf[total..$]);
			if (received == IConduit.Eof)
				break;
			total += received;
			if (total < buf.length)
				break;
			buf.length = buf.length + growBy;
		}

		//conn_.shutdown();
		//conn_.close();
		//conn_.flush();
		if (total < "\xff\xff\xff\xffprint\n".length) {
			return null;
		}
		else {
			buf = buf[4..total-4];  // first four bytes are just 0xFF
			assert(buf[0..6] == "print\n");
			return buf[6..$];
		}
	}

	private {
		char[] password_;
		DatagramConduit conn_;
	}

}

