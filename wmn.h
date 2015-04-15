#ifndef TXREXTRACTOR_WMN_HEADER
#define TXREXTRACTOR_WMN_HEADER

#include "stdint.h"
#include "TXRExtractor.h"

#define WMN_FILENAME_MAX_SZ	128
#define WMN_INFLATE_CHUNK_MAX_SZ	0x40000 /* 256KB */


// first 48 bytes in table of content (.TOC file) of Wangan Midnight
struct WMN_TOC_HEADER {
	char fourcc[4]; // BLDh
	uint32_t vermagic; // 0
	char def_section[4]; // "def "
	uint32_t def_section_sz; // size of def chunk, 24 bytes for WMN

	uint32_t unknown1; // 65536
	uint32_t number_of_files; // number of files in WMN.DAT, it is 3174
	uint32_t unknown2; // 22771984
	uint32_t unknown3; // 6620888, AUDIO_PS3.TOC has 0x0 here anyway?

	uint32_t alignment; // 2048 byte aligned
	uint32_t unknown4; // 0x0
	char inf_section[4]; // "inf "
	uint32_t inf_section_sz; // size of inf chunk
};

// starts at 0x1F020h
struct WMN_TOC_TBL_SECTION {
	char tbl_section[4]; // "tbl "
	uint32_t tbl_section_sz; // 101656 bytes for WMN
	// after 8 of above bytes, fname null terminated strings can be read
};

// starts at 0x37D40h
struct WMN_TOC_ROF_SECTION {
	char rof_section[4]; // "rof "
	uint32_t rof_section_sz; // 512 bytes for WMN
	// at this it is unknown what rof section is for
	// after this it is end of TOC file
};

// 40 bytes per entry, 3174 of them starting at 0x30h
struct WMN_TOC_DIR_ENTRY {
	uint32_t file_offset; // offset * alignment = starting position of a file
	uint32_t file_zsz; // seems to be 8 more than 'file_deflate_parts_sz' member from 'WMN_DAT_CHUNK'
	uint32_t file_sz; // final file size, non-deflate files report this as 0, e.g. FONT/MDK32_ROW.DAT at 0xAF800h in WMN.DAT
	uint32_t unknown1; // 
	uint32_t unknown_zero1;
	uint32_t unknown_zero2;
	char unknown_string[12];
	uint32_t unknown_zero3;
};

// deflated chunk spec, weights in at 60 bytes
struct WMN_DAT_CHUNK {
	char fourcc[4]; // GARC
	uint32_t file_deflate_parts_sz; // size of all chunks combined starting with "GARC" to last bytes before zeros padding begin
	char file_zlib_magic[4]; // zlib
	uint32_t file_inflate_sz; // final file size after inflation of all chunks

	// below part is 28 bytes
	char inf_section[4]; // "inf "
	uint32_t inf_section_sz; // 20 bytes for Wangan Midnight
	uint32_t inf_section_unknown1; // 4656
	uint32_t inf_section_max_chunk_size; // 256KB aka 262144
	uint32_t inf_section_unknown2; // 1536
	char inf_section_padding[8]; // 0x0h 0x0h

	char dat_section[4]; // "dat "
	uint32_t dat_section_size; // size of all chunks combined starting with "dat " and ending just before zeros padding begin
	uint32_t sz_of_curr_deflated_chunk; // size of raw chunk deflate data including the 6 byte zlib header and ending somewhere before padded 0x0h
										// every nth chunks starts with this followed by 0x0h, 6 byte zlib header, and raw data...
	char padding[4]; // 0x0
	/* char zlibheader[6];  e.g. 78 9C BD 5A 79 78 */
	// rest is raw zlib deflate data...
	// followed by ADLER32 hash?
};


// function prototypes
int mkdirr(const char *);
int wmn_dat_inflate_file(FILE *, struct WMN_DAT_CHUNK, struct WMN_TOC_DIR_ENTRY, void **, size_t *, const char *);
int wmn_toc_parse_filenames(FILE *, struct WMN_TOC_HEADER, char **);
int wmn_toc_parse_dir_entries(FILE *, FILE *, struct WMN_TOC_HEADER, char **);
int wmn_extract(FILE *, FILE *);

#endif
