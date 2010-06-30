module serverqueue;

import java.lang.Runnable;
import org.eclipse.swt.widgets.Display;

import common;
import masterlist;
import servertable;


///
final class ServerQueue
{
	///
	this(bool delegate(ServerHandle sh) addDg)
	{
		addDg_ = addDg;
		Display.getDefault.syncExec(new TimerTask);
	}


	///
	void add(ServerHandle sh)
	{
		synchronized (this) list_ ~= sh;
	}


	///
	void stop(bool addRemaining)
	{
		if (addRemaining) {
			Display.getDefault.syncExec(dgRunnable( {
				synchronizedAdd();
			}));
		}
		stop_ = true;
	}


	/// Note: Must be called by the GUI thread.
	private class TimerTask : Runnable {
		void run()
		{
			if (stop_)
				return;
			synchronizedAdd;
			Display.getDefault.timerExec(100, this);
		}
	}


	/// Note: Must be called by the GUI thread.
	private void synchronizedAdd()
	{
		if (list_.length == 0)
			return;

		synchronized (this) {
			if (stop_)
				return;
			if (addAll() && !arguments.norefresh)
				serverTable.quickRefresh;
			else
				serverTable.updateStatusBar();
		}
	}


	/// Note: Doesn't synchronize.
	private bool addAll()
	{
		bool refresh = false;

		foreach (sh; list_) {
			if (addDg_(sh))
				refresh = true;
		}
		list_.length = 0;

		return refresh;
	}


	private {
		ServerHandle[] list_;
		bool delegate(ServerHandle) addDg_;
		bool stop_ = false;
	}
}
