module threading;

import tango.core.Thread;
debug import tango.io.Console;

import runtools; // : abortParsing, killServerBrowser;


Thread serverThread;
ThreadDispatcher threadDispatcher;


/**
 * Stores a pointer to a function or delegate and calls it only when
 * serverThread has terminated.
 */
final class ThreadDispatcher
{
	void run(void function() fp) { dg_ = null; fp_ = fp; } ///
	void run(void delegate() function() dg) { fp_ = null; dg_ = dg; } ///

	void dispatch() ///
	{
		if (fp_ is null && dg_ is null)
			return;

		if (serverThread && serverThread.isRunning) {
			volatile abortParsing = true;
		}
		else {
			debug Cout("ThreadDispatcher.dispatch: Killing server browser...")
			                                                          .newline;
			killServerBrowser();

			if (fp_ !is null) {
				fp_();
				fp_ = null;
			}
			else {
				void delegate() startIt = dg_();
				if (startIt !is null) {
					serverThread = new Thread(startIt);
					serverThread.start();
				}
				dg_ = null;
			}
		}
	}

	private void function() fp_ = null;
	private void delegate() function() dg_ = null;
}
