#ifndef ENS_NORMALIZE_H
#define ENS_NORMALIZE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Normalize an ENS name
 * 
 * @param input Input string (UTF-8)
 * @param input_len Length of input string
 * @param output Output buffer for normalized string
 * @param output_len Pointer to output buffer length (in: buffer size, out: actual length)
 * @return 0 on success, negative error code on failure:
 *         -1: Out of memory
 *         -3: Other error
 *         -4: Output buffer too small
 */
int ens_normalize(const char* input, size_t input_len, char* output, size_t* output_len);

/**
 * Beautify an ENS name (add visual formatting)
 * 
 * @param input Input string (UTF-8)
 * @param input_len Length of input string
 * @param output Output buffer for beautified string
 * @param output_len Pointer to output buffer length (in: buffer size, out: actual length)
 * @return 0 on success, negative error code on failure:
 *         -1: Out of memory
 *         -3: Other error
 *         -4: Output buffer too small
 */
int ens_beautify(const char* input, size_t input_len, char* output, size_t* output_len);

/**
 * Process an ENS name (normalize and beautify in one call)
 * 
 * @param input Input string (UTF-8)
 * @param input_len Length of input string
 * @param normalized Output buffer for normalized string
 * @param normalized_len Pointer to normalized buffer length (in: buffer size, out: actual length)
 * @param beautified Output buffer for beautified string
 * @param beautified_len Pointer to beautified buffer length (in: buffer size, out: actual length)
 * @return 0 on success, negative error code on failure:
 *         -1: Out of memory
 *         -3: Other error
 *         -4: Normalized buffer too small
 *         -5: Beautified buffer too small
 */
int ens_process(const char* input, size_t input_len, 
                char* normalized, size_t* normalized_len,
                char* beautified, size_t* beautified_len);

#ifdef __cplusplus
}
#endif

#endif /* ENS_NORMALIZE_H */