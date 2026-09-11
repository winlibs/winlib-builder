#include <libheif/heif.h>

#include <stdio.h>
#include <stdlib.h>
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

static void check(struct heif_error error, const char *operation) {
    if (error.code != heif_error_Ok) {
        fprintf(stderr, "%s: %s\n", operation, error.message);
        exit(1);
    }
}

static void roundtrip(enum heif_compression_format format, const char *name) {
    struct heif_context *writer = heif_context_alloc();
    struct heif_context *reader = heif_context_alloc();
    struct heif_image *input = NULL, *output = NULL;
    struct heif_encoder *encoder = NULL;
    struct heif_image_handle *encoded = NULL, *decoded = NULL;
    char filename[64];
    int stride, output_stride, x, y;
    unsigned char *pixels;
    const unsigned char *result;
    long error = 0;
    if (!writer || !reader) exit(1);
    check(heif_context_get_encoder_for_format(writer, format, &encoder), "get encoder");
    check(heif_encoder_set_lossy_quality(encoder, 95), "set quality");
    check(heif_image_create(32, 32, heif_colorspace_RGB, heif_chroma_interleaved_RGB, &input), "create image");
    check(heif_image_add_plane(input, heif_channel_interleaved, 32, 32, 8), "add plane");
    pixels = heif_image_get_plane(input, heif_channel_interleaved, &stride);
    if (!pixels) exit(1);
    for (y = 0; y < 32; y++) {
        for (x = 0; x < 32; x++) {
            pixels[y * stride + 3 * x] = (unsigned char)(x * 4 + 32);
            pixels[y * stride + 3 * x + 1] = (unsigned char)(y * 4 + 32);
            pixels[y * stride + 3 * x + 2] = 80;
        }
    }
    check(heif_context_encode_image(writer, input, encoder, NULL, &encoded), "encode");
    snprintf(filename, sizeof(filename), "security-roundtrip-%s.heif", name);
    check(heif_context_write_to_file(writer, filename), "write");
    check(heif_context_read_from_file(reader, filename, NULL), "read");
    check(heif_context_get_primary_image_handle(reader, &decoded), "get image");
    if (heif_image_handle_get_width(decoded) != 32 || heif_image_handle_get_height(decoded) != 32) exit(1);
    check(heif_decode_image(decoded, &output, heif_colorspace_RGB, heif_chroma_interleaved_RGB, NULL), "decode");
    result = heif_image_get_plane_readonly(output, heif_channel_interleaved, &output_stride);
    if (!result) exit(1);
    for (y = 0; y < 32; y++) {
        for (x = 0; x < 32 * 3; x++) error += abs((int)pixels[y * stride + x] - result[y * output_stride + x]);
    }
    if (error > 32 * 32 * 3 * 8) {
        fprintf(stderr, "%s roundtrip pixel error too large: %ld\n", name, error);
        exit(1);
    }
    printf("%s roundtrip passed, pixel error %ld\n", name, error);
    heif_image_release(output);
    heif_image_handle_release(decoded);
    heif_image_handle_release(encoded);
    heif_encoder_release(encoder);
    heif_image_release(input);
    heif_context_free(reader);
    heif_context_free(writer);
    remove(filename);
}

int main(void) {
	int failed = 0;

	check(heif_init(NULL), "initialize");

	failed |= require_format(heif_compression_AV1, "AV1");
	failed |= require_format(heif_compression_JPEG, "JPEG-in-HEIF");
	failed |= require_format(heif_compression_uncompressed, "uncompressed");
	failed |= require_decoder("dav1d");
	failed |= require_decoder("aom");
	failed |= require_encoder("aom");

	if (!failed) {
		roundtrip(heif_compression_AV1, "av1");
		roundtrip(heif_compression_JPEG, "jpeg");
		roundtrip(heif_compression_uncompressed, "uncompressed");
		printf("libheif %s: all required codecs are available\n",
			   heif_get_version());
	}
	heif_deinit();
	return failed;
}
