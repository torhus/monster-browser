/**
 * Keeps track of user-initated actions, notifies parts of the system when an
 * action is started or stopped.
 */

module actions;

import std.algorithm.searching;
import std.conv;

import java.lang.Runnable;
import org.eclipse.swt.widgets.Display;

debug import common;


enum Action { none=0, checkForNew, refreshAll, refreshSome, addServer }

__gshared private ActionHandler[] handlers;
shared private Action currentAction, nextAction;


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
		assert(!handlers.canFind(handler));

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


debug private class DebugActionHandler : ActionHandler
{
	override void actionStarting(Action action)
	{
		log("actionStarting(" ~ getActionName(action) ~ ")");
	}

	override void actionQueued(Action action)
	{
		log("actionQueued(" ~ getActionName(action) ~ ")");
	}

	override void actionStopping(Action action)
	{
		log("actionStopping(" ~ getActionName(action) ~ ")");
	}
	override void actionDone(Action action)
	{
		log("actionDone(" ~ getActionName(action) ~ ")");
	}

	private string getActionName(Action action)
	{
		return text("Action.", action);
	}
}
