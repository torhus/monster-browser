module threadmanager;

import tango.core.Thread;
import tango.core.sync.Semaphore;

import java.lang.Runnable;
import org.eclipse.swt.widgets.Display;

import runtools : killServerBrowser;


/// Global instance.
ThreadManager threadManager;


/**
 * Stores a pointer to a function, and calls it only when the previous one has
 * terminated.
 */
class ThreadManager
{

	bool abort;  ///


	///
	this()
	{
		thread_ = new Thread(&dispatch);
		thread_.name = "secondary";
		semaphore_ = new Semaphore;
		thread_.start();
	}


	/**
	 * Store a function to be called after the current secondary thread has
	 * terminated.
	 *
	 * The return value of fp is a delegate that will be called in a new
	 * thread.  If fp returns null, no new thread is started.
	 *
	 * This method sets the abort property to true.
	 *
	 * Note: This will set the function pointer stored by runSecond to null.
	 */
	synchronized void run(void delegate() function() fp)
	{
		abort = true;
		fp_ = fp;
		fp2_ = null;
		semaphore_.notify();
	}


	/**
	 * Stores a function to be called after the one given to run() has ended.
	 *
	 * If the secondary thread is running, fp is not called until after it is
	 * finished.
	 *
	 * This method does not change the abort property.
	 */
	synchronized void runSecond(void delegate() function() fp)  ///
	{
		fp2_ = fp;
		semaphore_.notify();
	}


	/**
	 * Tell the secondary thread to stop what it's doing and exit.
	 */
	void shutdown()
	{
		abort = true;
		shutdown_ = true;
		semaphore_.notify();
	}


	/// Is the secondary thread sleeping or working?
	bool sleeping() { return sleeping_; }


	private void dispatch()
	{
		while (true) {
			void delegate() inSecondaryThread;

			sleeping_ = true;
			semaphore_.wait();
			sleeping_ = false;
			if (shutdown_)
				break;

			synchronized (this) assert(fp_ !is null || fp2_ !is null);

			killServerBrowser();

			Display.getDefault.syncExec(dgRunnable( (ThreadManager outer_) {
				void delegate() function() inGuiThread;
				synchronized (outer_) {
					if (fp_ !is null) {
						inGuiThread = fp_;
						fp_ = null;
					}
					else if (fp2_ !is null) {
						inGuiThread = fp2_;
						fp2_ = null;
					}
					abort = false;
				}
				inSecondaryThread = inGuiThread();
			}, this));

			if (!abort && inSecondaryThread !is null)
				inSecondaryThread();
		}
	}


	private {
		void delegate() function() fp_= null;
		void delegate() function() fp2_= null;
		Thread thread_;
		Semaphore semaphore_;
		bool shutdown_ = false;
		bool sleeping_ = true;
	}
}
