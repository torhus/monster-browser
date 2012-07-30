/**
 * Keeps track of user-initated actions, notifies parts of the system when an
 * action is started or stopped.
 */

module actions;

debug import tango.core.Array;
debug import tango.core.Thread;
debug import tango.io.Stdout;

import dwt.dwthelper.Runnable;
import dwt.widgets.Display;

debug import common;


enum Action { none=0, checkForNew, refreshAll, refreshSome, addServer }

private ActionHandler[] handlers;
private Action currentAction, nextAction;


static this()
{
	debug addActionHandler(new DebugActionHandler);
}


void startAction(Action action)
{
	Display.getDefault().syncExec(dgRunnable({
		assert(action != Action.none);
		assert(currentAction || !nextAction);

		if (currentAction == Action.none) {
			currentAction = action;
			foreach (handler; handlers)
				handler.actionStarting(currentAction);
		}
		else if (action != nextAction) {
			nextAction = action;
			foreach (handler; handlers)
				handler.actionQueued(nextAction);
		}
	}));
}


void stopAction()
{
	Display.getDefault().syncExec(dgRunnable({
		nextAction = Action.none;
		foreach (handler; handlers)
			handler.actionStopping(currentAction);
	}));
}


void doneAction()
{
	Display.getDefault().syncExec(dgRunnable({
		if (!currentAction)
			return;

		foreach (handler; handlers)
			handler.actionDone(currentAction);
		currentAction = Action.none;

		if (nextAction) {
			currentAction = nextAction;
			nextAction = Action.none;
			foreach (handler; handlers)
				handler.actionStarting(currentAction);
		}
	}));
}


void addActionHandler(ActionHandler handler)
{
	Display.getDefault().syncExec(dgRunnable({
		assert(handler !is null);
		assert(!handlers.contains(handler));

		handlers ~= handler;
	}));
}


abstract class ActionHandler
{
	void actionStarting(Action action) {}
	void actionQueued(Action action) {}
	void actionStopping(Action action) {}
	void actionDone(Action action) {}
}


private class DebugActionHandler : ActionHandler
{
	void actionStarting(Action action)
	{
		log("actionStarting(" ~ getActionName(action) ~ ")");
	}

	void actionQueued(Action action)
	{
		log("actionQueued(" ~ getActionName(action) ~ ")");
	}

	void actionStopping(Action action)
	{
		log("actionStopping(" ~ getActionName(action) ~ ")");
	}
	void actionDone(Action action)
	{
		log("actionDone(" ~ getActionName(action) ~ ")");
	}

	private char[] getActionName(Action action)
	{
		switch (action) {
			case Action.none:
				return "Action.none";
			case Action.checkForNew:
				return "Action.checkForNew";
			case Action.refreshAll:
				return "Action.refreshAll";
			case Action.refreshSome:
				return "Action.refreshSome";
			case Action.addServer:
				return "Action.addServer";
			default:
				assert(0);
		}
	}
}
