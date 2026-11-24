#include "z_ens_normalize.h"
#include <stdio.h>
#include <string.h>

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "C API check failed at line %d: %s\n", __LINE__, #condition); \
        return 1; \
    } \
} while (0)

int main(void) {
    CHECK(zens_init() == ZENS_SUCCESS);

    const uint8_t explicit_input[] = {'N', 'i', 'c', 'k', '.', 'E', 'T', 'H'};
    ZensResult result = zens_normalize(explicit_input, sizeof explicit_input);
    CHECK(result.error_code == ZENS_SUCCESS);
    CHECK(result.len == 8 && memcmp(result.data, "nick.eth", result.len) == 0);
    zens_free(result);

    const uint8_t malformed[] = {'a', 0xe2, 0x82};
    result = zens_normalize(malformed, sizeof malformed);
    CHECK(result.error_code == ZENS_ERROR_INVALID_UTF8);
    CHECK(result.data == NULL && result.len == 0);
    zens_free(result);

    zens_normalize_into(&result, (const uint8_t *)"a..eth", 0);
    CHECK(result.error_code == ZENS_ERROR_EMPTY_LABEL);
    CHECK(result.data == NULL && result.len == 0);
    zens_free_result(&result);
    CHECK(strcmp(zens_error_message(result.error_code), "Empty label") == 0);
    CHECK(strcmp(zens_error_message(12345), "Unknown error") == 0);

    const char emoji[] = "🏴‍☠.eth";
    const char beautiful[] = "🏴‍☠️.eth";
    uint8_t *buffer = zens_alloc(sizeof emoji);
    CHECK(buffer != NULL);
    memcpy(buffer, emoji, sizeof emoji);
    zens_beautify_into(&result, buffer, 0);
    CHECK(result.error_code == ZENS_SUCCESS);
    CHECK(result.len == sizeof beautiful - 1);
    CHECK(memcmp(result.data, beautiful, result.len) == 0);
    zens_free_result(&result);
    zens_dealloc(buffer, sizeof emoji);
    zens_deinit();

    CHECK(zens_init() == ZENS_SUCCESS);
    result = zens_normalize((const uint8_t *)"", 0);
    CHECK(result.error_code == ZENS_SUCCESS && result.len == 0);
    zens_free(result);
    zens_deinit();
    return 0;
}
