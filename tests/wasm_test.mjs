import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const { instance: { exports } } = await WebAssembly.instantiate(await readFile(process.argv[2]));
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function transform(fn, bytes) {
    const input = exports.zens_alloc(bytes.length + 1);
    const result = exports.zens_alloc(12);
    assert.ok(input && result);
    const buffer = new Uint8Array(exports.memory.buffer, input, bytes.length + 1);
    buffer.set(bytes);
    buffer[bytes.length] = 0;

    try {
        exports[fn](result, input, bytes.length);
        const view = new DataView(exports.memory.buffer, result, 12);
        const pointer = view.getUint32(0, true);
        const length = view.getUint32(4, true);
        const code = view.getInt32(8, true);
        if (code !== 0) {
            assert.equal(pointer, 0);
            assert.equal(length, 0);
            return code;
        }
        return decoder.decode(new Uint8Array(exports.memory.buffer, pointer, length));
    } finally {
        exports.zens_free_result(result);
        exports.zens_dealloc(result, 12);
        exports.zens_dealloc(input, bytes.length + 1);
    }
}

assert.equal(exports.zens_init(), 0);
assert.equal(transform('zens_normalize_into', encoder.encode('Nick.ETH')), 'nick.eth');
assert.equal(transform('zens_beautify_into', encoder.encode('🏴‍☠.eth')), '🏴‍☠️.eth');
assert.equal(transform('zens_normalize_into', encoder.encode('')), '');
assert.equal(transform('zens_normalize_into', encoder.encode('a..eth')), -11);
assert.equal(transform('zens_normalize_into', Uint8Array.of(0xe2, 0x82)), -2);
exports.zens_deinit();
