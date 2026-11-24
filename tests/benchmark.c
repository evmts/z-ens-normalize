#include "z_ens_normalize.h"
#include <stdio.h>
#include <string.h>
#include <time.h>

static int normalize(const char *input, const char *expected) {
    ZensResult result = zens_normalize((const uint8_t *)input, 0);
    int valid = result.error_code == ZENS_SUCCESS &&
        result.len == strlen(expected) && memcmp(result.data, expected, result.len) == 0;
    zens_free(result);
    return valid;
}

static double nanoseconds(struct timespec start, struct timespec end) {
    return (double)(end.tv_sec - start.tv_sec) * 1e9 + (end.tv_nsec - start.tv_nsec);
}

int main(void) {
    enum { iterations = 10000 };
    struct timespec start, warm, end;
    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0 ||
        !normalize("Nick.ETH", "nick.eth") ||
        clock_gettime(CLOCK_MONOTONIC, &warm) != 0) {
        return 1;
    }

    for (int i = 0; i < iterations; ++i) {
        if (!normalize("Nick.ETH", "nick.eth") ||
            !normalize("Café.ETH", "café.eth") ||
            !normalize("🏴‍☠️.ETH", "🏴‍☠.eth")) {
            return 1;
        }
    }

    if (clock_gettime(CLOCK_MONOTONIC, &end) != 0) return 1;
    printf("Cold first normalization: %.2f ms\n", nanoseconds(start, warm) / 1e6);
    printf("Warm ASCII/Unicode/emoji average: %.0f ns/name (%d names)\n",
        nanoseconds(warm, end) / (3 * iterations), 3 * iterations);
    zens_deinit();
    return 0;
}
