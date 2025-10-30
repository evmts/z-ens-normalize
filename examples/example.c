/**
 * Example C program demonstrating z-ens-normalize usage
 *
 * Compile and run:
 *   zig build c-lib
 *   gcc examples/example.c -I./include -L./zig-out/lib -lz_ens_normalize_c -o example
 *   ./example
 */

#include <stdio.h>
#include <string.h>
#include "z_ens_normalize.h"

void print_result(const char *operation, ZensResult result) {
    if (result.error_code == ZENS_SUCCESS) {
        printf("%s: %.*s\n", operation, (int)result.len, result.data);
        zens_free(result);
    } else {
        printf("%s failed: %s (code: %d)\n",
               operation,
               zens_error_message(result.error_code),
               result.error_code);
    }
}

int main(void) {
    // Initialize the library (optional but recommended)
    if (zens_init() != 0) {
        fprintf(stderr, "Failed to initialize library\n");
        return 1;
    }

    printf("z-ens-normalize C API Examples\n");
    printf("================================\n\n");

    // Example 1: Basic normalization
    printf("Example 1: Basic Normalization\n");
    ZensResult result1 = zens_normalize((const uint8_t *)"Nick.ETH", 0);
    print_result("  normalize('Nick.ETH')", result1);
    printf("\n");

    // Example 2: Normalization with explicit length
    printf("Example 2: Normalization with Length\n");
    const char *test2 = "VITALIK.eth";
    ZensResult result2 = zens_normalize((const uint8_t *)test2, strlen(test2));
    print_result("  normalize('VITALIK.eth')", result2);
    printf("\n");

    // Example 3: Beautification
    printf("Example 3: Beautification\n");
    ZensResult result3 = zens_beautify((const uint8_t *)"🚀RaFFY🚴‍♂️.eTh", 0);
    print_result("  beautify('🚀RaFFY🚴‍♂️.eTh')", result3);
    printf("\n");

    // Example 4: Error handling - empty label
    printf("Example 4: Error Handling (Empty Label)\n");
    ZensResult result4 = zens_normalize((const uint8_t *)"invalid..name", 0);
    print_result("  normalize('invalid..name')", result4);
    printf("\n");

    // Example 5: Error handling - disallowed character
    printf("Example 5: Error Handling (Disallowed Character)\n");
    ZensResult result5 = zens_normalize((const uint8_t *)"test@example.eth", 0);
    print_result("  normalize('test@example.eth')", result5);
    printf("\n");

    // Example 6: Unicode handling
    printf("Example 6: Unicode Handling\n");
    ZensResult result6 = zens_normalize((const uint8_t *)"café.eth", 0);
    print_result("  normalize('café.eth')", result6);
    printf("\n");

    // Example 7: Multiple normalizations (reusing library)
    printf("Example 7: Batch Processing\n");
    const char *names[] = {
        "alice.eth",
        "bob.eth",
        "charlie.eth",
        "Ξ.eth"
    };

    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        ZensResult result = zens_normalize((const uint8_t *)names[i], 0);
        if (result.error_code == ZENS_SUCCESS) {
            printf("  [%zu] %s -> %.*s\n",
                   i, names[i], (int)result.len, result.data);
            zens_free(result);
        } else {
            printf("  [%zu] %s -> ERROR: %s\n",
                   i, names[i], zens_error_message(result.error_code));
        }
    }
    printf("\n");

    // Cleanup the library (optional)
    zens_deinit();

    printf("All examples completed successfully!\n");
    return 0;
}
