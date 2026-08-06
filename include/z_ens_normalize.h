/**
 * z-ens-normalize C API
 *
 * Zero-dependency ENS (Ethereum Name Service) name normalization according to ENSIP-15.
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef Z_ENS_NORMALIZE_H
#define Z_ENS_NORMALIZE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

/**
 * Error codes returned by the library.
 */
typedef enum {
    ZENS_SUCCESS = 0,
    ZENS_ERROR_OUT_OF_MEMORY = -1,
    ZENS_ERROR_INVALID_UTF8 = -2,
    ZENS_ERROR_INVALID_LABEL_EXTENSION = -3,
    ZENS_ERROR_ILLEGAL_MIXTURE = -4,
    ZENS_ERROR_WHOLE_CONFUSABLE = -5,
    ZENS_ERROR_LEADING_UNDERSCORE = -6,
    ZENS_ERROR_FENCED_LEADING = -7,
    ZENS_ERROR_FENCED_ADJACENT = -8,
    ZENS_ERROR_FENCED_TRAILING = -9,
    ZENS_ERROR_DISALLOWED_CHARACTER = -10,
    ZENS_ERROR_EMPTY_LABEL = -11,
    ZENS_ERROR_CM_LEADING = -12,
    ZENS_ERROR_CM_AFTER_EMOJI = -13,
    ZENS_ERROR_NSM_DUPLICATE = -14,
    ZENS_ERROR_NSM_EXCESSIVE = -15,
    ZENS_ERROR_UNKNOWN = -99
} ZensErrorCode;

/**
 * Result structure returned by normalization functions.
 *
 * On success:
 *   - error_code = ZENS_SUCCESS
 *   - data points to UTF-8 normalized string
 *   - len is the length in bytes
 *
 * On error:
 *   - error_code contains the error code
 *   - data is NULL
 *   - len is 0
 *
 * Use zens_free() to free the data pointer when done.
 */
typedef struct {
    uint8_t *data;
    size_t len;
    int32_t error_code;
} ZensResult;

/**
 * Initialize the library.
 *
 * This function is optional but recommended to call once at program startup.
 * It initializes internal allocators and caches.
 *
 * @return 0 on success, non-zero on failure
 */
int32_t zens_init(void);

/**
 * Cleanup the library.
 *
 * Call this function at program exit to free any internal resources.
 * After calling this, you must call zens_init() again before using the library.
 */
void zens_deinit(void);

/**
 * Normalize an ENS name according to ENSIP-15.
 *
 * This function converts an ENS name to its canonical normalized form:
 * - Applies Unicode normalization
 * - Validates character restrictions
 * - Checks for confusable characters
 * - Ensures proper label structure
 *
 * Example:
 *   ZensResult result = zens_normalize("Nick.ETH", 0);
 *   if (result.error_code == ZENS_SUCCESS) {
 *       printf("%.*s\n", (int)result.len, result.data);
 *       zens_free(result);
 *   }
 *
 * @param input Null-terminated UTF-8 input string
 * @param input_len Length of input (or 0 to use strlen)
 * @return ZensResult with normalized name or error
 */
ZensResult zens_normalize(const uint8_t *input, size_t input_len);

/**
 * Beautify an ENS name.
 *
 * Similar to normalize but with visual enhancements:
 * - Preserves emoji presentation (FE0F variation selectors)
 * - Converts lowercase Greek xi (ξ) to uppercase Xi (Ξ) in non-Greek labels
 * - More visually appealing for UI display
 *
 * Example:
 *   ZensResult result = zens_beautify("🏴‍☠️nick.eth", 0);
 *   if (result.error_code == ZENS_SUCCESS) {
 *       printf("%.*s\n", (int)result.len, result.data);
 *       zens_free(result);
 *   }
 *
 * @param input Null-terminated UTF-8 input string
 * @param input_len Length of input (or 0 to use strlen)
 * @return ZensResult with beautified name or error
 */
ZensResult zens_beautify(const uint8_t *input, size_t input_len);

/**
 * Free memory allocated by zens_normalize() or zens_beautify().
 *
 * This function must be called for every successful result to prevent memory leaks.
 * It is safe to call on error results (where data is NULL).
 *
 * @param result Result struct from zens_normalize or zens_beautify
 */
void zens_free(ZensResult result);

/**
 * Get a human-readable error message for an error code.
 *
 * The returned string is statically allocated and must not be freed.
 *
 * Example:
 *   if (result.error_code != ZENS_SUCCESS) {
 *       printf("Error: %s\n", zens_error_message(result.error_code));
 *   }
 *
 * @param error_code Error code from ZensResult
 * @return Null-terminated error message string (do not free)
 */
const char *zens_error_message(int32_t error_code);

/*
 * Buffer helpers, primarily for WebAssembly hosts (which have no libc
 * malloc, and where ZensResult cannot be returned by value across the
 * wasm boundary). Usable from C as well.
 */

/**
 * Allocate a buffer owned by the library's allocator.
 *
 * @param len Number of bytes to allocate
 * @return Pointer to the buffer, or NULL on allocation failure
 */
uint8_t *zens_alloc(size_t len);

/**
 * Free a buffer allocated with zens_alloc().
 *
 * @param ptr Pointer returned by zens_alloc (NULL is a no-op)
 * @param len The exact length passed to zens_alloc
 */
void zens_dealloc(uint8_t *ptr, size_t len);

/**
 * Normalize an ENS name, writing the result through a pointer.
 * Equivalent to *result = zens_normalize(input, input_len).
 *
 * @param result Caller-provided result struct to fill
 * @param input UTF-8 input string
 * @param input_len Length of input (or 0 to use strlen)
 */
void zens_normalize_into(ZensResult *result, const uint8_t *input, size_t input_len);

/**
 * Beautify an ENS name, writing the result through a pointer.
 * Equivalent to *result = zens_beautify(input, input_len).
 *
 * @param result Caller-provided result struct to fill
 * @param input UTF-8 input string
 * @param input_len Length of input (or 0 to use strlen)
 */
void zens_beautify_into(ZensResult *result, const uint8_t *input, size_t input_len);

/**
 * Free the data of a result produced by the _into variants.
 * Equivalent to zens_free(*result); does not free the struct itself.
 *
 * @param result Result previously filled by zens_normalize_into/zens_beautify_into
 */
void zens_free_result(const ZensResult *result);

#ifdef __cplusplus
}
#endif

#endif /* Z_ENS_NORMALIZE_H */
