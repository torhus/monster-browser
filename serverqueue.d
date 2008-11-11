module serverqueue;

import dwt.dwthelper.Runnable;
import dwt.widgets.Display;

import common : arguments;
import serverlist;
import servertable;


///
class ServerQueue
{
	///
	this(bool delegate(ServerData*) addDg)
	{
		addDg_ = addDg;
		Display.getDefault.syncExec(new TimerTask);
	}


	~this()
	{
		if (list_ !is null)
			delete list_;
	}


	///
	void add(ServerData* sd)
	{
		synchronized (this) list_ ~= *sd;
	}


	///
	void addRemainingAndStop()
	{
		Display.getDefault.syncExec(new class Runnable {
			void run() { synchronizedAdd(); }
		});
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
		}
	}


	/// Note: Doesn't synchronize.
	private bool addAll()
	{
		bool refresh = false;

		foreach (ref sd; list_) {
			if (addDg_(&sd))
				refresh = true;
		}
		list_.length = 0;

		return refresh;
	}


	private {
		ServerData[] list_;
		bool delegate(ServerData*) addDg_;
		bool stop_ = false;
	}
}
