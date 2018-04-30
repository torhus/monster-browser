Monster Browser Instructions
============================

Basic Usage
-----------
Select a game from the drop down box on the right, where it says "Smokin' Guns"
the first time you run the program. If the game or mod you want is not listed,
just type its gamename there and press <Enter>. If it doesn't use Id's Quake 3
master server, you need to create a custom config for it, see 'Customizing the
Game List' below.

To update the server list, press the 'Refresh all' button. This happens
automatically at startup, or the first time each session you switch to a game.
You can press 'Check for new' to synchronize the list of servers that Monster
Browser queries with the master server. It's probably a good idea to use 'Check
for new' once a day or so.

The filters and column sorting should be pretty straight forward to use. You
can leave the filters on while doing a refresh, all the servers will be queried
anyway.

To join a server, double click on it, or select it and press <Enter>. If the
server requires a password, a password dialog will pop up. To change the
password, or add an optional password for servers with private slots, select
'Set password...' in the right-click menu.


Customizing the Game List
-------------------------
By clicking on the 'Game configuration' button in the settings, you can edit
the list displayed in the combo box. The format of this file is explained in
the file itself. The first game listed will be used as the default. If you want
the program to always start with the topmost game, select 'Default game' in the
settings. Otherwise it will start with the last selected game.


Adding Extra Servers
--------------------
If you want to query a server that isn't registered with the master server, you
can click on 'Add...' to add it to the list. Normally, any servers not
registered on the master will be removed from Monster Browser's list the next
time you check for new servers. If you don't want this to happen, make sure
'Never remove this server automatically' is checked. The server will still be
removed automatically if it times out too many times.

If you have more than a couple of servers to add, it's easier to add them
directly to a file called '<gamename>.extra' in the Monster Browser directory.
The format is just one IP address per line, with or without a port number. For
instance, when refreshing a list or checking for new servers for the cpma mod,
Monster Browser checks for existence of a file called 'cpma.extra', and adds
any servers listed in it to the list of servers to query.


Remote Console
--------------
The remote console (rcon) lets you send commands to a game server. It's an
advanced feature primarily useful for server administrators. To open a remote
console window, select a server and press F9, or use the context menu. The up
and down arrow keys access the command history, while page up and page down
scroll the output window. Pressing Esc closes the window.


Portable Monster Browser
------------------------
If you create an (empty or not) file called 'portable.txt' in the directory
where Monster Browser is installed, Monster Browser will save all its files in
that directory. Useful for USB stick installs, or if you want multiple
independent installations. Versions prior to 0.7 worked this way by default.


Keyboard shortcuts
------------------
F4 - Check for new servers
F5 - Refresh list
F9 - Open remote console
Enter - Join server
Ctrl+R - Refresh selected server(s)
Ctrl+C - Copy the addresses of selected server(s) to the clipboard
Del - Remove selected server(s)
Esc - Abort action


Credits
-------
Qstat for querying servers - http://qstat.sourceforge.net

Thanks to Biondo for making the application icon that's used for Monster
Browser 0.9 and later.

GeoLite Country from maxmind.com.

Function Free Icon set by Function Design & Development Studio
http://www.wefunction.com


Info and contact
----------------
Web site: http://sites.google.com/site/monsterbrowser/
Source code, etc.: https://github.com/torhus/monster-browser

I'm open for requests to change the licence, I just haven't bothered deciding
which licence to use yet.

Check out smokin-guns.org, I'm registered as torhu. Send me a private message
through the forum there if I don't reply to your emails.

Email:
torhu at yahoo dot com.
