#ifndef TXREXTRACTOR_HEADER
#define TXREXTRACTOR_HEADER

typedef int(*archive_unpack_f)(FILE *, FILE *);

// function prototypes
int txre_detect_archive(archive_unpack_f *, FILE *, FILE *);

#endif
