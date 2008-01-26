Monster Browser
---------------
This program is copyright (c) 2007 Tor Husabø.


Installation
------------
Just unzip in your "C:\Program Files" directory, and make a desktop shortcut to MonsterBrowser.exe.  If you have problems, send me an email and I'll try to help.


Basic Usage
-----------
Select the mod name from the drop down box on the right, where it says 'westernq3' the first time you run the program.  If the mod you want is not listed, just type its gamename there and press <enter>.  The gamename is the same as the name of the directory the mod is installed in.

Then click on 'Get new list'.  That might take a while, but you can use 'Refresh'  instead most of the time.  The next time you start the program, it will load the server list from disk, and do an automatic refresh.  It's probably a good idea to use 'Get new list' once a day or so.

The filters and column sorting should be pretty straight forward to use.  You can leave the filters on while doing a refresh or getting a new list, all the servers will be queried anyway.

On first use, go into the settings and check that the path to your Quake 3 exe is set correctly.  The program will not find Quake 3 by itself.

To join a server, just select it and double click or press <enter>.  If the server requires a password, or has an optional password for reserved slots, a password dialog will pop up.  The password will be stored.


Customizing the Mod List
------------------------
By clicking on the 'Mods...' button in the settings, you can edit the list displayed in the combo box.  The format of this file is explained in the file itself.  The first mod listed will be used as the default.  If you want the program to always start with the top mod, select 'Default mod' in the settings.  Otherwise it will start with the last selected mod.


Adding Extra Servers
--------------------
If you want to check a server that isn't registered with the master server, you can click on 	'Specify...' to add it to the list.  There's an option to save it to disk, so that it won't be lost when you restart Monster Browser.

If you have more than a couple of servers to add, it's easier to add them directly to a file called '<modname>.extra' in the Monster Browser directory.  The format is just one IP address per line, with or without a port number.  For instance, when refreshing a list or getting a new list for the cpma mod, Monster Browser checks for existance of a file called 'cpma.extra', and adds any servers listed in it to the list of servers to query.  These files are also where the 'Specify...' feature saves the added servers to.


Info and contact
----------------
I'm open for requests to change the licence, I just haven't bothered deciding which licence to use yet.

Check out westernquake3.net, I'm registered as torhu.  Send me a PM there if I don't reply to your emails.

Send comments, patches etc. to:
torhu at yahoo dot com.
