module serverqueue;

import tango.util.MinMax;

import dwt.dwthelper.Runnable;
import dwt.widgets.Display;

import common : arguments;
import masterlist;
import serverlist;
import servertable;


///
final class ServerQueue
{
	///
	this(Replacement delegate(ServerHandle sh) addDg)
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
			int topIndex = addAll();
			if (topIndex < int.max && !arguments.norefresh)
				serverTable.quickRefresh(topIndex);
			else
				serverTable.updateStatusBar();
		}
	}


	/// Note: Doesn't synchronize.
	private int addAll()
	{
		int topIndex = int.max;

		foreach (sh; list_) {
			Replacement repl = addDg_(sh);
			if (repl.oldIndex == -1 && repl.newIndex == -1)
				continue;
			topIndex = min(cast(uint)repl.oldIndex, cast(uint)repl.newIndex);
		}
		list_.length = 0;

		return topIndex;
	}

	private {
		ServerHandle[] list_;
		Replacement delegate(ServerHandle) addDg_;
		bool stop_ = false;
	}
}
