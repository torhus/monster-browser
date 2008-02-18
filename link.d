module link;

// used by the Build tool
version(build) {
	/*debug {
		pragma(link, "dwtd.lib");
	}
	else {
		pragma(link, "dwt.lib");
	}*/

	pragma(link, "advapi32.lib");
	pragma(link, "comctl32.lib");
	pragma(link, "comdlg32.lib");
	pragma(link, "gdi32.lib");
	pragma(link, "shell32.lib");
	pragma(link, "ole32.lib");
	pragma(link, "oleaut32.lib");
	pragma(link, "oleacc.lib");
	pragma(link, "msimg32.lib");
	pragma(link, "usp10.lib");
}
