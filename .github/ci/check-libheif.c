#include <libheif/heif.h>

#include <stdio.h>
#include <string.h>

static int require_format(enum heif_compression_format format,
						  const char *name) {
	if (!heif_have_decoder_for_format(format)) {
		fprintf(stderr, "missing %s decoder\n", name);
		return 1;
	}
	if (!heif_have_encoder_for_format(format)) {
		fprintf(stderr, "missing %s encoder\n", name);
		return 1;
	}
	return 0;
}

static int require_decoder(const char *id) {
	const struct heif_decoder_descriptor *descriptors[16];
	int count = heif_get_decoder_descriptors(heif_compression_AV1, descriptors,
										16);
	int i;

	for (i = 0; i < count; i++) {
		const char *candidate =
			heif_decoder_descriptor_get_id_name(descriptors[i]);
		if (candidate && strcmp(candidate, id) == 0) {
			return 0;
		}
	}

	fprintf(stderr, "missing AV1 decoder backend: %s\n", id);
	return 1;
}

static int require_encoder(const char *id) {
	const struct heif_encoder_descriptor *descriptors[16];
	int count = heif_get_encoder_descriptors(heif_compression_AV1, NULL,
										 descriptors, 16);
	int i;

	for (i = 0; i < count; i++) {
		const char *candidate =
			heif_encoder_descriptor_get_id_name(descriptors[i]);
		if (candidate && strcmp(candidate, id) == 0) {
			return 0;
		}
	}

	fprintf(stderr, "missing AV1 encoder backend: %s\n", id);
	return 1;
}

int main(void) {
	int failed = 0;

	failed |= require_format(heif_compression_AV1, "AV1");
	failed |= require_format(heif_compression_JPEG, "JPEG-in-HEIF");
	failed |= require_format(heif_compression_uncompressed, "uncompressed");
	failed |= require_decoder("dav1d");
	failed |= require_decoder("aom");
	failed |= require_encoder("aom");

	if (!failed) {
		printf("libheif %s: all required codecs are available\n",
			   heif_get_version());
	}
	return failed;
}
