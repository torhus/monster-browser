Monster Browser Instructions
============================

Basic Usage
-----------
Select a game from the drop down box on the right, where it says "Smokin' Guns" the first time you run the program.  If the game or mod you want is not listed, just type its gamename there and press <enter>.  If it doesn't use Id's Quake 3 master server, you need to create a custom config for it, see 'Customizing the Game List' below.

To update the server list, press the 'Refresh all' button.  This happens automatically at startup, or the first time each session you switch to a game.  You can press 'Check for new' to synchronize the list of servers that Monster Browser queries with the master server.  It's probably a good idea to use 'Check for new' once a day or so, and just use 'Refresh all' most of the time.

The filters and column sorting should be pretty straight forward to use.  You can leave the filters on while doing a refresh, all the servers will be queried anyway.

To join a server, just select it and double click or press <enter>.  If the server requires a password, or has an optional password for reserved slots, a password dialog will pop up.  The password will be stored on disk.


Customizing the Game List
-------------------------
By clicking on the 'Games...' button in the settings, you can edit the list displayed in the combo box.  The format of this file is explained in the file itself.  The first game listed will be used as the default.  If you want the program to always start with the topmost game, select 'Default game' in the settings.  Otherwise it will start with the last selected game.


Adding Extra Servers
--------------------
If you want to check a server that isn't registered with the master server, you can click on 	'Add...' to add it to the list.  There's an option to save it to disk, so that it won't be lost when you restart Monster Browser.

If you have more than a couple of servers to add, it's easier to add them directly to a file called '<gamename>.extra' in the Monster Browser directory.  The format is just one IP address per line, with or without a port number.  For instance, when refreshing a list or checking for new servers for the cpma mod, Monster Browser checks for existance of a file called 'cpma.extra', and adds any servers listed in it to the list of servers to query.  These files are also where the 'Add...' feature saves the added servers to.


Keyboard shortcuts
------------------
F4     - Check for new servers
F5     - Refresh list
Enter  - Join server
Ctrl+R - Refresh selected server(s)
Ctrl+C - Copy the addresses of selected server(s) to the clipboard
Esc    - Abort action


Credits
-------
Monster Browser uses:

Function Free Icon set by Function Design & Development Studio
http://www.wefunction.com


Info and contact
----------------
Web site: http://monsterbrowser.googlepages.com/
Source code, etc.: http://monsterbrowser.googlecode.com/

I'm open for requests to change the licence, I just haven't bothered deciding which licence to use yet.

Check out smokin-guns.net, I'm registered as torhu.  Send me a PM there if I don't reply to your emails.

Email:
torhu at yahoo dot com.
