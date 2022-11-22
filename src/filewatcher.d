/**
* Automatically update the server list and GUI when the game configuration file
* is edited.
*/

module filewatcher;

import fswatch;
import java.lang.Runnable;
import org.eclipse.swt.widgets.Display;

import common;
import serveractions;
import servertable;
import settings;
import mainwindow;


void startFileWatching()
{
    shared static firstTime = true;
    assert(firstTime);

    FileWatch watcher = FileWatch(gamesFilePath);

    void reloadGameConfig()
    {
        log("Reloading game config...");
        string name = serverTable.serverList.gameName;
        settings.loadGamesFile();
        gameBar.setGames(settings.gameNames);
        switchToGame((findString(settings.gameNames, name)
                                  != -1) ? name : settings.gameNames[0], true);
        updateServerListCache(settings.gameNames);

    }

    void check()
    {
        Display.getDefault().timerExec(500, dgRunnable(&check));
        if (firstTime)
            return;

        foreach(event; watcher.getEvents()) {
            if (event.type == FileChangeEventType.modify)
                reloadGameConfig();
        }
    }

    check();
    firstTime = false;
}
