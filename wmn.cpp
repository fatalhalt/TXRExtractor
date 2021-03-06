#include "stdafx.h"
#include "wmn.h"

#define ZLIB_WINAPI
#include <zlib.h>

#include <io.h>
#include <errno.h>
#include <memory.h>
#include <assert.h>

#ifdef TXREXTRACTOR_GUI_BUILD
  #define WIN32_LEAN_AND_MEAN
  #include <windows.h>
  extern HWND g_hWnd_tb4;  // output textfield for the GUI
#endif

// recusive mkdir, if traling dir has a dot it is assumed it's a file and is skipped
int mkdirr(const char *path)
{
	int ret = 0;
	static int depth = 0;
	char *dir = NULL;

	if (dir = ((char *) strrchr(path, '/')) ) {
		*dir = '\0';
		depth++;
		ret = mkdirr(path);
		depth--;
		*dir = '/';

		if (ret) // if we fail, we cannot continue creating subdirs
			return ret;
	}

	if (strlen(path)) {
		if (depth == 0 && strchr(path, '.') != NULL)
			return 0; // if trailing dir has a dot, it is probably a file, skip it

		if (ret = _mkdir(path)) {
			if ((EEXIST == errno))
				ret = 0;
		}
	}

	return ret;
}

int wmn_dat_inflate_file(FILE *fd_archive, struct WMN_DAT_CHUNK dat_chunk, struct WMN_TOC_DIR_ENTRY dir_entry,
						void **file, size_t *file_sz, const char *fname) {
	int ret;
	unsigned have;
	z_stream strm;

	unsigned char chunk_deflated[WMN_INFLATE_CHUNK_MAX_SZ] = { 0 };
	unsigned char chunk_inflated[WMN_INFLATE_CHUNK_MAX_SZ] = { 0 };
	long chunk_inflated_sz; // cumulative sum
	long chunk_deflated_sz = dat_chunk.sz_of_curr_deflated_chunk;
	long inflated_amount = 0;
	long file_inflate_alloc_sz = dat_chunk.file_inflate_sz;
	long file_offset = ftell(fd_archive);

	// there are some nondeflatable files that don't need inflating
	if (dir_entry.file_sz == 0) {
		// dir_entry.file_zsz in these rare cases actually specifies uncompressed file size
		file_inflate_alloc_sz = dir_entry.file_zsz; 
	}

	*file = (void *)malloc(file_inflate_alloc_sz);
	if (!file) {
		fprintf(stderr, "failed to allocate %l memory for %s: %s\n", dat_chunk.file_inflate_sz, fname, strerror(errno));
		exit(11);
	}

	// for nondeflatable files we return early in this function
	if (dir_entry.file_sz == 0) {
		int sz = sizeof(struct WMN_DAT_CHUNK);
		fseek(fd_archive, -sz, SEEK_CUR);
		fread(*file, dir_entry.file_zsz, 1, fd_archive);
		*file_sz = dir_entry.file_zsz;
		return 0;
	}


	while (inflated_amount < (long) dat_chunk.file_inflate_sz) {
		chunk_inflated_sz = 0;

		/* allocate inflate state */
		strm.zalloc = Z_NULL;
		strm.zfree = Z_NULL;
		strm.opaque = Z_NULL;
		strm.avail_in = 0;
		strm.next_in = Z_NULL;
		ret = inflateInit(&strm);
		if (ret != Z_OK)
			return ret;

		/* decompress until deflate stream ends or end of file */
		do {
			strm.avail_in = fread((void *)chunk_deflated, 1, chunk_deflated_sz, fd_archive);
			if (ferror(fd_archive)) {
				(void) inflateEnd(&strm);
				return Z_ERRNO;
			}
			if (strm.avail_in == 0)
				break;
			strm.next_in = chunk_deflated;

			/* run inflate() on input until output buffer not full */
			do {
				strm.avail_out = WMN_INFLATE_CHUNK_MAX_SZ;
				strm.next_out = chunk_inflated;
				ret = inflate(&strm, Z_NO_FLUSH);
				assert(ret != Z_STREAM_ERROR);  /* state not clobbered */
				switch (ret) {
				case Z_NEED_DICT:
					ret = Z_DATA_ERROR;     /* and fall through */
				case Z_DATA_ERROR:
				case Z_MEM_ERROR:
					(void) inflateEnd(&strm);
					return ret;
				}
				have = WMN_INFLATE_CHUNK_MAX_SZ - strm.avail_out;

				chunk_inflated_sz += have;
			} while (strm.avail_out == 0);

			/* done when inflate() says it's done */
		} while (ret != Z_STREAM_END);

		memcpy((void *) (((char *) *file) + inflated_amount), chunk_inflated, chunk_inflated_sz);
		inflated_amount += chunk_inflated_sz;

		/* clean up */
		(void) inflateEnd(&strm);
		if (ret != Z_STREAM_END)
			return ret;

		file_offset = ftell(fd_archive);
		file_offset = (file_offset + 3) & ~3; // align to 4 bytes
		fseek(fd_archive, file_offset, SEEK_SET);

		// this is where we will read deflated size of next chunk which is followed by 4 byte 0x0h
		fread(&chunk_deflated_sz, sizeof(uint32_t), 1, fd_archive);
		fseek(fd_archive, sizeof(uint32_t), SEEK_CUR);
	}

	return 0;
}

// populates filenames
int wmn_toc_parse_filenames(FILE *fd_toc, struct WMN_TOC_HEADER toc_header, char **filenames) {
	struct WMN_TOC_TBL_SECTION tbl_section;
	long offset_tbl;
	uint32_t i, j;
	int ret;
	char c;

	// first 8 bytes is fourcc and magicver, next 8 is "def " and its size, next 8 is for "inf " and its size...
	offset_tbl = 8 + 8 + toc_header.def_section_sz + 8 + toc_header.inf_section_sz;

	// below fseek assumes fixed size for WMN_TOC_HEADER which is 48 and fixed size of "def " section of 24 bytes
	if (fseek(fd_toc, sizeof(struct WMN_TOC_HEADER) + toc_header.inf_section_sz, SEEK_SET) == 0) {
		ret = fread((void *) &tbl_section, sizeof(struct WMN_TOC_TBL_SECTION), 1, fd_toc);
		if (ret != 1 || !(strncmp(tbl_section.tbl_section, "tbl ", 4) == 0)) {
			fprintf(stderr, "failed to parse valid Wangan Midnight tbl section\n");
			exit(6);
		}
		printf("successfully parsed tbl section at 0x%08x\n", offset_tbl);

		for (i = 0; i < toc_header.number_of_files; i++) {
			filenames[i] = (char *) malloc(sizeof(char) * WMN_FILENAME_MAX_SZ);
			if (!filenames[i]) {
				fprintf(stderr, "couldn't allocate memory for filename %d\n", i + 1);
				exit(7);
			}
			
			for (j = 0, c = fgetc(fd_toc); j < WMN_FILENAME_MAX_SZ && c != '\0'; j++) {
				c = fgetc(fd_toc);
				filenames[i][j] = c;
			}
		}

		printf("successfully parsed filenames\n");
	}
	else {
		fprintf(stderr, "couldn't seek to tbl section in toc\n");
		exit(4);
	}

	return 0;
}

// this function loops through all file entries and attempts to dump them
// there's an entry for each file, refer to struct WMN_TOC_DIR_ENTRY
int wmn_toc_parse_dir_entries(FILE *fd_archive, FILE *fd_toc, struct WMN_TOC_HEADER toc_header, char **filenames) {
	uint32_t i = 0;
	int ret;
	FILE *fd_output;

	void *file;
	size_t file_sz;
	long file_offset;

	struct WMN_DAT_CHUNK dat_chunk;
	struct WMN_TOC_DIR_ENTRY dir_entry;
	long offset_fentry;

	// adjust fd_toc to point to first file entry
	rewind(fd_toc);
	offset_fentry = 16 + toc_header.def_section_sz + 8;

	// this loop's function is walk through all file entries in toc (directory) and gather info such as offsets to the files
	// in the archive to be able to dump them
	do {
		// create directory tree
		mkdirr(filenames[i]);

		// parse toc file entries aka directory
		fseek(fd_toc, offset_fentry, SEEK_SET);
		ret = fread((void *) &dir_entry, sizeof(struct WMN_TOC_DIR_ENTRY), 1, fd_toc);
		if (ret != 1) {
			fprintf(stderr, "failed to load toc file entry %d\n", i+1);
			exit(10);
		}
		printf("successfully loaded file entry from toc at 0x%08x\n", offset_fentry);

		// get file offset and file size from dir entry
		file_offset = dir_entry.file_offset * toc_header.alignment; // offsets are 2048 byte aligned for Wangan Midnight
		file_sz = dir_entry.file_sz;

		// parse header of leading deflated chunk from archive and check for validity
		fseek(fd_archive, file_offset, SEEK_SET);
		ret = fread((void *) &dat_chunk, sizeof(struct WMN_DAT_CHUNK), 1, fd_archive);
		if (ret != 1 || (dir_entry.file_sz > 0 && (!(strncmp(dat_chunk.fourcc, "GARC", 4) == 0) || !(strncmp(dat_chunk.file_zlib_magic, "zlib ", 4) == 0))) ) {
			fprintf(stderr, "failed to parse valid Wangan Midnight zlib deflate chunk\n");
			exit(9);
		}

		printf("successfully parsed leading deflate chunk from archive at 0x%08x\n", file_offset);

		// at this point we may inflate chunks and attempt to dump a file
		if (fd_output = fopen(filenames[i], "wb")) {
			// fd_archive here points to zlib header e.g. 78 9C ...
			ret = wmn_dat_inflate_file(fd_archive, dat_chunk, dir_entry, &file, &file_sz, filenames[i]);
			if (ret) {
				fprintf(stderr, "zlib stream error: %d\n", ret);
				exit(13);
			}

			fwrite(file, file_sz, 1, fd_output);
			printf("DUMPING %s\n", filenames[i]);
#ifdef TXREXTRACTOR_GUI_BUILD
            char str_buff[512];
            sprintf(str_buff, "%s\n", filenames[i]);
            int outputTextboxLength = 0;
            outputTextboxLength = GetWindowTextLength(g_hWnd_tb4);
            SendMessage(g_hWnd_tb4, EM_SETSEL, (WPARAM) outputTextboxLength, (LPARAM) outputTextboxLength);  // set selection to end of text
            SendMessage(g_hWnd_tb4, EM_REPLACESEL, 0, (LPARAM) str_buff);
#endif

			fclose(fd_output);
			free(file);
		}
		else {
			fprintf(stderr, "error writing %s: %s\n", filenames[i], strerror(errno));
			exit(8);
		}

		i++;
		offset_fentry += sizeof(struct WMN_TOC_DIR_ENTRY);

	} while (i < toc_header.number_of_files);

	return 0;
}

int wmn_extract(FILE *fd_archive, FILE *fd_toc) {
	struct WMN_TOC_HEADER toc_header;
	char **filenames;
	int i, ret;

	rewind(fd_archive);
	rewind(fd_toc);

	// parse toc header and check for validity
	ret = fread((void *) &toc_header, sizeof(struct WMN_TOC_HEADER), 1, fd_toc);
	if ( ret != 1 || !(strncmp(toc_header.fourcc, "BLDh", 4) == 0) || !(strncmp(toc_header.def_section, "def ", 4) == 0) ) {
		fprintf(stderr, "failed to parse valid Wangan Midnight toc header\n");
		exit(3);
	}
	printf("successfully parsed toc header\n");

	// seek to tbl section and parse all filenames in toc file
	filenames = (char **) malloc(toc_header.number_of_files * sizeof(char *));
	if (filenames) {
		ret = wmn_toc_parse_filenames(fd_toc, toc_header, filenames);
		wmn_toc_parse_dir_entries(fd_archive, fd_toc, toc_header, filenames);
	}
	else {
		fprintf(stderr, "couldn't allocate memory for filenames: %s\n", strerror(errno));
		exit(5);
	}


	// cleanup
	if (filenames) {
		for (i = 0; i < (int) toc_header.number_of_files; i++)
			free(filenames[i]);
		free(filenames);
	}

	return 0;
}

int wmn_extract_audio(FILE *fd_archive, FILE *fd_toc) {
	// audio files are stored uncompressed, since wmn_dat_inflate_file already can handle non zlib deflated files
	// we can call wmn_extract directly
	return wmn_extract(fd_archive, fd_toc);
}
