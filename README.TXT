Monster Browser Instructions
============================

Basic Usage
-----------
Select a game or mod from the drop-down list in the 'Game' section. To update
the server list, press the 'Refresh all' button.  This happens automatically
at startup, or the first time each session you switch to a game.  You can
press 'Check for new' to synchronize the list of servers that Monster Browser
queries with the master server.  It's probably a good idea to do this once a
day or so.

The filters and column sorting should be pretty straight forward to use.  You
can leave the filters on while doing a refresh, all the servers will be
queried anyway.

To join a server, double click on it, or select it and press <Enter>.  If the
server requires a password, a password dialog will pop up.  To change the
password, or add an optional password for servers with private slots, select
'Set password...' in the right-click menu.


Customizing the Game List
-------------------------
By clicking on the Edit button you can edit the list displayed in the drop-
down list.  The first game listed will be used as the default. If you remove
this file, or clear its contents, Monster Browser will create a new one
containing the default configuration.

Available Options:

* mod: This is matched against the game and gamename cvars, to allow for
  filtering on game or mod. Set to empty value (mod=) to disable filtering.
  Defaults to being the same as the section name.
* exePath: The full path to the game's executable. The default is the path set
  in Settings. This can be set a to shortcut (.lnk) or  file (.bat) to get more
  flexibility. In batch files you have to pass MB's arguments to the executable
  on explicitly, like this: C:\TheGame\game.exe %*
* regKey: A registry key containing the path to the game. Useful for the games
  that have installers that set this. This will be tried before exePath.
* exeName: Combined with the value found through regKey to form the full path.
* masterServer: Defaults to master.quake3arena.com:27950.
* protocolVersion: Defaults to 68.
* gameTypes: List of game type names, separated by spaces.
* etColors: Set to true to enable Enemy Territory-style extended color codes
  (31 colors). See http://wolfwiki.anime.net/index.php/Color_Codes for more
  information.
* qstatMasterServerType: Defaults to q3m.
* qstatConfigFile: For setting Qstat's -cfg parameter.


Adding Extra Servers
--------------------
If you want to query a server that isn't registered with the master server, 
you can click on 'Add...' to add it to the list. Normally, any servers not 
registered on the master will be removed from Monster Browser's list the next 
time you check for new servers. If you don't want this to happen, make sure
'Never remove this server automatically' is checked. The server will still be 
removed automatically if it times out too many times.

If you have more than a couple of servers to add, it's easier to add them 
directly to a file called '<mod>.extra' in the Monster Browser directory. If 
mod is set to nothing, use '<section name>.extra' instead. The format is just 
one IP address per line, with or without a port number. For instance, when 
refreshing a list or checking for new servers for the cpma mod, Monster 
Browser checks for existence of a file called 'cpma.extra', and adds any 
servers listed in it to the list of servers to query.


Remote Console
--------------
The remote console (rcon) lets you send commands to a game server. It's an
advanced feature primarily useful for server administrators. To open a remote
console window, select a server and press F9, or use the context menu. The up
and down arrow keys access the command history, while page up and page down
scroll the output window. Pressing Esc closes the window.


Portable Monster Browser
------------------------
If you create a file called 'portable.txt' in the directory where Monster 
Browser is installed, Monster Browser will save all its files in that 
directory.  Useful for USB stick installs, or if you want multiple independent 
installations.


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
Qstat for querying servers - https://github.com/Unity-Technologies/qstat

Thanks to Biondo for making the application icon that's used for Monster
Browser 0.9 and later.

This product includes GeoLite2 data created by MaxMind, available from
https://www.maxmind.com

Function Free Icon set by Function Design & Development Studio
http://www.wefunction.com


Info and contact
----------------
Web site: http://sites.google.com/site/monsterbrowser/
Source code, etc.: https://github.com/torhus/monster-browser

I'm open for requests to change the licence, I just haven't bothered deciding
which licence to use yet.

Email:
torhu at yahoo dot com.
