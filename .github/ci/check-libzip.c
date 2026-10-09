#include <zip.h>

#include <stdio.h>
#include <string.h>

static int roundtrip(zip_int32_t method, int encrypted)
{
    const char *path = "check-libzip.zip";
    const char *password = "libzip-static-zstd-check";
    char input[65536], output[sizeof(input)];
    zip_t *archive;
    zip_source_t *source;
    zip_file_t *file;
    zip_stat_t st;
    zip_int64_t index, count;
    size_t i, total = 0;
    int error;

    for (i = 0; i < sizeof(input); i++) {
        input[i] = (char)('a' + i % 23);
    }
    if (!zip_compression_method_supported(method, 1) ||
        !zip_compression_method_supported(method, 0)) {
        fprintf(stderr, "compression method %d is unavailable\n", method);
        return 1;
    }
    archive = zip_open(path, ZIP_CREATE | ZIP_TRUNCATE, &error);
    if (archive == NULL) {
        fprintf(stderr, "zip_open failed: %d\n", error);
        return 1;
    }
    source = zip_source_buffer(archive, input, sizeof(input), 0);
    if (source == NULL) {
        zip_discard(archive);
        return 1;
    }
    index = zip_file_add(archive, "payload.txt", source, ZIP_FL_ENC_UTF_8);
    if (index < 0) {
        zip_source_free(source);
        zip_discard(archive);
        return 1;
    }
    if (zip_set_file_compression(archive, (zip_uint64_t)index, method, 0) != 0 ||
        zip_file_set_mtime(archive, (zip_uint64_t)index, (time_t)1700000000, 0) != 0 ||
        (encrypted && zip_file_set_encryption(archive, (zip_uint64_t)index, ZIP_EM_AES_256, password) != 0)) {
        fprintf(stderr, "archive setup failed: %s\n", zip_strerror(archive));
        zip_discard(archive);
        return 1;
    }
    if (zip_close(archive) != 0) {
        fprintf(stderr, "zip_close failed: %s\n", zip_strerror(archive));
        zip_discard(archive);
        return 1;
    }
    archive = zip_open(path, ZIP_RDONLY, &error);
    if (archive == NULL) {
        return 1;
    }
    zip_stat_init(&st);
    if (zip_stat_index(archive, 0, 0, &st) != 0 || st.size != sizeof(input) ||
        st.comp_method != method || st.mtime != (time_t)1700000000 ||
        st.encryption_method != (encrypted ? ZIP_EM_AES_256 : ZIP_EM_NONE) ||
        (method != ZIP_CM_STORE && st.comp_size >= st.size)) {
        fprintf(stderr, "archive metadata mismatch\n");
        zip_discard(archive);
        return 1;
    }
    file = zip_fopen_index_encrypted(archive, 0, 0, encrypted ? password : NULL);
    if (file == NULL) {
        zip_discard(archive);
        return 1;
    }
    while (total < sizeof(output)) {
        count = zip_fread(file, output + total, sizeof(output) - total);
        if (count <= 0) {
            break;
        }
        total += (size_t)count;
    }
    count = zip_fread(file, output, 1);
    error = zip_fclose(file);
    if (total != sizeof(input) || count != 0 || error != 0 || memcmp(input, output, sizeof(input)) != 0) {
        fprintf(stderr, "archive content mismatch\n");
        zip_discard(archive);
        return 1;
    }
    if (zip_close(archive) != 0) {
        zip_discard(archive);
        return 1;
    }
    if (remove(path) != 0) {
        return 1;
    }
    printf("method %d, AES-256 %s: passed\n", method, encrypted ? "on" : "off");
    return 0;
}

static int torrentzip_roundtrip(void)
{
    const char *path = "check-torrentzip.zip";
    const char *payloads[] = {"original", "replacement"};
    zip_t *archive;
    zip_source_t *source;
    zip_file_t *file;
    char output[32];
    zip_int64_t count;
    int pass, error;

    for (pass = 0; pass < 2; pass++) {
        archive = zip_open(path, pass == 0 ? ZIP_CREATE | ZIP_TRUNCATE : 0, &error);
        if (archive == NULL) {
            return 1;
        }
        if (zip_set_archive_flag(archive, ZIP_AFL_WANT_TORRENTZIP, 1) != 0) {
            zip_discard(archive);
            return 1;
        }
        source = zip_source_buffer(archive, payloads[pass], strlen(payloads[pass]), 0);
        if (source == NULL) {
            zip_discard(archive);
            return 1;
        }
        if ((pass == 0 && zip_file_add(archive, "payload.txt", source, 0) < 0) ||
            (pass == 1 && zip_file_replace(archive, 0, source, 0) != 0)) {
            fprintf(stderr, "torrentzip add/replace failed: %s\n", zip_strerror(archive));
            zip_source_free(source);
            zip_discard(archive);
            return 1;
        }
        if (zip_close(archive) != 0) {
            fprintf(stderr, "torrentzip close failed: %s\n", zip_strerror(archive));
            zip_discard(archive);
            return 1;
        }
        archive = zip_open(path, ZIP_RDONLY, &error);
        if (archive == NULL) {
            return 1;
        }
        if (zip_get_archive_flag(archive, ZIP_AFL_IS_TORRENTZIP, 0) != 1) {
            zip_discard(archive);
            return 1;
        }
        file = zip_fopen_index(archive, 0, 0);
        if (file == NULL) {
            zip_discard(archive);
            return 1;
        }
        count = zip_fread(file, output, sizeof(output));
        error = zip_fclose(file);
        if (count != (zip_int64_t)strlen(payloads[pass]) || error != 0 ||
            memcmp(output, payloads[pass], strlen(payloads[pass])) != 0) {
            zip_discard(archive);
            return 1;
        }
        if (zip_close(archive) != 0) {
            zip_discard(archive);
            return 1;
        }
    }
    if (remove(path) != 0) {
        return 1;
    }
    puts("torrentzip add/replace round trips: passed");
    return 0;
}

int main(void)
{
    static const zip_int32_t methods[] = {ZIP_CM_STORE, ZIP_CM_DEFLATE, ZIP_CM_BZIP2, ZIP_CM_LZMA, ZIP_CM_XZ, ZIP_CM_ZSTD};
    size_t i;
    int encrypted;

    printf("libzip %s\n", zip_libzip_version());
    for (i = 0; i < sizeof(methods) / sizeof(methods[0]); i++) {
        for (encrypted = 0; encrypted <= 1; encrypted++) {
            if (roundtrip(methods[i], encrypted) != 0) {
                return 1;
            }
        }
    }
    return torrentzip_roundtrip();
}
