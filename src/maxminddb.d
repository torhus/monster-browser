/**
 * For accessing MaxMind's GeoIP2 databases.
 */

module maxminddb;

import core.stdc.stdint;
import std.format;
import std.string;


alias ptrdiff_t ssize_t;
alias int c_int;

/* Error codes */
enum {
	MMDB_SUCCESS = 0,
	MMDB_FILE_OPEN_ERROR = 1,
	MMDB_CORRUPT_SEARCH_TREE_ERROR = 2,
	MMDB_INVALID_METADATA_ERROR = 3,
	MMDB_IO_ERROR = 4,
	MMDB_OUT_OF_MEMORY_ERROR = 5,
	MMDB_UNKNOWN_DATABASE_FORMAT_ERROR = 6,
	MMDB_INVALID_DATA_ERROR = 7,
	MMDB_INVALID_LOOKUP_PATH_ERROR = 8,
	MMDB_LOOKUP_PATH_DOES_NOT_MATCH_DATA_ERROR = 9,
	MMDB_INVALID_NODE_NUMBER_ERROR = 10,
	MMDB_IPV6_LOOKUP_IN_IPV4_DATABASE_ERROR = 11,
}

struct MMDB_entry_s {
	MMDB_s *mmdb;
	uint32_t offset;
}

struct MMDB_lookup_result_s {
	bool found_entry;
	MMDB_entry_s entry;
	uint16_t netmask;
}

struct MMDB_entry_data_s {
	bool has_data;
	union {
		uint32_t pointer;
		const char *utf8_string;
		double double_value;
		const uint8_t *bytes;
		uint16_t uint16;
		uint32_t uint32;
		int32_t int32;
		uint64_t uint64;
		version (all) {
			uint8_t[16] uint128;
		}
		else {
			mmdb_uint128_t uint128;
		}
		bool boolean;
		float float_value;
	}
	/* This is a 0 if a given entry cannot be found. This can only happen
	 * when a call to MMDB_(v)get_value() asks for hash keys or array
	 * indices that don't exist. */
	uint32_t offset;
	/* This is the next entry in the data section, but it's really only
	 * relevant for entries that part of a larger map or array
	 * struct. There's no good reason for an end user to look at this
	 * directly. */
	uint32_t offset_to_next;
	/* This is only valid for strings, utf8_strings or binary data */
	uint32_t data_size;
	/* This is an MMDB_DATA_TYPE_* constant */
	uint32_t type;
}

struct MMDB_entry_data_list_s {
	MMDB_entry_data_s entry_data;
	MMDB_entry_data_list_s *next;
	void *pool;
}

struct MMDB_description_s {
	/*const*/ char *language;
	/*const*/ char *description;
}

struct MMDB_metadata_s {
	uint32_t node_count;
	uint16_t record_size;
	uint16_t ip_version;
	/*const*/ char *database_type;
	struct Languages {
		size_t count;
		/*const*/ char **names;
	}
	Languages languages;
	uint16_t binary_format_major_version;
	uint16_t binary_format_minor_version;
	uint64_t build_epoch;
	struct Description {
		size_t count;
		MMDB_description_s **descriptions;
	}
	Description description;
}

struct MMDB_ipv4_start_node_s {
	uint16_t netmask;
	uint32_t node_value;
}

struct MMDB_s {
	uint32_t flags;
	/*const*/ char *filename;
	ssize_t file_size;
	/*const*/ uint8_t *file_content;
	/*const*/ uint8_t *data_section;
	uint32_t data_section_size;
	/*const*/ uint8_t *metadata_section;
	uint32_t metadata_section_size;
	uint16_t full_record_byte_size;
	uint16_t depth;
	MMDB_ipv4_start_node_s ipv4_start_node;
	MMDB_metadata_s metadata;
}

/* For interpreting the gai_error argument of MMDB lookup functions */
version (Windows) {
	// It's an inline function on Windows, defined in WS2tcpip.h
	const(char) * gai_strerror(c_int ecode)
	{
		return toStringz(format("gai_strerror(%s)", ecode));
	}
}
else {
	extern (C) char * gai_strerror(c_int ecode);
}

