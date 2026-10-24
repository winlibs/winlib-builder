#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
#include <brotli/decode.h>
#include <brotli/encode.h>

#define CHECK(test) do { if (!(test)) { fprintf(stderr, "Failed: %s (line %d)\n", #test, __LINE__); return 1; } } while (0)

int main(void) {
    unsigned char input[4096], compressed[8192], output[8192];
    uLongf compressed_size = sizeof(compressed), output_size = sizeof(output);
    size_t brotli_size = sizeof(compressed), decoded_size = sizeof(output);
    gzFile file;
    size_t i;

    CHECK(strcmp(zlibVersion(), "1.3.2") == 0);
    CHECK(BrotliDecoderVersion() == 0x01002001);
    CHECK(BrotliEncoderVersion() == 0x01002001);
    for (i = 0; i < sizeof(input); i++) input[i] = (unsigned char)(i * 37 + i / 23);
    CHECK(compress2(compressed, &compressed_size, input, sizeof(input), Z_BEST_COMPRESSION) == Z_OK);
    CHECK(uncompress(output, &output_size, compressed, compressed_size) == Z_OK);
    CHECK(output_size == sizeof(input) && memcmp(input, output, sizeof(input)) == 0);

    file = gzopen("apache-compression-smoke.gz", "wb");
    CHECK(file != NULL);
    CHECK(gzbuffer(file, 64) == 0);
    CHECK(gzwrite(file, input, sizeof(input)) == sizeof(input));
    CHECK(gzprintf(file, "-%s-%d", "tail", 123) == 9);
    CHECK(gzclose(file) == Z_OK);
    file = gzopen("apache-compression-smoke.gz", "rb");
    CHECK(file != NULL);
    CHECK(gzread(file, output, sizeof(output)) == sizeof(input) + 9);
    CHECK(memcmp(output, input, sizeof(input)) == 0);
    CHECK(memcmp(output + sizeof(input), "-tail-123", 9) == 0);
    CHECK(gzclose(file) == Z_OK);
    CHECK(remove("apache-compression-smoke.gz") == 0);

    CHECK(BrotliEncoderCompress(11, BROTLI_DEFAULT_WINDOW, BROTLI_MODE_GENERIC,
        sizeof(input), input, &brotli_size, compressed));
    CHECK(BrotliDecoderDecompress(brotli_size, compressed, &decoded_size, output) == BROTLI_DECODER_RESULT_SUCCESS);
    CHECK(decoded_size == sizeof(input) && memcmp(input, output, sizeof(input)) == 0);
    printf("Apache compression QA passed: zlib %s; Brotli 1.2.1; deflate, gzip write/printf/read, Brotli encode/decode\n", zlibVersion());
    return 0;
}
