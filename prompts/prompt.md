
<prompt>
<goal>
Your primary goal is to refactor an existing Zig implementation of the ENSIP-15 normalization standard. The refactoring should focus on improving architectural soundness, correctness, efficiency, and maintainability by addressing several key issues identified in a code review. You will not be adding new features, but rather improving the structure and quality of the existing, functional code.
</goal>

<context>
You are working with a Zig project located in the `/Users/williamcory/ens-normalize-rs/` directory. This project provides a library and an executable for ENS (Ethereum Name Service) name normalization. The core logic is implemented in Zig files within the `src/` directory, with a comprehensive test suite in the `tests/` directory, all managed by `build.zig`.

A detailed code review has already been performed on the following key files:
- `build.zig`: The build script.
- `src/root.zig`: The public API facade.
- `src/normalizer.zig`: The main orchestrator struct (`EnsNameNormalizer`).
- `src/tokenizer.zig`: The initial input string-to-token processing logic.
- `src/validator.zig`: The validation logic for tokenized names.

The current architecture is functional but has several areas that need improvement. Specifically, it suffers from inefficient data loading, overly complex data structures, and some leftover hardcoded data that conflicts with the dynamic data loaded from spec files.
</context>

<tasks>

<task title="Task 1: Centralize All Specification Data Loading and Ownership">
    <problem>
    Currently, various components load their own required data from disk (e.g., `spec.zon`, `confusables.zon`, `scripts.zon`). For example, `validator.zig`'s `validateLabel` function loads script groups and confusable data every time it's called. This is highly inefficient, leading to redundant file I/O and parsing, especially when processing multiple names.
    </problem>
    <solution>
    You must refactor the data loading mechanism to a centralized ownership model.
    1.  Modify the `EnsNameNormalizer` struct in `src/normalizer.zig` to own all the necessary specification data. This includes:
        - `code_points.CodePointsSpecs` (already present)
        - `script_groups.ScriptGroups`
        - `confusables.ConfusableData`
        - `nfc.NFCData`
    2.  Update `EnsNameNormalizer.init` (or `default`) to load all of this data once upon initialization.
    3.  Update `EnsNameNormalizer.deinit` to correctly free the memory for all the newly added data structures.
    4.  Modify the function signatures of `process`, `validateLabel`, `tokenize`, etc., to accept `*const` references to these data structures instead of loading them internally. For example, `validateLabel` should change from `validateLabel(allocator, tokenized_name, specs)` to something like `validateLabel(allocator, tokenized_name, specs, script_groups, confusable_data)`.
    5.  Trace the function calls from `EnsNameNormalizer.process` downwards and plumb the data references through as needed.
    </solution>
    <expected_outcome>
    The `EnsNameNormalizer` struct will be the single source of truth for all specification data. Functions like `validateLabel` will become pure, stateless functions that operate on their inputs and the provided data references, with no internal file I/O. This will significantly improve performance when normalizing multiple names with the same `EnsNameNormalizer` instance.
    </expected_outcome>
</task>

<task title="Task 2: Refactor the Tokenization and NFC Pipeline">
    <problem>
    The tokenization process in `src/tokenizer.zig` is overly complex. The `Token` struct has a recursive `nfc` variant that can contain other tokens, making memory management and logic complex. The functions `applyNFCTransform` and `collapseValidTokens` perform difficult and error-prone in-place modifications on an `ArrayList` of tokens.
    </problem>
    <solution>
    You must refactor the entire tokenization and normalization pipeline to be a series of distinct, sequential stages that are easier to manage.
    1.  **Simplify `Token` Struct:** Remove the `.nfc` variant from the `Token` struct's union in `src/tokenizer.zig`. The tokenizer's job is only to produce a flat list of tokens, not to handle NFC.
    2.  **Isolate Tokenization:** The `tokenizeInputWithMappingsImpl` function should be simplified. Its only job is to produce a flat `[]Token` containing `.valid`, `.mapped`, `.ignored`, `.disallowed`, `.emoji`, and `.stop` tokens.
    3.  **Create a Separate Collapse Function:** Refactor `collapseValidTokens`. It should now take `[]const Token` as input and return a *new* `[]Token` (i.e., `![]Token`) with consecutive `.valid` tokens merged. It should not modify the input slice.
    4.  **Create a Separate NFC Normalization Function:** Create a new function, perhaps in `src/nfc.zig` or `src/normalizer.zig`, called `performNFC`. This function will take a `[]const Token` (the output from the collapse step) and the `NFCData`. It will iterate through the tokens, apply NFC normalization to sequences of text-based tokens (`.valid`, `.mapped`), and return a final, fully normalized `[]Token`. If normalization results in a change, the original tokens are discarded and replaced by a new sequence of `.valid` tokens in the output list.
    5.  **Integrate the New Pipeline:** In `src/normalizer.zig`, update the `process` function to call these stages in sequence: `tokenize` -> `collapse` -> `performNFC`. The final list of tokens is what should be passed to the validator.
    </solution>
    <expected_outcome>
    The tokenization and normalization logic will be separated into a clean, multi-stage pipeline. The `Token` struct will be simple, and the complex, error-prone in-place array modifications will be eliminated, making the code more robust, modular, and easier to test and maintain.
    </expected_outcome>
</task>

<task title="Task 3: Remove Hardcoded Data and Dead Code">
    <problem>
    The codebase contains remnants of an earlier implementation, including hardcoded data and unused functions that conflict with the current data-driven approach.
    - `src/validator.zig` contains a `CharacterValidator` struct with hardcoded lists like `FENCED_CHARS` and `COMBINING_MARKS`.
    - `src/tokenizer.zig` contains an unused `CharacterSpecs` struct and an unused `tokenizeInput` function.
    </problem>
    <solution>
    You must perform the following cleanup:
    1.  In `src/validator.zig`, delete the entire `CharacterValidator` struct and the `checkFencedCharactersHardcoded` function.
    2.  Go through `validator.zig` and ensure that any logic that was using `CharacterValidator` (e.g., `isFenced`) is now using the `CodePointsSpecs` data passed in from the `EnsNameNormalizer`.
    3.  In `src/tokenizer.zig`, delete the entire `CharacterSpecs` struct and the `tokenizeInput` function.
    </solution>
    <expected_outcome>
    The codebase will be cleaner and more correct, with a single source of truth for all character properties (the data loaded from `spec.zon`). This eliminates the risk of bugs caused by outdated, hardcoded values.
    </expected_outcome>
</task>

<task title="Task 4: Address Efficiency and Consistency Issues">
    <problem>
    Several smaller issues related to efficiency and logical consistency were identified.
    1.  The standalone `normalize` and `beautify` functions in `src/normalizer.zig` do not perform validation, which is inconsistent with `EnsNameNormalizer.process` and potentially unsafe.
    2.  The `beautifyTokens` function in `src/normalizer.zig` is incomplete and does not correctly implement beautification for emojis (which involves ensuring FE0F is present).
    3.  The method for finding unique code points in `src/validator.zig` uses a `HashMap`, which is less efficient than sorting for this use case.
    </problem>
    <solution>
    1.  Refactor the standalone `normalize` and `beautify` functions in `src/normalizer.zig`. They should create a default `EnsNameNormalizer` instance and call its `.process()` method to ensure validation is always run, then call `.normalize()` or `.beautify()` on the result.
    2.  Update the `beautifyTokens` logic. When processing an `.emoji` token, it should use the `emoji` field from the token data (the fully-qualified version), not the `cps` field (the FE0F-stripped version).
    3.  In `src/validator.zig`, replace the `HashMap`-based unique codepoint generation with a more efficient sort-based approach. You can `dupe` the slice, `std.mem.sort` it, and then use `std.mem.uniq` to get the unique values.
    </solution>
    <expected_outcome>
    The library will be more consistent in its behavior, the beautification logic will be more correct, and certain operations will be more memory- and CPU-efficient.
    </expected_outcome>
</task>

<task title="Task 5: Refactor `build.zig` for Reduced Boilerplate">
    <problem>
    The `build.zig` file has a large amount of repetitive code for adding each of the ~15 test files. Each test definition is nearly identical.
    </problem>
    <solution>
    1.  Create a helper function within `build.zig`, for example `addEnsTest(b: *std.Build, comptime test_path: []const u8, lib_mod: *std.Build.Module) void`.
    2.  This function will contain the logic for `b.addTest`, `root_module.addImport`, and `b.addRunArtifact`.
    3.  Replace the repetitive blocks of code in `build.zig` with calls to this new helper function for each test file.
    4.  Ensure the `test_step` correctly depends on the run artifacts produced by the helper function.
    </solution>
    <expected_outcome>
    The `build.zig` script will be significantly shorter, cleaner, and easier to maintain. Adding new test files in the future will only require a single line of code.
    </expected_outcome>
</task>

</tasks>

<general_instructions>
- You must work incrementally through the tasks, starting with Task 1, as later tasks may depend on the architectural changes made in earlier ones.
- After each major change, run the test suite using `zig build test` to ensure that you have not introduced any regressions. All tests must pass upon completion.
- Adhere strictly to Zig's idioms and the existing code style. Pay close attention to memory management, ensuring there are no leaks.
- The public API exposed in `src/root.zig` should remain unchanged. The refactoring is internal.
- Provide clear and concise commit messages for each task if you are asked to commit your changes.
</general_instructions>

</prompt>
