# CLAUDE.md - Critical Rules for ENS Normalization Implementation

## 📖 **OFFICIAL SPECIFICATION**

The official ENS Normalization specification is at: https://docs.ens.domains/ensip/15/

### ENSIP-15 ENS Name Normalization Standard - Complete Specification

**Authors:** raffy.eth  
**Created:** April 3, 2023  
**Status:** Final

#### Abstract
This ENSIP standardizes Ethereum Name Service (ENS) name normalization process outlined in ENSIP-1 § Name Syntax.

#### Motivation
Since ENSIP-1 (originally EIP-137) was finalized in 2016, Unicode has evolved from version 8.0.0 to 15.0.0 and incorporated many new characters, including complex emoji sequences.
- ENSIP-1 does not state the version of Unicode.
- ENSIP-1 implies but does not state an explicit flavor of IDNA processing.
- UTS-46 is insufficient to normalize emoji sequences. Correct emoji processing is only possible with UTS-51.
- Validation tests are needed to ensure implementation compliance.
- The success of ENS has encouraged spoofing via the following techniques:
  - Insertion of zero-width characters.
  - Using names which normalize differently between algorithms.
  - Using names which appear differently between applications and devices.
  - Substitution of confusable (look-alike) characters.
  - Mixing incompatible scripts.

#### Specification
- **Unicode version 16.0.0**
- Normalization is a living specification and should use the latest stable version of Unicode.
- `spec.json` contains all necessary data for normalization.
- `nf.json` contains all necessary data for Unicode Normalization Forms NFC and NFD.

#### Definitions
Terms in **bold** throughout this document correspond with components of `spec.json`.

- A **string** is a sequence of Unicode codepoints.
  - Example: "abc" is 61 62 63
- An **Unicode emoji** is a single entity composed of one or more codepoints:
  - An **Emoji Sequence** is the preferred form of an emoji, resulting from input that tokenized into an Emoji token.
  - Example: 💩︎︎ [1F4A9] → Emoji[1F4A9 FE0F]
  - 1F4A9 FE0F is the Emoji Sequence.
  - `spec.json` contains the complete list of valid Emoji Sequences.
  - **Derivation** defines which emoji are normalizable.
  - Not all Unicode emoji are valid.
    - ‼ [203C] double exclamation mark → error: Disallowed character
    - 🈁 [1F201] Japanese "here" button → Text["ココ"]
  - An Emoji Sequence may contain characters that are disallowed:
    - 👩‍❤️‍👨 [1F469 200D 2764 FE0F 200D 1F468] couple with heart: woman, man — contains ZWJ
    - #️⃣ [23 FE0F 20E3] keycap: # — contains 23 (#)
    - 🏴󠁧󠁢󠁥󠁮󠁧󠁿 [1F3F4 E0067 E0062 E0065 E006E E0067 E007F] — contains E00XX
  - An Emoji Sequence may contain other emoji:
    - Example: ❤️ [2764 FE0F] red heart is a substring of ❤️‍🔥 [2764 FE0F 200D 1F525] heart on fire
  - Single-codepoint emoji may have various presentation styles on input:
    - Default: ❤ [2764]
    - Text: ❤︎ [2764 FE0E]
    - Emoji: ❤️ [2764 FE0F]
    - However, these all tokenize to the same Emoji Sequence.
  - All Emoji Sequence have explicit emoji-presentation.
  - The convention of ignoring presentation is difficult to change because:
    - Presentation characters (FE0F and FE0E) are **Ignored**
    - ENSIP-1 did not treat emoji differently from text
    - Registration hashes are immutable
  - **Beautification** can be used to restore emoji-presentation in normalized names.

#### Algorithm
**Normalization** is the process of canonicalizing a name before for hashing.
- It is idempotent: applying normalization multiple times produces the same result.
- For user convenience, leading and trailing whitespace should be trimmed before normalization, as all whitespace codepoints are disallowed. Inner characters should remain unmodified.
- No string transformations (like case-folding) should be applied.
- Split the name into labels.
- Normalize each label.
- Join the labels together into a name again.

##### Normalize
1. **Tokenize** — transform the label into Text and Emoji tokens.
   - If there are no tokens, the label cannot be normalized.
2. Apply **NFC** to each Text token.
   - Example: Text["à"] → [61 300] → [E0] → Text["à"]
3. Strip **FE0F** from each Emoji token.
4. **Validate** — check if the tokens are valid and obtain the Label Type.
   - The Label Type and Restricted state may be presented to user for additional security.
5. Concatenate the tokens together.
6. Return the normalized label.

Examples:
- `"_$A" [5F 24 41] → "_$a" [5F 24 61]` — ASCII
- `"E︎̃" [45 FE0E 303] → "ẽ" [1EBD]` — Latin
- `"𓆏🐸" [1318F 1F438] → "𓆏🐸" [1318F 1F438]` — Restricted: Egyp
- `"nı̇ck" [6E 131 307 63 6B] → error: Disallowed character`

##### Tokenize
Convert a label into a list of Text and Emoji tokens, each with a payload of codepoints. The complete list of character types and emoji sequences can be found in `spec.json`.

1. Allocate an empty codepoint buffer.
2. Find the longest **Emoji Sequence** that matches the remaining input.
   - Example: 👨🏻‍💻 [1F468 1F3FB 200D 1F4BB]
     - Match (1): 👨️ [1F468] man
     - Match (2): 👨🏻 [1F468 1F3FB] man: light skin tone
     - Match (4): 👨🏻‍💻 [1F468 1F3FB 200D 1F4BB] man technologist: light skin tone — longest match!
   - **FE0F** is optional from the input during matching.
     - Example: 👨‍❤️‍👨 [1F468 200D 2764 FE0F 200D 1F468]
       - Match: 1F468 200D 2764 FE0F 200D 1F468 — fully-qualified
       - Match: 1F468 200D 2764 200D 1F468 — missing FE0F
       - No match: 1F468 FE0F 200D 2764 FE0F 200D 1F468 — extra FE0F
       - No match: 1F468 200D 2764 FE0F FE0F 200D 1F468 — has (2) FE0F
   - This is equivalent to `/^(emoji1|emoji2|...)/` where `\uFE0F` is replaced with `\uFE0F?` and `*` is replaced with `\x2A`.
3. If an Emoji Sequence is found:
   - If the buffer is nonempty, emit a Text token, and clear the buffer.
   - Emit an Emoji token with the fully-qualified matching sequence.
   - Remove the matched sequence from the input.
4. Otherwise:
   - Remove the leading codepoint from the input.
   - Determine the character type:
     - If **Valid**, append the codepoint to the buffer.
       - This set can be precomputed from the union of characters in all groups and their NFD decompositions.
     - If **Mapped**, append the corresponding mapped codepoint(s) to the buffer.
     - If **Ignored**, do nothing.
     - Otherwise, the label cannot be normalized.
5. Repeat until all the input is consumed.
6. If the buffer is nonempty, emit a final Text token with its contents.
7. Return the list of emitted tokens.

Examples:
- `"xyz👨🏻" [78 79 7A 1F468 1F3FB] → Text["xyz"] + Emoji["👨🏻"]`
- `"A💩︎︎b" [41 FE0E 1F4A9 FE0E FE0E 62] → Text["a"] + Emoji["💩️"] + Text["b"]`
- `"a™️" [61 2122 FE0F] → Text["atm"]`

##### Validate
Given a list of Emoji and Text tokens, determine if the label is valid and return the Label Type. If any assertion fails, the name cannot be normalized.

1. If only Emoji tokens:
   - Return "Emoji"
2. If a single Text token and every characters is ASCII (00..7F):
   - **5F (_) LOW LINE** can only occur at the start.
     - Must match `/^_*[^_]*$/`
     - Examples: "___" and "__abc" are valid, "abc__" and "_abc_" are invalid.
   - The 3rd and 4th characters must not both be **2D (-) HYPHEN-MINUS**.
     - Must not match `/^..--/`
     - Examples: "ab-c" and "---a"are valid, "xn--" and ---- are invalid.
   - Return "ASCII"
3. The label is free of **Fenced** and **Combining Mark** characters, and not confusable.
4. Concatenate all the tokens together.
5. **5F (_) LOW LINE** can only occur at the start.
6. The first and last characters cannot be **Fenced**.
   - Examples: "a's" and "a・a" are valid, "'85" and "joneses'" and "・a・" are invalid.
7. **Fenced** characters cannot be contiguous.
   - Examples: "a・a's" is valid, "6'0''" and "a・・a" are invalid.
8. The first character of every Text token must not be a **Combining Mark**.
9. Concatenate the Text tokens together.
10. Find the first **Group** that contain every text character:
    - If no group is found, the label cannot be normalized.
    - If the group is not **CM Whitelisted**:
      - Apply **NFD** to the concatenated text characters.
      - For every contiguous sequence of **NSM** characters:
        - Each character must be unique.
          - Example: "x̀̀" [78 300 300] has (2) grave accents.
        - The number of **NSM** characters cannot exceed **Maximum NSM** (4).
          - Example: "إؐؑؒؓؔ"‎ [625 610 611 612 613 614] has (6) NSM.
11. **Wholes** — check if text characters form a confusable.
12. The label is valid.
13. Return the name of the group as the Label Type.

Examples:
- `Emoji["💩️"] + Emoji["💩️"] → "Emoji"`
- `Text["abc$123"] → "ASCII"`
- `Emoji["🚀️"] + Text["à"] → "Latin"`

##### Wholes
A label is **whole-script confusable** if a similarly-looking valid label can be constructed using one alternative character from a different group. The complete list of **Whole Confusables** can be found in `spec.json`. Each Whole Confusable has a set of non-confusing characters ("valid") and a set of confusing characters ("confused") where each character may be the member of one or more groups.

Example: Whole Confusable for "g"

| Type | Code | Form | Character | Latn | Hani | Japn | Kore | Armn | Cher | Lisu |
|------|------|------|-----------|------|------|------|------|------|------|------|
| valid | 67 | g | LATIN SMALL LETTER G | A | A | A | A | | | |
| confused | 581 | ց | ARMENIAN SMALL LETTER CO | | | | | B | | |
| confused | 13C0 | Ꮐ | CHEROKEE LETTER NAH | | | | | | C | |
| confused | 13F3 | Ᏻ | CHEROKEE LETTER YU | | | | | | C | |
| confused | A4D6 | ꓖ | LISU LETTER GA | | | | | | | D |

1. Allocate an empty character buffer.
2. Start with the set of ALL groups.
3. For each unique character in the label:
   - If the character is **Confused** (a member of a Whole Confusable):
     - Retain groups with Whole Confusable characters excluding the **Confusable Extent** of the matching Confused character.
     - If no groups remain, the label is not confusable.
     - The **Confusable Extent** is the fully-connected graph formed from different groups with the same confusable and different confusables of the same group.
     - The mapping from Confused to Confusable Extent can be precomputed.
     - In the table above, Whole Confusable for "g", the rectangle formed by each capital letter is a Confusable Extent:
       - A is [g] ⊗ [Latin, Han, Japanese, Korean]
       - B is [ց] ⊗ [Armn]
       - C is [Ꮐ, Ᏻ] ⊗ [Cher]
       - D is [ꓖ] ⊗ [Lisu]
     - A Confusable Extent can span multiple characters and multiple groups. Consider the (incomplete) Whole Confusable for "o":
       - 6F (o) LATIN SMALL LETTER O → Latin, Han, Japanese, and Korean
       - 3007 (〇) IDEOGRAPHIC NUMBER ZERO → Han, Japanese, Korean, and Bopomofo
       - Confusable Extent is [o, 〇] ⊗ [Latin, Han, Japanese, Korean, Bopomofo]
   - If the character is **Unique**, the label is not confusable.
     - This set can be precomputed from characters that appear in exactly one group and are not Confused.
   - Otherwise:
     - Append the character to the buffer.
4. If any **Confused** characters were found:
   - If there are no buffered characters, the label is confusable.
   - If any of the remaining groups contain all of the buffered characters, the label is confusable.
   - Example: "0х" [30 445]
     - 30 (0) DIGIT ZERO
       - Not Confused or Unique, add to buffer.
     - 445 (х) CYRILLIC SMALL LETTER HA
       - Confusable Extent is [х, 4B3 (ҳ) CYRILLIC SMALL LETTER HA WITH DESCENDER] ⊗ [Cyrillic]
       - Whole Confusable excluding the extent is [78 (x) LATIN SMALL LETTER X, ...] → [Latin, ...]
       - Remaining groups: ALL ∩ [Latin, ...] → [Latin, ...]
       - There was (1) buffered character:
         - Latin also contains 30 → "0x" [30 78]
         - The label is confusable.
5. The label is not confusable.

A label composed of confusable characters isn't necessarily confusable.

Example: "тӕ" [442 4D5]
- 442 (т) CYRILLIC SMALL LETTER TE
  - Confusable Extent is [т] ⊗ [Cyrillic]
  - Whole Confusable excluding the extent is [3C4 (τ) GREEK SMALL LETTER TAU] → [Greek]
  - Remaining groups: ALL ∩ [Greek] → [Greek]
- 4D5 (ӕ) CYRILLIC SMALL LIGATURE A IE
  - Confusable Extent is [ӕ] ⊗ [Greek]
  - Whole Confusable excluding the extent is [E6 (æ) LATIN SMALL LETTER AE] → [Latin]
  - Remaining groups: [Greek] ∩ [Latin] → ∅
- No groups remain so the label is not confusable.

##### Split
Partition a name into labels, separated by **2D (.) FULL STOP**, and return the resulting array.
- Example: "abc.123.eth" → ["abc", "123", "eth"]
- The empty string is 0-labels: "" → []

##### Join
Assemble an array of labels into a name, inserting **2D (.) FULL STOP** between each label, and return the resulting string.
- Example: ["abc", "123", "eth"] → "abc.123.eth"

#### Description of spec.json
- **Groups** ("groups") — groups of characters that can constitute a label
  - "name" — ASCII name of the group (or abbreviation if Restricted)
    - Examples: Latin, Japanese, Egyp
  - **Restricted** ("restricted") — true if Excluded or Limited-Use script
    - Examples: Latin → false, Egyp → true
  - "primary" — subset of characters that define the group
    - Examples: "a" → Latin, "あ" → Japanese, "𓀀" → Egyp
  - "secondary" — subset of characters included with the group
    - Example: "0" → Common but mixable with Latin
- **CM Whitelist(ed)** ("cm") — (optional) set of allowed compound sequences in NFC
  - Each compound sequence is a character followed by one or more **Combining Marks**.
  - Example: à̀̀ → E0 300 300
  - Currently, every group that is CM Whitelist has zero compound sequences.
  - **CM Whitelisted** is effectively true if [] otherwise false
- **Ignored** ("ignored") — characters that are ignored during normalization
  - Example: 34F (�) COMBINING GRAPHEME JOINER
- **Mapped** ("mapped") — characters that are mapped to a sequence of valid characters
  - Example: 41 (A) LATIN CAPITAL LETTER A → [61 (a) LATIN SMALL LETTER A]
  - Example: 2165 (Ⅵ) ROMAN NUMERAL SIX → [76 (v) LATIN SMALL LETTER V, 69 (i) LATIN SMALL LETTER I]
- **Whole Confusable** ("wholes") — groups of characters that look similar
  - "valid" — subset of confusable characters that are allowed
    - Example: 34 (4) DIGIT FOUR
  - **Confused** ("confused") — subset of confusable characters that confuse
    - Example: 13CE (Ꮞ) CHEROKEE LETTER SE
- **Fenced** ("fenced") — characters that cannot be first, last, or contiguous
  - Example: 2044 (⁄) FRACTION SLASH
- **Emoji Sequence(s)** ("emoji") — valid emoji sequences
  - Example: 👨‍💻 [1F468 200D 1F4BB] man technologist
- **Combining Marks / CM** ("cm") — characters that are Combining Marks
- **Non-spacing Marks / NSM** ("nsm") — valid subset of CM with general category ("Mn" or "Me")
- **Maximum NSM** ("nsm_max") — maximum sequence length of unique NSM
- **Should Escape** ("escape") — characters that shouldn't be printed
- **NFC Check** ("nfc_check") — valid subset of characters that may require NFC

#### Description of nf.json
- "decomp" — mapping from a composed character to a sequence of (partially)-decomposed characters
  - UnicodeData.txt where Decomposition_Mapping exists and does not have a formatting tag
- "exclusions" — set of characters for which the "decomp" mapping is not applied when forming a composition
  - CompositionExclusions.txt
- "ranks" — sets of characters with increasing Canonical_Combining_Class
  - UnicodeData.txt grouped by Canonical_Combining_Class
  - Class 0 is not included
- "qc" — set of characters with property NFC_QC of value N or M
  - DerivedNormalizationProps.txt
  - **NFC Check** (from spec.json) is a subset of this set

#### Derivation
**IDNA 2003**
- UseSTD3ASCIIRules is true
- VerifyDnsLength is false
- Transitional_Processing is false
- The following deviations are valid:
  - DF (ß) LATIN SMALL LETTER SHARP S
  - 3C2 (ς) GREEK SMALL LETTER FINAL SIGMA
- CheckHyphens is false (WHATWG URL Spec § 3.3)
- CheckBidi is false
- **ContextJ:**
  - 200C (�) ZERO WIDTH NON-JOINER (ZWNJ) is disallowed everywhere.
  - 200D (�) ZERO WIDTH JOINER (ZWJ) is only allowed in emoji sequences.
- **ContextO:**
  - B7 (·) MIDDLE DOT is disallowed.
  - 375 (͵) GREEK LOWER NUMERAL SIGN is disallowed.
  - 5F3 (׳) HEBREW PUNCTUATION GERESH and 5F4 (״) HEBREW PUNCTUATION GERSHAYIM are Greek.
  - 30FB (・) KATAKANA MIDDLE DOT is Fenced and Han, Japanese, Korean, and Bopomofo.
- Some **Extended Arabic Numerals** are mapped:
  - 6F0 (۰) → 660 (٠) ARABIC-INDIC DIGIT ZERO
  - 6F1 (۱) → 661 (١) ARABIC-INDIC DIGIT ONE
  - 6F2 (۲) → 662 (٢) ARABIC-INDIC DIGIT TWO
  - 6F3 (۳) → 663 (٣) ARABIC-INDIC DIGIT THREE
  - 6F7 (۷) → 667 (٧) ARABIC-INDIC DIGIT SEVEN
  - 6F8 (۸) → 668 (٨) ARABIC-INDIC DIGIT EIGHT
  - 6F9 (۹) → 669 (٩) ARABIC-INDIC DIGIT NINE
- Punycode is not decoded.
- The following **ASCII characters** are valid:
  - 24 ($) DOLLAR SIGN
  - 5F (_) LOW LINE with restrictions
- Only label separator is **2E (.) FULL STOP**
  - No character maps to this character.
  - This simplifies name detection in unstructured text.
  - The following alternatives are disallowed:
    - 3002 (。) IDEOGRAPHIC FULL STOP
    - FF0E (．) FULLWIDTH FULL STOP
    - FF61 (｡) HALFWIDTH IDEOGRAPHIC FULL STOP
- Many characters are disallowed for various reasons:
  - Nearly all punctuation are disallowed.
    - Example: 589 (։) ARMENIAN FULL STOP
  - All parentheses and brackets are disallowed.
    - Example: 2997 (⦗) LEFT BLACK TORTOISE SHELL BRACKET
  - Nearly all vocalization annotations are disallowed.
    - Example: 294 (ʔ) LATIN LETTER GLOTTAL STOP
  - Obsolete, deprecated, and ancient characters are disallowed.
    - Example: 463 (ѣ) CYRILLIC SMALL LETTER YAT
  - Combining, modifying, reversed, flipped, turned, and partial variations are disallowed.
    - Example: 218A (↊) TURNED DIGIT TWO
  - When multiple weights of the same character exist, the variant closest to "heavy" is selected and the rest disallowed.
    - Example: 🞡🞢🞣🞤✚🞥🞦🞧 → 271A (✚) HEAVY GREEK CROSS
    - This occasionally selects an emoji.
      - Example: ✔️ or 2714 (✔︎) HEAVY CHECK MARK is selected instead of 2713 (✓) CHECK MARK
  - Many visually confusable characters are disallowed.
    - Example: 131 (ı) LATIN SMALL LETTER DOTLESS I
  - Many ligatures, n-graphs, and n-grams are disallowed.
    - Example: A74F (ꝏ) LATIN SMALL LETTER OO
  - Many esoteric characters are disallowed.
    - Example: 2376 (⍶) APL FUNCTIONAL SYMBOL ALPHA UNDERBAR
- Many **hyphen-like characters** are mapped to **2D (-) HYPHEN-MINUS**:
  - 2010 (‐) HYPHEN
  - 2011 (‑) NON-BREAKING HYPHEN
  - 2012 (‒) FIGURE DASH
  - 2013 (–) EN DASH
  - 2014 (—) EM DASH
  - 2015 (―) HORIZONTAL BAR
  - 2043 (⁃) HYPHEN BULLET
  - 2212 (−) MINUS SIGN
  - 23AF (⎯) HORIZONTAL LINE EXTENSION
  - 23E4 (⏤) STRAIGHTNESS
  - FE58 (﹘) SMALL EM DASH
  - 2E3A (⸺) TWO-EM DASH → "--"
  - 2E3B (⸻) THREE-EM DASH → "---"
- Characters are assigned to **Groups** according to Unicode Script_Extensions.
  - Groups may contain multiple scripts:
    - Only Latin, Greek, Cyrillic, Han, Japanese, and Korean have access to Common characters.
    - Latin, Greek, Cyrillic, Han, Japanese, Korean, and Bopomofo only permit specific **Combining Mark** sequences.
    - Han, Japanese, and Korean have access to a-z.
    - Restricted groups are always single-script.
  - **Unicode augmented script sets**
  - Scripts Braille, Linear A, Linear B, and Signwriting are disallowed.
- **27 (') APOSTROPHE** is mapped to **2019 (') RIGHT SINGLE QUOTATION MARK** for convenience.
- **Ethereum symbol** (39E (Ξ) GREEK CAPITAL LETTER XI) is case-folded and Common.
- **Emoji:**
  - All emoji are fully-qualified.
  - Digits (0-9) are not emoji.
  - Emoji mapped to non-emoji by IDNA cannot be used as emoji.
  - Emoji disallowed by IDNA with default text-presentation are disabled:
    - 203C (‼️) double exclamation mark
    - 2049 (⁉️) exclamation question mark
  - Remaining emoji characters are marked as disallowed (for text processing).
  - All RGI_Emoji_ZWJ_Sequence are enabled.
  - All Emoji_Keycap_Sequence are enabled.
  - All RGI_Emoji_Tag_Sequence are enabled.
  - All RGI_Emoji_Modifier_Sequence are enabled.
  - All RGI_Emoji_Flag_Sequence are enabled.
  - Basic_Emoji of the form [X FE0F] are enabled.
  - Emoji with default emoji-presentation are enabled as [X FE0F].
  - Remaining single-character emoji are enabled as [X FE0F] (explicit emoji-presentation).
  - All singular Skin-color Modifiers are disabled.
  - All singular Regional Indicators are disabled.
  - Blacklisted emoji are disabled.
  - Whitelisted emoji are enabled.
- **Confusables:**
  - Nearly all Unicode Confusables
  - Emoji are not confusable.
  - ASCII confusables are case-folded.
    - Example: 61 (a) LATIN SMALL LETTER A confuses with 13AA (Ꭺ) CHEROKEE LETTER GO

#### Backwards Compatibility
- 99% of names are still valid.
- Preserves as much Unicode IDNA and WHATWG URL compatibility as possible.
- Only valid emoji sequences are permitted.

#### Security Considerations
- Unicode presentation may vary between applications and devices.
- Unicode text is ultimately subject to font-styling and display context.
- Unsupported characters (�) may appear unremarkable.
- Normalized single-character emoji sequences do not retain their explicit emoji-presentation and may display with text or emoji presentation styling.
  - ❤︎ — text-presentation and default-color
  - ❤︎ — text-presentation and green-color
  - ❤️ — emoji-presentation and green-color
- Unsupported emoji sequences with ZWJ may appear indistinguishable from those without ZWJ.
  - 💩💩 [1F4A9 1F4A9]
  - 💩‍💩 [1F4A9 200D 1F4A9] → error: Disallowed character
- Names composed of labels with varying bidi properties may appear differently depending on context.
  - Normalization does not enforce single-directional names.
  - Names may be composed of labels of different directions but normalized labels are never bidirectional.
  - [LTR].[RTL] bahrain.مصر
  - [LTR+RTL] bahrainمصر → error: Illegal mixture: Latin + Arabic
- Not all normalized names are visually unambiguous.
  - This ENSIP only addresses single-character confusables.
  - There exist confusable multi-character sequences:
    - "ஶ்ரீ" [BB6 BCD BB0 BC0]
    - "ஸ்ரீ" [BB8 BCD BB0 BC0]
  - There exist confusable emoji sequences:
    - 🚴 [1F6B4] and 🚴🏻 [1F6B4 1F3FB]
    - 🇺🇸 [1F1FA 1F1F8] and 🇺🇲 [1F1FA 1F1F2]
    - ♥ [2665] BLACK HEART SUIT and ❤ [2764] HEAVY BLACK HEART

#### Copyright
Copyright and related rights waived via CC0.

#### Appendix: Reference Specifications
- EIP-137: Ethereum Domain Name Service
- ENSIP-1: ENS
- UAX-15: Normalization Forms
- UAX-24: Script Property
- UAX-29: Text Segmentation
- UAX-31: Identifier and Pattern Syntax
- UTS-39: Security Mechanisms
- UAX-44: Character Database
- UTS-46: IDNA Compatibility Processing
- UTS-51: Emoji
- RFC-3492: Punycode
- RFC-5891: IDNA: Protocol
- RFC-5892: The Unicode Code Points and IDNA
- Unicode CLDR
- WHATWG URL: IDNA

#### Appendix: Additional Resources
- Supported Groups
- Supported Emoji
- Additional Disallowed Characters
- Ignored Characters
- Should Escape Characters
- Combining Marks
- Non-spacing Marks
- Fenced Characters
- NFC Quick Check

#### Appendix: Validation Tests
A list of validation tests are provided with the following interpretation:
- **Already Normalized**: `{name: "a"}` → normalize("a") is "a"
- **Need Normalization**: `{name: "A", norm: "a"}` → normalize("A") is "a"
- **Expect Error**: `{name: "@", error: true}` → normalize("@") throws

#### Annex: Beautification
Follow algorithm, except:
- Do not strip FE0F from Emoji tokens.
- Replace 3BE (ξ) GREEK SMALL LETTER XI with 39E (Ξ) GREEK CAPITAL LETTER XI if the label isn't Greek.
- Example: normalize("‐Ξ1️⃣") [2010 39E 31 FE0F 20E3] is "-ξ1⃣" [2D 3BE 31 20E3]
- Example: beautify("-ξ1⃣") [2D 3BE 31 20E3]" is "-Ξ1️⃣" [2D 39E 31 FE0F 20E3]

**⚠️ CRITICAL: This specification is the ultimate authority. Any implementation that deviates from ENSIP-15 is incorrect by definition.**

## 🚨 MANDATORY IMPLEMENTATION RULES

### 1. **ALWAYS Reference Implementations First**
- **NEVER** implement based on assumptions or general understanding
- **ALWAYS** read the reference implementation code BEFORE writing any code
- **ALWAYS** check multiple reference implementations to understand the pattern
- If reference implementations differ, investigate WHY and document the reason

### 2. **Production Parity is NON-NEGOTIABLE**
- A 90% solution is WORSE than no solution
- The implementation MUST match reference implementations 100%
- Every edge case handled by references MUST be handled identically
- No shortcuts, no "good enough", no "we'll fix it later"

### 3. **Data Must Match Exactly**
- Character mappings MUST be identical to reference data
- DO NOT create simplified mappings - use the exact data from references
- If ℌ maps to 'h' in the reference, it MUST map to 'h' (not 'H') in our implementation
- Always check the actual data files (spec.json, include-ens.js) not just the code

### 4. **Test Against Reference Test Cases**
- Every reference implementation has test cases - USE THEM
- Our implementation MUST pass ALL reference test cases
- If a test fails, the implementation is WRONG (not the test)
- Add test cases from ALL reference implementations, not just one

### 5. **No Assumptions About Unicode**
- DO NOT assume how Unicode normalization works
- DO NOT assume how character mappings should work
- Look at EXACTLY how the references handle it
- Copy their approach precisely

## 📋 Implementation Checklist

Before implementing ANY feature:

- [ ] Read the JavaScript reference implementation
- [ ] Read the Rust reference implementation  
- [ ] Read at least one other reference (Go, C#, or Java)
- [ ] Understand the data format they use
- [ ] Copy their test cases
- [ ] Verify our approach matches theirs EXACTLY

## 🔍 Common Pitfalls to Avoid

1. **Incomplete Mappings**: References map ℌ→h directly, not ℌ→H→h
2. **Missing Edge Cases**: Every character the references handle must be handled
3. **Wrong Assumptions**: Don't assume ASCII folding is separate from Unicode mappings

## ⚠️ **CRITICAL MEMORY MANAGEMENT RULES**

### **ArrayList + toOwnedSlice() Pattern - EXTREMELY DANGEROUS**

**NEVER do this:**
```zig
var list = std.ArrayList(T).init(allocator);
defer list.deinit(); // ❌ BUG: Creates double-free!
// ... add items to list ...
return list.toOwnedSlice(); // Transfers ownership, then defer tries to free again
```

**CORRECT patterns:**

**Option 1 - No defer, handle errors manually:**
```zig
var list = std.ArrayList(T).init(allocator);
errdefer list.deinit(); // Only free on error
// ... add items to list ...
return list.toOwnedSlice(); // Transfer ownership on success
```

**Option 2 - Use defer with careful ownership:**
```zig
var list = std.ArrayList(T).init(allocator);
defer list.deinit();
// ... add items to list ...
const result = try list.toOwnedSlice();
list = std.ArrayList(T).init(allocator); // Reset to empty so deinit is safe
return result;
```

### **Why This Matters:**
- `toOwnedSlice()` transfers ownership of internal buffer to caller
- `defer deinit()` then tries to free the SAME buffer
- Results in double-free bugs, bus errors, memory corruption
- Can cause mysterious crashes, segfaults, data corruption

### **Memory Management Checklist:**
- [ ] Every `allocator.alloc()` has corresponding `allocator.free()`
- [ ] Every `allocator.dupe()` has corresponding `allocator.free()`
- [ ] Never call `deinit()` after `toOwnedSlice()` on same ArrayList
- [ ] Use `errdefer` for cleanup on error paths
- [ ] Test with allocation failure modes (if possible)
4. **Incomplete Testing**: Test with actual ENS names from production, not just simple cases

## 🛠️ Debugging Process

When something doesn't work:

1. **First**: Check what the JavaScript implementation does
2. **Second**: Verify against the Rust implementation
3. **Third**: Look at the actual data files they use
4. **Fourth**: Run their test cases
5. **Never**: Assume or guess how it should work

## 📊 Data Sources Priority

1. **Primary**: The actual spec.json or include-ens.js data files
2. **Secondary**: The test cases in reference implementations
3. **Tertiary**: The implementation code itself
4. **Never**: Our own interpretation or simplification

## ⚠️ Red Flags

These indicate you're doing it wrong:

- "This should work the same way"
- "We can simplify this"
- "We'll handle this case later"
- "90% compatibility is fine for now"
- Creating our own test data instead of using reference data
- Implementing without reading the references first

## 🎯 Success Criteria

An implementation is ONLY complete when:

1. It passes ALL test cases from ALL reference implementations
2. It uses the EXACT same character mapping data
3. It handles EVERY edge case the references handle
4. It produces IDENTICAL output for all inputs
5. There are NO "known limitations" compared to references

## 💡 Key Insight from Character Mappings Failure

We failed because:
- We assumed ℌ→H→h (two-step) when references do ℌ→h (one-step)
- We created "basic mappings" instead of using the actual data
- We didn't check what the actual mapping data contained
- We marked it "complete" with known limitations

This must NEVER happen again. Always use the reference data and implementation exactly.

## 🔧 Specific Technical Rules

### Character Mappings
- Use the EXACT mappings from spec.json or include-ens.js
- Do NOT create simplified versions
- Do NOT assume multi-step transformations
- Mathematical symbols map DIRECTLY to lowercase (ℌ→h, not ℌ→H)

### Tokenization
- Token types must match references exactly
- Token ordering must match references exactly  
- Edge cases (empty strings, special chars) must match references exactly

### Validation
- Validation rules must match references exactly
- Error types must match references exactly
- Label types must match references exactly

### Testing
- MUST include test cases from JavaScript implementation
- MUST include test cases from Rust implementation
- MUST include test cases from at least one other implementation
- MUST test with real ENS names from mainnet

Remember: The goal is 100% compatibility with existing implementations. Nothing less is acceptable.

## 🚫 CRITICAL: Data Format Rules

### ZON vs JSON
- **WE USE ZON FILES, NOT JSON**
- The project has already been converted from JSON to ZON
- **NEVER** suggest converting ZON back to JSON
- **NEVER** try to parse ZON as JSON at runtime
- **NEVER** create JSON-to-ZON or ZON-to-JSON converters

### Why This Matters
- We specifically converted from JSON to ZON for good reasons
- Going back to JSON is moving backwards
- Converting between formats at runtime is inefficient and error-prone
- If ZON import isn't working, we need to fix the ZON import, not abandon it

### Correct Approaches for ZON
1. Use `@import` with proper type definitions at compile time
2. Define proper Zig types that match the ZON structure
3. Handle heterogeneous arrays with union types or other Zig constructs
4. Use comptime code generation if needed

### What NOT to Do
- ❌ Convert ZON to JSON at runtime
- ❌ Revert to JSON files
- ❌ Parse ZON as text and transform it
- ❌ Suggest "easier" solutions that involve JSON

The project uses ZON. Period. Make it work with ZON.

## 🔧 Zig Build System Rules

### Adding Tests
When creating new test files, you MUST add them to build.zig:
1. Tests need to import the main module using `@import("ens_normalize")`
2. In build.zig, each test must be added with the module dependency:
   ```zig
   const my_test = b.addTest(.{
       .root_source_file = .{ .path = "tests/my_test.zig" },
       .target = target,
       .optimize = optimize,
   });
   my_test.root_module.addImport("ens_normalize", ens_normalize_module);
   ```
3. Never try to run tests directly with `zig test` - always use `zig build test`

### Module System
- The main module is defined in build.zig as `ens_normalize_module`
- All tests must import it as `@import("ens_normalize")`
- Individual source files cannot be tested in isolation if they depend on the module