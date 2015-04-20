/*
 * Tokyo Xtreme Racer Extractor
 *
 * currently supported archives:
 *   - Wangan Midnight 2007 PS3..............: WMN.DAT (done), AUDIO_PS3.DAT (DONE)
 *   - Import Tuner Challenge 2006 XBOX360...: work in progress...
 *
 *
 * author: fatalhalt https://github.com/fatalhalt
 *
 */

#include "stdafx.h"
#include "TXRExtractor.h"
#include "wmn.h"
#include <io.h>
#include <fcntl.h>

// detects supported Tokyo Xtreme Racer archive
int txre_detect_archive(archive_unpack_f *f, FILE *fd_archive, FILE *fd_toc) {
	int ret1, ret2;
	char toc_heading[48] = { 0 };
	char dat_heading[60] = { 0 };

	// read first 60 bytes of archive and 48 bytes of table of content
	ret1 = fread(toc_heading, 48, 1, fd_toc);
	ret2 = fread(dat_heading, 60, 1, fd_archive);

	if (ret1 & ret2) {
		struct WMN_TOC_HEADER *toc_header = (struct WMN_TOC_HEADER *) toc_heading;
		struct WMN_DAT_CHUNK *dat_header = (struct WMN_DAT_CHUNK *) dat_heading;

		// detect Wangan Midnight
		if ((strncmp(toc_header->fourcc, "BLDh", 4) == 0) && (strncmp(toc_header->def_section, "def ", 4) == 0)) {
			if ((strncmp(dat_header->fourcc, "GARC", 4) == 0) && (strncmp(dat_header->file_zlib_magic, "zlib", 4) == 0)) {
				*f = wmn_extract;
				return 0;
			} else {
				*f = wmn_extract_audio;
				return 0;
			}
		}
	} else {
		fprintf(stderr, "failed to prefetch first 60 bytes of archive and first 48 bytes of toc: %s\n", strerror(errno));
	}

	return 1;
}

int main(int argc, char* argv[])
{
	archive_unpack_f archive_unpack = NULL;
	int ret;

	/* avoid end-of-line conversions */
	_setmode(_fileno(stdin), O_BINARY);
	_setmode(_fileno(stdout), O_BINARY);

	if (argc != 4) {
		fprintf(stderr, "usage: %s <archive> <table of content> <output>\n", argv[0]);
		exit(1);
	}

	FILE *fd_archive, *fd_toc;
	fd_archive = fopen(argv[1], "rb");
	fd_toc = fopen(argv[2], "rb");
	if (!fd_archive || !fd_toc) {
		fprintf(stderr, "failed to open required files: %s\n", strerror(errno));
		exit(2);
	}

	ret = txre_detect_archive(&archive_unpack, fd_archive, fd_toc);
	if (ret == 0) {
		// cd to output dir
		if (_chdir(argv[3])) {
			fprintf(stderr, "couldn't cd into %s: %s\n", argv[3], strerror(errno));
			exit(12);
		}

		// unpack archive
		ret = archive_unpack(fd_archive, fd_toc);
	} else {
		fprintf(stdout, "unsupported archive\n");
	}

	fclose(fd_archive);
	fclose(fd_toc);

	return 0;
}

