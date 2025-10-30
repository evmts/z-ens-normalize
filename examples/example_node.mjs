/**
 * Node.js WebAssembly example for z-ens-normalize
 *
 * Usage:
 *   zig build wasm
 *   node examples/example_node.mjs
 */

import { readFile } from 'fs/promises';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Error code mappings
const ERROR_MESSAGES = {
    0: "Success",
    [-1]: "Out of memory",
    [-2]: "Invalid UTF-8 encoding",
    [-3]: "Invalid label extension (-- at positions 2-3)",
    [-4]: "Illegal script mixture",
    [-5]: "Whole confusable",
    [-6]: "Leading underscore",
    [-7]: "Fenced leading",
    [-8]: "Fenced adjacent",
    [-9]: "Fenced trailing",
    [-10]: "Disallowed character",
    [-11]: "Empty label",
    [-12]: "Combining mark leading",
    [-13]: "Combining mark after emoji",
    [-14]: "Non-spacing mark duplicate",
    [-15]: "Non-spacing mark excessive",
    [-99]: "Unknown error"
};

class ZensNormalize {
    constructor(instance) {
        this.instance = instance;
        this.exports = instance.exports;
        this.memory = this.exports.memory;
        this.encoder = new TextEncoder();
        this.decoder = new TextDecoder();

        // Initialize library
        this.exports.zens_init();
    }

    writeStringToMemory(str) {
        const bytes = this.encoder.encode(str);
        const ptr = this.exports.malloc(bytes.length + 1);
        const memory = new Uint8Array(this.memory.buffer);
        memory.set(bytes, ptr);
        memory[ptr + bytes.length] = 0; // null terminator
        return { ptr, len: bytes.length };
    }

    readResult(resultPtr) {
        const memory = new Uint8Array(this.memory.buffer);
        const view = new DataView(this.memory.buffer);

        // ZensResult struct layout: data (4 bytes), len (4 bytes), error_code (4 bytes)
        const dataPtr = view.getUint32(resultPtr, true);
        const len = view.getUint32(resultPtr + 4, true);
        const errorCode = view.getInt32(resultPtr + 8, true);

        if (errorCode !== 0) {
            return {
                success: false,
                error: ERROR_MESSAGES[errorCode] || "Unknown error",
                code: errorCode
            };
        }

        const bytes = memory.slice(dataPtr, dataPtr + len);
        const text = this.decoder.decode(bytes);

        // Free the result
        this.exports.zens_free(resultPtr);

        return { success: true, text };
    }

    normalize(input) {
        const { ptr, len } = this.writeStringToMemory(input);
        const resultPtr = this.exports.zens_normalize(ptr, len);
        return this.readResult(resultPtr);
    }

    beautify(input) {
        const { ptr, len } = this.writeStringToMemory(input);
        const resultPtr = this.exports.zens_beautify(ptr, len);
        return this.readResult(resultPtr);
    }

    deinit() {
        this.exports.zens_deinit();
    }
}

async function main() {
    console.log('z-ens-normalize Node.js WebAssembly Example');
    console.log('============================================\n');

    // Load WASM module
    const wasmPath = join(__dirname, '../zig-out/bin/z_ens_normalize.wasm');
    const wasmBuffer = await readFile(wasmPath);
    const { instance } = await WebAssembly.instantiate(wasmBuffer, {
        env: {
            // Provide any required imports here
        }
    });

    const zens = new ZensNormalize(instance);

    // Example 1: Basic normalization
    console.log('Example 1: Basic Normalization');
    let result = zens.normalize('Nick.ETH');
    if (result.success) {
        console.log(`  Input:  'Nick.ETH'`);
        console.log(`  Output: '${result.text}'`);
    } else {
        console.log(`  Error: ${result.error}`);
    }
    console.log();

    // Example 2: Beautification
    console.log('Example 2: Beautification');
    result = zens.beautify('🚀RaFFY🚴‍♂️.eTh');
    if (result.success) {
        console.log(`  Input:  '🚀RaFFY🚴‍♂️.eTh'`);
        console.log(`  Output: '${result.text}'`);
    } else {
        console.log(`  Error: ${result.error}`);
    }
    console.log();

    // Example 3: Error handling - empty label
    console.log('Example 3: Error Handling (Empty Label)');
    result = zens.normalize('invalid..name');
    if (result.success) {
        console.log(`  Output: '${result.text}'`);
    } else {
        console.log(`  Input:  'invalid..name'`);
        console.log(`  Error: ${result.error} (code: ${result.code})`);
    }
    console.log();

    // Example 4: Error handling - disallowed character
    console.log('Example 4: Error Handling (Disallowed Character)');
    result = zens.normalize('test@example.eth');
    if (result.success) {
        console.log(`  Output: '${result.text}'`);
    } else {
        console.log(`  Input:  'test@example.eth'`);
        console.log(`  Error: ${result.error} (code: ${result.code})`);
    }
    console.log();

    // Example 5: Batch processing
    console.log('Example 5: Batch Processing');
    const names = [
        'VITALIK.eth',
        'café.eth',
        'Ξ.eth',
        'alice.eth',
        'bob.eth'
    ];

    for (const name of names) {
        result = zens.normalize(name);
        if (result.success) {
            console.log(`  ${name.padEnd(20)} -> ${result.text}`);
        } else {
            console.log(`  ${name.padEnd(20)} -> ERROR: ${result.error}`);
        }
    }
    console.log();

    // Example 6: Unicode handling
    console.log('Example 6: Unicode Normalization');
    const unicodeNames = [
        'café.eth',      // composed
        'café.eth',      // decomposed (looks the same but different bytes)
        '🏴‍☠️.eth',       // emoji with ZWJ
    ];

    for (const name of unicodeNames) {
        result = zens.normalize(name);
        if (result.success) {
            console.log(`  Input:  '${name}'`);
            console.log(`  Output: '${result.text}'`);
            console.log(`  Bytes:  ${Buffer.from(result.text).toString('hex')}`);
            console.log();
        }
    }

    // Cleanup
    zens.deinit();

    console.log('All examples completed successfully!');
}

main().catch(err => {
    console.error('Error:', err);
    process.exit(1);
});
