/*
 * Tokyo Xtreme Racer Extractor
 *
 * currently supported archives:
 *   - Wangan Midnight 2007 PS3..............: WMN.DAT (done), AUDIO_PS3.DAT (work in progress...)
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

int main(int argc, char* argv[])
{
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

	// cd to output dir
	if (_chdir(argv[3])) {
		fprintf(stderr, "couldn't cd into %s: %s\n", argv[3], strerror(errno));
		exit(12);
	}

	wmn_extract(fd_archive, fd_toc);

	fclose(fd_archive);
	fclose(fd_toc);

	return 0;
}

