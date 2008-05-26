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
		bindFunc!(GeoIP_open)(geoIpLib);
		bindFunc!(GeoIP_delete)(geoIpLib);
		bindFunc!(GeoIP_country_code_by_addr)(geoIpLib);
	}
	catch (SharedLibException e) {
		log("Unable to load GeoIP.dll, flags will not be shown.");
		return false;
	}

	gi = GeoIP_open("GeoIP.dat", GEOIP_MEMORY_CACHE);
	if (gi is null) {
		warning("GeoIP.dat was not found, flags will not be shown.");
		geoIpLib.unload;
	}
	else {
		initFlagFiles;
		if (flagFiles is null || flagFiles.length == 0) {
			log("No flag data was found.");
			geoIpLib.unload;
			//GeoIP_delete(gi);  // For some reason, this crashes.
			gi = null;
		}
	}

	return gi && flagFiles;
}


///
char[] countryCodeByAddr(in char[] addr)
{
	assert(gi);

	char* code = GeoIP_country_code_by_addr(gi, toStringz(addr));
	if (code is null) {
		log("GeoIP: no country found for " ~ addr ~ ".");
		return null;
	}
	else {
		return toLower(fromStringz(code).dup);
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
	if (image is null) {
		Image tmp = null;
		ubyte data[] = flagFiles[countryCode];

		if (data !is null) {
			try {
				auto stream  = new ByteArrayInputStream(cast(byte[])data);
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


static ~this()
{
	foreach (key, val; flagCache)
		val.dispose;

	if (gi)
		GeoIP_delete(gi);
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
	GeoIP* function(in char *filename, int flags) GeoIP_open;
	void function(GeoIP* gi) GeoIP_delete;
	char* function(GeoIP* gi, in char *addr) GeoIP_country_code_by_addr;
}
