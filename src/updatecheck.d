/**
 * Check for updates automatically, notify the user if there is a new version.
 */

module updatecheck;

import core.thread;
import std.net.curl;
import std.regex;

import java.lang.Runnable;
import org.eclipse.swt.SWT;
import org.eclipse.swt.program.Program;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.MessageBox;

import common;
import messageboxes;


///
void startUpdateChecker(bool quiet=true)
{
    auto t = new Thread({ checkForUpdate(quiet); });
    t.isDaemon(true);
    t.start();
}


private void checkForUpdate(bool quiet)
{
    char[] content;

    log("[Update check] Starting...");

    try {
        content = get("https://api.github.com/" ~
                               "repos/torhus/monster-browser/releases/latest");
    }
    catch (CurlException e)
    {
        logx(__FILE__, __LINE__, e);
    }

	if (auto m = content.matchFirst(`"tag_name": "v(\d+.\d+(\w|\.\d+|))"`)) {
        if (m[1] > FINAL_VERSION) {
            log("[Update check] Found version %s", m[1]);
            Display.getDefault().asyncExec(dgRunnable(
                                                { showNewVersionMessage(); }));
        }
        else {
            log("[Update check] No newer version found.");
            if (!quiet)
                info("There was no new version.");
        }
    }
    else {
            log("[Update check] There was an error.");
            if (!quiet)
                error("Update check failed!");
    }
}


private void showNewVersionMessage()
{
    auto mb = new MessageBox(mainShell, SWT.ICON_INFORMATION | SWT.OK |
                                        SWT.CANCEL);
    mb.setText("New Version");
    mb.setMessage ("A new version of " ~ APPNAME ~ " is available!" ~
                                " Press OK to go to the web site and get it.");

    if (mb.open() == SWT.OK)
        Program.launch("https://sites.google.com/site/monsterbrowser/");
}
