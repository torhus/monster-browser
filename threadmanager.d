module threadmanager;

import core.thread;
import core.sync.semaphore;

import java.lang.Runnable;
import org.eclipse.swt.widgets.Display;

import runtools;// : killServerBrowser;


/// Global instance.
__gshared ThreadManager threadManager;


/**
 * Utility class for serialized execution of code in a secondary thread.
 *
 * The stored function or delegate will only be executed after the previously
 * started one has finished.  It will be executed in a thread controlled by
 * this class.
 *
 * FIXME: this class should probably be declared as synchronized.
 */
class ThreadManager
{
	/**
	 * This can be checked by the function or delegate given to run to see if
	 * it should exit prematurely, to give the next function or delegate a
	 * chance to start sooner.
	 *
	 * The ThreadManager class does not read the value of this property, it
	 * only sets it.  Using this property is purely optional.
	 */
	bool abort;


	///
	this()
	{
		thread_ = new Thread(&dispatch);
		thread_.name = "secondary";
		semaphore_ = new Semaphore;
		thread_.start();
	}


	/**
	 * Store a function or delegate to be called after the previous one has
	 * terminated.
	 *
	 * Only one function or delegate at a time can be stored, calling run again
	 * before the previous one has been started will replace it.
	 *
	 * These methods sets the abort property to true.  Just before the stored
	 * function or delegate is called, and unless shutDown has been called,
	 * abort is set to false again.
	 */
	void run(void function() fp)
	{
		synchronized (this) {
			abort = true;
			fp_ = fp;
			dg_ = null;
			semaphore_.notify();
		}
	}


	/// Ditto
	void run(void delegate() dg)
	{
		synchronized (this) {
			abort = true;
			dg_ = dg;
			fp_ = null;
			semaphore_.notify();
		}
	}


	/**
	 * Tell the secondary thread to exit.
	 *
	 * The currently running stored function or delegate will be allowed to run
	 * to completion first.
	 *
	 * Sets the abort property to true.
	 */
	void shutDown()
	{
		synchronized (this) {
			abort = true;
			shutdown_ = true;
			semaphore_.notify();
		}
	}


	/// Is the secondary thread sleeping or working?
	bool sleeping() { return sleeping_; }


	private void dispatch()
	{
		void function() fpCopy;
		void delegate() dgCopy;

		while (true) {
			sleeping_ = true;
			semaphore_.wait();
			sleeping_ = false;
			if (shutdown_)
				break;

			killServerBrowser();

			synchronized (this) {
				fpCopy = fp_;
				fp_ = null;
				dgCopy = dg_;
				dg_ = null;

				if (!shutdown_)
					abort = false;
			}

			assert ((dgCopy is null) != (fpCopy is null));

			if (fpCopy !is null)
				fpCopy();
			if (dgCopy !is null)
				dgCopy();
		}
	}


	private {
		void function() fp_= null;
		void delegate() dg_= null;
		Thread thread_;
		Semaphore semaphore_;
		bool shutdown_ = false;
		bool sleeping_ = true;
	}
}
