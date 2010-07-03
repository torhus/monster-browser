module link;

version(Windows) {
	pragma(lib, "advapi32.lib");
	pragma(lib, "comctl32.lib");
	pragma(lib, "comdlg32.lib");
	pragma(lib, "gdi32.lib");
	// Only needed for win 95/98 compatibility for SHGetSpecialFolderPath()
	pragma(lib, "shfolder.lib");
	pragma(lib, "shell32.lib");
	pragma(lib, "shlwapi.lib");
	pragma(lib, "ole32.lib");
	pragma(lib, "oleaut32.lib");
	pragma(lib, "olepro32.lib");
	pragma(lib, "oleacc.lib");
	pragma(lib, "msimg32.lib");
	pragma(lib, "usp10.lib");
	pragma(lib, "uuid.lib");
	pragma(lib, "zlib.lib");
}

version (linux) {
	pragma(lib, "gtk-x11-2.0");
	pragma(lib, "gdk-x11-2.0");
	pragma(lib, "atk-1.0");
	pragma(lib, "gdk_pixbuf-2.0");
	pragma(lib, "gthread-2.0");
	//pragma(lib, "gnomeui-2");  // doesn't seem to work
	pragma(lib, "pangocairo-1.0");
	pragma(lib, "fontconfig");
	pragma(lib, "Xtst");
	pragma(lib, "Xext");
	pragma(lib, "Xrender");
	pragma(lib, "Xinerama");
	pragma(lib, "Xi");
	pragma(lib, "Xrandr");
	pragma(lib, "Xcursor");
	pragma(lib, "Xcomposite");
	pragma(lib, "Xdamage");
	pragma(lib, "X11");
	pragma(lib, "Xfixes");
	//pragma(lib, "Xtst");  // doesn't seem to work
	pragma(lib, "pango-1.0");
	pragma(lib, "gobject-2.0");
	pragma(lib, "gmodule-2.0");
	pragma(lib, "dl");
	pragma(lib, "glib-2.0");
	pragma(lib, "cairo");
	//pragma(lib, "z" );  // doesn't seem to work
}

