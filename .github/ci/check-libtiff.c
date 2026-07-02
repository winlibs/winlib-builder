#include <tiffio.h>

#include <stdio.h>

struct codec_check {
	uint16_t scheme;
	const char *name;
};

int main(void)
{
	static const struct codec_check codecs[] = {
		{COMPRESSION_ADOBE_DEFLATE, "Deflate"},
		{COMPRESSION_JPEG, "JPEG"},
		{COMPRESSION_WEBP, "WebP"},
		{COMPRESSION_ZSTD, "Zstd"},
		{COMPRESSION_LZMA, "LZMA"},
	};
	size_t i;
	int failed = 0;

	printf("%s\n", TIFFGetVersion());
	for (i = 0; i < sizeof(codecs) / sizeof(codecs[0]); i++) {
		if (!TIFFIsCODECConfigured(codecs[i].scheme)) {
			fprintf(stderr, "missing TIFF codec: %s\n", codecs[i].name);
			failed = 1;
		}
	}

	return failed;
}
