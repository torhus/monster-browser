/**
 * GeoIP stuff.
 */

module geoip;

import tango.stdc.stdarg;
import tango.stdc.stdint;
import tango.stdc.stringz;
import tango.stdc.time;
import tango.sys.SharedLib;
import tango.text.Ascii;
import Util = tango.text.Util;

import dwt.DWTException;
import dwt.dwthelper.ByteArrayInputStream;
import dwt.graphics.Image;
import dwt.widgets.Display;

import common;
import flagdata;
import maxminddb;

/** The result of a GeoIp lookup */
struct GeoInfo {
	char[] countryCode;
	char[] countryName;
}

private {
	MMDB_s mmdb;
	bool geoIpReady = false;
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


private char[] getString(MMDB_entry_s* start, ...)
{
	MMDB_entry_data_s entry_data;
	va_list args;

version (X86) {
	va_start(args, start);
}
else {
	assert(0);
}
	scope (exit) va_end(args);

	c_int result = MMDB_vget_value(start, &entry_data, args);

	if (result == MMDB_SUCCESS && entry_data.has_data) {
		return entry_data.utf8_string[0..entry_data.data_size];
	}
	else {
		log("MMDB_get_value failed.");
		log("GeoIP: " ~ fromStringz(MMDB_strerror(result)));
		return null;
	}
}


///
bool initGeoIp()
{
	static bool firstTime = true;
	const libName = "libmaxminddb.dll";
	const dbName = "GeoLite2-Country.mmdb";
	SharedLib geoIpLib;
	c_int result;

	assert(firstTime, "Can't call initGeoIp() more than once.");
	if (!firstTime)
		return false;
	firstTime = false;

	display = Display.getDefault;

	try {
		geoIpLib = SharedLib.load(libName);
		bindFuncOrThrow!(MMDB_lib_version)(geoIpLib);
		bindFuncOrThrow!(MMDB_open)(geoIpLib);
		bindFuncOrThrow!(MMDB_close)(geoIpLib);
		bindFuncOrThrow!(MMDB_lookup_string)(geoIpLib);
		bindFuncOrThrow!(MMDB_get_value)(geoIpLib);
		bindFuncOrThrow!(MMDB_vget_value)(geoIpLib);
		bindFuncOrThrow!(MMDB_get_metadata_as_entry_data_list)(geoIpLib);
		bindFuncOrThrow!(MMDB_get_entry_data_list)(geoIpLib);
		bindFuncOrThrow!(MMDB_free_entry_data_list)(geoIpLib);
		bindFuncOrThrow!(MMDB_strerror)(geoIpLib);
	}
	catch (SharedLibException e) {
		log("Unable to load the GeoIP library (" ~ libName ~ "), server " ~
			"locations will not be shown.");
		return false;
	}
	log("Loaded GeoIP2 library (" ~ libName ~ ") version " ~
	    fromStringz(MMDB_lib_version()) ~ ".");

	result = MMDB_open(toStringz(appDir ~ dbName), 0, &mmdb);
	if (result != MMDB_SUCCESS) {
		log("GeoIP: " ~ fromStringz(MMDB_strerror(result)));
		geoIpLib.unload;
	}
	else {
		time_t build_epoch = cast(time_t)mmdb.metadata.build_epoch;

		log("Loaded GeoIP2 database: " ~
		    fromStringz(mmdb.metadata.database_type) ~ ", " ~
		    Util.trim(fromStringz(asctime(gmtime(&build_epoch)))) ~ ".");

		initFlagFiles;
		geoIpReady = true;
	}

	return geoIpReady;
}


///
GeoInfo getGeoInfo(in char[] addr)
{
	if (!geoIpReady)
		return GeoInfo(null, null);

	c_int gai_error = 0, mmdb_error;
	bool error = false;

	MMDB_lookup_result_s result = MMDB_lookup_string(&mmdb,
	                                                 toStringz(addr),
	                                                 &gai_error,
	                                                 &mmdb_error);

	if (gai_error != 0) {
		log("GeoIP: " ~ fromStringz(gai_strerror(gai_error)));
		error = true;
	}
	if (mmdb_error != MMDB_SUCCESS) {
		log("GeoIP: " ~ fromStringz(MMDB_strerror(mmdb_error)));
		error = true;
	}
	if (!result.found_entry) {
		error = true;
	}
	if (error) {
		log("GeoIp: No info for address " ~ addr ~ ".");
		return GeoInfo(null, null);
	}
	else {
		char[] code = getString(&result.entry, "country".ptr, "iso_code".ptr, null);
		assert(code.length == 2);
		char[] name = getString(&result.entry, "country".ptr, "names".ptr, "en".ptr, null);
		return GeoInfo(toLower(code, new char[2]), name);
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

	if (geoIpReady) {
		MMDB_close(&mmdb);;
	}
}


extern (C) {
	c_int function(/*const*/ char */*const*/ filename, uint32_t flags,
	               MMDB_s */*const*/ mmdb)
	    MMDB_open;
	void function(MMDB_s */*const*/ mmdb) MMDB_close;
	MMDB_lookup_result_s function(MMDB_s */*const*/ mmdb,
	                              /*const*/ char */*const*/ ipstr,
	                              c_int */*const*/ gai_error,
	                              c_int */*const*/ mmdb_error)
	    MMDB_lookup_string;
	c_int function(MMDB_entry_s */*const*/ start,
	                     MMDB_entry_data_s */*const*/ entry_data, ...)
	    MMDB_get_value;
	c_int function(MMDB_entry_s */*const*/ start,
	                     MMDB_entry_data_s */*const*/ entry_data,
	                     va_list va_path)
	    MMDB_vget_value;
	c_int function(MMDB_s */*const*/ mmdb,
	               MMDB_entry_data_list_s **/*const*/ entry_data_list)
	    MMDB_get_metadata_as_entry_data_list;
	c_int function(MMDB_entry_s *start, MMDB_entry_data_list_s
	                               **/*const*/ entry_data_list)
	    MMDB_get_entry_data_list;
	void function(MMDB_entry_data_list_s */*const*/ entry_data_list)
	    MMDB_free_entry_data_list;
	/*const*/ char *function() MMDB_lib_version;
	/*const*/ char *function(c_int error_code) MMDB_strerror;
}
