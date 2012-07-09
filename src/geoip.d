/**
 * GeoIP stuff.
 */

module geoip;

import tango.stdc.stringz;
import tango.sys.SharedLib;
import tango.text.Ascii;

import dwt.DWTException;
import dwt.dwthelper.ByteArrayInputStream;
import dwt.graphics.Image;
import dwt.widgets.Display;

import common;
import flagdata;


private {
	GeoIP* gi;
	Display display;
	Image[char[]] flagCache;
}


private void bindFunc(alias funcPtr)(SharedLib lib)
{
	funcPtr = cast(typeof(funcPtr))lib.getSymbolNoThrow(funcPtr.stringof.ptr);
}


private void bindFuncOrThrow(alias funcPtr)(SharedLib lib)
{
	funcPtr = cast(typeof(funcPtr))lib.getSymbol(funcPtr.stringof.ptr);
}


///
bool initGeoIp()
{
	SharedLib geoIpLib;

	assert(gi is null, "Can't call initGeoIp() more than once.");

	display = Display.getDefault;

	try {
		geoIpLib = SharedLib.load("GeoIP.dll");
		bindFunc!(GeoIP_lib_version)(geoIpLib);
		bindFuncOrThrow!(GeoIP_open)(geoIpLib);
		bindFuncOrThrow!(GeoIP_delete)(geoIpLib);
		bindFuncOrThrow!(GeoIP_database_info)(geoIpLib);
		bindFuncOrThrow!(GeoIP_country_code_by_addr)(geoIpLib);
		bindFuncOrThrow!(GeoIP_country_name_by_addr)(geoIpLib);
	}
	catch (SharedLibException e) {
		log("Error when loading the GeoIP DLL, flags will not be shown.");
		return false;
	}
	if (GeoIP_lib_version !is null)
		log("Loaded GeoIP DLL version " ~ fromStringz(GeoIP_lib_version()));

	gi = GeoIP_open(toStringz(appDir ~ "GeoIP.dat"), GEOIP_MEMORY_CACHE);
	if (gi is null) {
		log("Unable to load the GeoIP database, flags will not be shown.");
		geoIpLib.unload;
	}
	else {
		char[] info = fromStringz(GeoIP_database_info(gi));

		log("Loaded GeoIP database: " ~ info);
		initFlagFiles;
		if (flagFiles is null || flagFiles.length == 0) {
			log("No flag data was found.");
			GeoIP_delete(gi);
			gi = null;
			geoIpLib.unload;
		}
		// This probably isn't needed just for country names.
		//GeoIP_set_charset(gi, GEOIP_CHARSET_UTF8);
	}

	return gi && flagFiles;
}


///
char[] countryCodeByAddr(in char[] addr)
{
	if (gi is null)
		return null;

	char* code = GeoIP_country_code_by_addr(gi, toStringz(addr));
	if (code is null) {
		log("GeoIP: no country found for " ~ addr ~ ".");
		return null;
	}
	else {
		char[] s = fromStringz(code);
		assert(s.length == 2);
		return toLower(s.dup);
	}
}


///
char[] countryNameByAddr(in char[] addr)
{
	if (gi is null)
		return null;

	char* name = GeoIP_country_name_by_addr(gi, toStringz(addr));
	if (name is null) {
		log("GeoIP: no country name for " ~ addr ~ ".");
		return null;
	}
	else {
		return fromStringz(name);
	}
}


/**
 * Get a flag image for the given two-letter lower case country code.
 *
 * Returns null when no flag was found for the given country code, or if there
 * was a problem reading the image file, etc.  Only one attempt will be made at
 * loading each flag, calling this function again will not cause more attempts
 * to be made.
 */
Image getFlagImage(in char[] countryCode)
{
	Image* image;

	image = countryCode in flagCache;
	if (!image) {
		Image tmp = null;
		ubyte[]* data = countryCode in flagFiles;

		if (data) {
			try {
				auto stream  = new ByteArrayInputStream(cast(byte[])*data);
				tmp = new Image(display, stream);
			}
			catch (DWTException e) {
				log("Error when decoding flag for '" ~ countryCode ~ "', "
				                                     "possibly corrupt file.");
			}
		}
		else {
			log("No flag found for country code '" ~ countryCode ~ "'.");
		}

		flagCache[countryCode] = tmp;
		image = &tmp;
	}

	return image ? *image : null;
}


/// To be called before program exit.
void disposeFlagImages()
{
	foreach (key, val; flagCache)
		if (val)
			val.dispose;

	if (gi) {
		GeoIP_delete(gi);
		gi = null;
	}
}


struct GeoIP { }

enum /*GeoIPOptions*/ {
	GEOIP_STANDARD = 0,
	GEOIP_MEMORY_CACHE = 1,
	GEOIP_CHECK_CACHE = 2,
	GEOIP_INDEX_CACHE = 4,
	GEOIP_MMAP_CACHE = 8,
}

extern (C) {
	GeoIP* function(in char* filename, int flags) GeoIP_open;
	void function(GeoIP* gi) GeoIP_delete;
	char* function(GeoIP* gi) GeoIP_database_info;
	char* function(GeoIP* gi, in char* addr) GeoIP_country_code_by_addr;
	char* function(GeoIP* gi, in char* addr) GeoIP_country_name_by_addr;
	char* function() GeoIP_lib_version;
}
