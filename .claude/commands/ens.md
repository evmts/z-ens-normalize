# Ens context

## Goals

Coding agent implementing ens spec
Goal is to implement ens library 100% to spec in zig.

The following context is from official ens spec. I will share context then provide futher instructions at the end

---

description: Documentation of the basic ENS protocol (formerly EIP-137)
contributors:

- nick.eth
  ensip:
  created: '2016-04-04'
  status: final
  ignoredRules: ["missing:copyright"]

---

# ENSIP-1: ENS

## Abstract

This ENSIP describes the details of the Ethereum Name Service, a proposed protocol and ABI definition that provides flexible resolution of short, human-readable names to service and resource identifiers. This permits users and developers to refer to human-readable and easy to remember names, and permits those names to be updated as necessary when the underlying resource (contract, content-addressed data, etc) changes.

The goal of domain names is to provide stable, human-readable identifiers that can be used to specify network resources. In this way, users can enter a memorable string, such as 'vitalik.wallet' or 'www.mysite.swarm', and be directed to the appropriate resource. The mapping between names and resources may change over time, so a user may change wallets, a website may change hosts, or a swarm document may be updated to a new version, without the domain name changing. Further, a domain need not specify a single resource; different record types allow the same domain to reference different resources. For instance, a browser may resolve 'mysite.swarm' to the IP address of its server by fetching its A (address) record, while a mail client may resolve the same address to a mail server by fetching its MX (mail exchanger) record.

## Motivation

Existing [specifications](https://github.com/ethereum/wiki/wiki/Registrar-ABI) and [implementations](https://ethereum.gitbooks.io/frontier-guide/content/registrar_services.html) for name resolution in Ethereum provide basic functionality, but suffer several shortcomings that will significantly limit their long-term usefulness:

- A single global namespace for all names with a single 'centralised' resolver.
- Limited or no support for delegation and sub-names/sub-domains.
- Only one record type, and no support for associating multiple copies of a record with a domain.
- Due to a single global implementation, no support for multiple different name allocation systems.
- Conflation of responsibilities: Name resolution, registration, and whois information.

Use-cases that these features would permit include:

- Support for subnames/sub-domains - eg, live.mysite.tld and forum.mysite.tld.
- Multiple services under a single name, such as a DApp hosted in Swarm, a Whisper address, and a mail server.
- Support for DNS record types, allowing blockchain hosting of 'legacy' names. This would permit an Ethereum client such as Mist to resolve the address of a traditional website, or the mail server for an email address, from a blockchain name.
- DNS gateways, exposing ENS domains via the Domain Name Service, providing easier means for legacy clients to resolve and connect to blockchain services.

The first two use-cases, in particular, can be observed everywhere on the present-day internet under DNS, and we believe them to be fundamental features of a name service that will continue to be useful as the Ethereum platform develops and matures.

The normative parts of this document does not specify an implementation of the proposed system; its purpose is to document a protocol that different resolver implementations can adhere to in order to facilitate consistent name resolution. An appendix provides sample implementations of resolver contracts and libraries, which should be treated as illustrative examples only.

Likewise, this document does not attempt to specify how domains should be registered or updated, or how systems can find the owner responsible for a given domain. Registration is the responsibility of registrars, and is a governance matter that will necessarily vary between top-level domains.

Updating of domain records can also be handled separately from resolution. Some systems, such as swarm, may require a well defined interface for updating domains, in which event we anticipate the development of a standard for this.

## Specification

### Overview

The ENS system comprises three main parts:

- The ENS registry
- Resolvers
- Registrars

The registry is a single contract that provides a mapping from any registered name to the resolver responsible for it, and permits the owner of a name to set the resolver address, and to create subdomains, potentially with different owners to the parent domain.

Resolvers are responsible for performing resource lookups for a name - for instance, returning a contract address, a content hash, or IP address(es) as appropriate. The resolver specification, defined here and extended in other ENSIPs, defines what methods a resolver may implement to support resolving different types of records.

Registrars are responsible for allocating domain names to users of the system, and are the only entities capable of updating the ENS; the owner of a node in the ENS registry is its registrar. Registrars may be contracts or externally owned accounts, though it is expected that the root and top-level registrars, at a minimum, will be implemented as contracts.

Resolving a name in ENS is a two-step process. First, the ENS registry is called with the name to resolve, after hashing it using the procedure described below. If the record exists, the registry returns the address of its resolver. Then, the resolver is called, using the method appropriate to the resource being requested. The resolver then returns the desired result.

For example, suppose you wish to find the address of the token contract associated with 'beercoin.eth'. First, get the resolver:

```javascript
var node = namehash("beercoin.eth");
var resolver = ens.resolver(node);
```

Then, ask the resolver for the address for the contract:

```javascript
var address = resolver.addr(node);
```

Because the `namehash` procedure depends only on the name itself, this can be precomputed and inserted into a contract, removing the need for string manipulation, and permitting O(1) lookup of ENS records regardless of the number of components in the raw name.

### Name Syntax

ENS names must conform to the following syntax:

```go
<domain> ::= <label> | <domain> "." <label>
<label> ::= any valid string label per [UTS46](https://unicode.org/reports/tr46/)
```

In short, names consist of a series of dot-separated labels. Each label must be a valid normalised label as described in [UTS46](https://unicode.org/reports/tr46/) with the options `transitional=false` and `useSTD3AsciiRules=true`. For Javascript implementations, a [library](https://www.npmjs.com/package/idna-uts46) is available that normalises and checks names.

Note that while upper and lower case letters are allowed in names, the UTS46 normalisation process case-folds labels before hashing them, so two names with different case but identical spelling will produce the same namehash.

Labels and domains may be of any length, but for compatibility with legacy DNS, it is recommended that labels be restricted to no more than 64 characters each, and complete ENS names to no more than 255 characters. For the same reason, it is recommended that labels do not start or end with hyphens, or start with digits.

### namehash algorithm

Before being used in ENS, names are hashed using the 'namehash' algorithm. This algorithm recursively hashes components of the name, producing a unique, fixed-length string for any valid input domain. The output of namehash is referred to as a 'node'.

Pseudocode for the namehash algorithm is as follows:

```go
def namehash(name):
  if name == '':
    return '\0' * 32
  else:
    label, _, remainder = name.partition('.')
    return sha3(namehash(remainder) + sha3(label))
```

Informally, the name is split into labels, each label is hashed. Then, starting with the last component, the previous output is concatenated with the label hash and hashed again. The first component is concatenated with 32 '0' bytes. Thus, 'mysite.swarm' is processed as follows:

```javascript
node = "\0" * 32;
node = sha3(node + sha3("swarm"));
node = sha3(node + sha3("mysite"));
```

Implementations should conform to the following test vectors for namehash:

```javascript
namehash('') = 0x0000000000000000000000000000000000000000000000000000000000000000
namehash('eth') = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae
namehash('foo.eth') = 0xde9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f
```

### Registry specification

The ENS registry contract exposes the following functions:

```solidity
function owner(bytes32 node) constant returns (address);
```

Returns the owner (registrar) of the specified node.

```solidity
function resolver(bytes32 node) constant returns (address);
```

Returns the resolver for the specified node.

```solidity
function ttl(bytes32 node) constant returns (uint64);
```

Returns the time-to-live (TTL) of the node; that is, the maximum duration for which a node's information may be cached.

```solidity
function setOwner(bytes32 node, address owner);
```

Transfers ownership of a node to another registrar. This function may only be called by the current owner of `node`. A successful call to this function logs the event `Transfer(bytes32 indexed, address)`.

```solidity
function setSubnodeOwner(bytes32 node, bytes32 label, address owner);
```

Creates a new node, `sha3(node, label)` and sets its owner to `owner`, or updates the node with a new owner if it already exists. This function may only be called by the current owner of `node`. A successful call to this function logs the event `NewOwner(bytes32 indexed, bytes32 indexed, address)`.

```solidity
function setResolver(bytes32 node, address resolver);
```

Sets the resolver address for `node`. This function may only be called by the owner of `node`. A successful call to this function logs the event `NewResolver(bytes32 indexed, address)`.

```solidity
function setTTL(bytes32 node, uint64 ttl);
```

Sets the TTL for a node. A node's TTL applies to the 'owner' and 'resolver' records in the registry, as well as to any information returned by the associated resolver.

### Resolver specification

Resolvers may implement any subset of the record types specified here. Where a record types specification requires a resolver to provide multiple functions, the resolver MUST implement either all or none of them. Resolvers MUST specify a fallback function that throws.

Resolvers have one mandatory function:

```solidity
function supportsInterface(bytes4 interfaceID) constant returns (bool)
```

The `supportsInterface` function is documented in ENSIP-165, and returns true if the resolver implements the interface specified by the provided 4 byte identifier. An interface identifier consists of the XOR of the function signature hashes of the functions provided by that interface; in the degenerate case of single-function interfaces, it is simply equal to the signature hash of that function. If a resolver returns `true` for `supportsInterface()`, it must implement the functions specified in that interface.

`supportsInterface` must always return true for `0x01ffc9a7`, which is the interface ID of `supportsInterface` itself.

Currently standardised resolver interfaces are specified in the table below.

The following interfaces are defined:

| Interface name        | Interface hash | Specification                                       |
| --------------------- | -------------- | --------------------------------------------------- |
| `addr`                | 0x3b3b57de     | Contract address                                    |
| `name`                | 0x691f3431     | [ENSIP-3](ensip-3-reverse-resolution.md)            |
| `ABI`                 | 0x2203ab56     | [ENSIP-4](ensip-4-support-for-contract-abis.md)     |
| text                  | 0x59d1d43c     | [ENSIP-5](ensip-5-text-records.md)                  |
| contenthash           | 0xbc1c58d1     | [ENSIP-7](ensip-7-contenthash-field.md)             |
| interfaceImplementer  | 0xb8f2bbb4     | [ENSIP-8](ensip-8-interface-discovery.md)           |
| addr(bytes32,uint256) | 0xf1cb7e06     | [ENSIP-9](ensip-9-multichain-address-resolution.md) |

ENSIPs may define new interfaces to be added to this registry.

#### Contract Address Interface <a href="#addr" id="addr"></a>

Resolvers wishing to support contract address resources must provide the following function:

```solidity
function addr(bytes32 node) constant returns (address);
```

If the resolver supports `addr` lookups but the requested node does not have an addr record, the resolver MUST return the zero address.

Clients resolving the `addr` record MUST check for a zero return value, and treat this in the same manner as a name that does not have a resolver specified - that is, refuse to send funds to or interact with the address. Failure to do this can result in users accidentally sending funds to the 0 address.

Changes to an address MUST trigger the following event:

```solidity
event AddrChanged(bytes32 indexed node, address a);
```

## Appendix A: Registry Implementation

```solidity
contract ENS {
    struct Record {
        address owner;
        address resolver;
        uint64 ttl;
    }

    mapping(bytes32=>Record) records;

    event NewOwner(bytes32 indexed node, bytes32 indexed label, address owner);
    event Transfer(bytes32 indexed node, address owner);
    event NewResolver(bytes32 indexed node, address resolver);

    modifier only_owner(bytes32 node) {
        if(records[node].owner != msg.sender) throw;
        _
    }

    function ENS(address owner) {
        records[0].owner = owner;
    }

    function owner(bytes32 node) constant returns (address) {
        return records[node].owner;
    }

    function resolver(bytes32 node) constant returns (address) {
        return records[node].resolver;
    }

    function ttl(bytes32 node) constant returns (uint64) {
        return records[node].ttl;
    }

    function setOwner(bytes32 node, address owner) only_owner(node) {
        Transfer(node, owner);
        records[node].owner = owner;
    }

    function setSubnodeOwner(bytes32 node, bytes32 label, address owner) only_owner(node) {
        var subnode = sha3(node, label);
        NewOwner(node, label, owner);
        records[subnode].owner = owner;
    }

    function setResolver(bytes32 node, address resolver) only_owner(node) {
        NewResolver(node, resolver);
        records[node].resolver = resolver;
    }

    function setTTL(bytes32 node, uint64 ttl) only_owner(node) {
        NewTTL(node, ttl);
        records[node].ttl = ttl;
    }
}
```

## Appendix B: Sample Resolver Implementations

#### Built-in resolver

The simplest possible resolver is a contract that acts as its own name resolver by implementing the contract address resource profile:

```solidity
contract DoSomethingUseful {
    // Other code

    function addr(bytes32 node) constant returns (address) {
        return this;
    }

    function supportsInterface(bytes4 interfaceID) constant returns (bool) {
        return interfaceID == 0x3b3b57de || interfaceID == 0x01ffc9a7;
    }

    function() {
        throw;
    }
}
```

Such a contract can be inserted directly into the ENS registry, eliminating the need for a separate resolver contract in simple use-cases. However, the requirement to 'throw' on unknown function calls may interfere with normal operation of some types of contract.

#### Standalone resolver

A basic resolver that implements the contract address profile, and allows only its owner to update records:

```solidity
contract Resolver {
    event AddrChanged(bytes32 indexed node, address a);

    address owner;
    mapping(bytes32=>address) addresses;

    modifier only_owner() {
        if(msg.sender != owner) throw;
        _
    }

    function Resolver() {
        owner = msg.sender;
    }

    function addr(bytes32 node) constant returns(address) {
        return addresses[node];
    }

    function setAddr(bytes32 node, address addr) only_owner {
        addresses[node] = addr;
        AddrChanged(node, addr);
    }

    function supportsInterface(bytes4 interfaceID) constant returns (bool) {
        return interfaceID == 0x3b3b57de || interfaceID == 0x01ffc9a7;
    }

    function() {
        throw;
    }
}
```

After deploying this contract, use it by updating the ENS registry to reference this contract for a name, then calling `setAddr()` with the same node to set the contract address it will resolve to.

#### Public resolver

Similar to the resolver above, this contract only supports the contract address profile, but uses the ENS registry to determine who should be allowed to update entries:

```solidity
contract PublicResolver {
    event AddrChanged(bytes32 indexed node, address a);
    event ContentChanged(bytes32 indexed node, bytes32 hash);

    ENS ens;
    mapping(bytes32=>address) addresses;

    modifier only_owner(bytes32 node) {
        if(ens.owner(node) != msg.sender) throw;
        _
    }

    function PublicResolver(address ensAddr) {
        ens = ENS(ensAddr);
    }

    function addr(bytes32 node) constant returns (address ret) {
        ret = addresses[node];
    }

    function setAddr(bytes32 node, address addr) only_owner(node) {
        addresses[node] = addr;
        AddrChanged(node, addr);
    }

    function supportsInterface(bytes4 interfaceID) constant returns (bool) {
        return interfaceID == 0x3b3b57de || interfaceID == 0x01ffc9a7;
    }

    function() {
        throw;
    }
}
```

## Appendix C: Sample Registrar Implementation

This registrar allows users to register names at no cost if they are the first to request them.

```solidity
contract FIFSRegistrar {
    ENS ens;
    bytes32 rootNode;

    function FIFSRegistrar(address ensAddr, bytes32 node) {
        ens = ENS(ensAddr);
        rootNode = node;
    }

    function register(bytes32 subnode, address owner) {
        var node = sha3(rootNode, subnode);
        var currentOwner = ens.owner(node);
        if(currentOwner != 0 && currentOwner != msg.sender)
            throw;

        ens.setSubnodeOwner(rootNode, subnode, owner);
    }
}
```

---

description: A standard for ENS name normalization.
contributors:

- raffy.eth
  ensip:
  status: final
  created: 2023-04-03
  ignoredRules: ["heading:description-of-", "heading:derivation", "heading:appendix:-reference-specifications", "heading:appendix:-additional-resources", "heading:appendix:-validation-tests", "heading:annex:-beautification"]

---

# ENSIP-15: Name Normalization

## Abstract

This ENSIP standardizes Ethereum Name Service (ENS) name normalization process outlined in [ENSIP-1 § Name Syntax](./1.md#name-syntax).

## Motivation

- Since [ENSIP-1](./1.md) (originally [EIP-137](https://eips.ethereum.org/EIPS/eip-137)) was finalized in 2016, Unicode has [evolved](https://unicode.org/history/publicationdates.html) from version 8.0.0 to 15.0.0 and incorporated many new characters, including complex emoji sequences.
- ENSIP-1 does not state the version of Unicode.
- ENSIP-1 implies but does not state an explicit flavor of IDNA processing.
- [UTS-46](https://unicode.org/reports/tr46/) is insufficient to normalize emoji sequences. Correct emoji processing is only possible with [UTS-51](https://www.unicode.org/reports/tr51/).
- Validation tests are needed to ensure implementation compliance.
- The success of ENS has encouraged spoofing via the following techniques:
  1.  Insertion of zero-width characters.
  1.  Using names which normalize differently between algorithms.
  1.  Using names which appear differently between applications and devices.
  1.  Substitution of confusable (look-alike) characters.
  1.  Mixing incompatible scripts.

## Specification

- Unicode version `16.0.0`
  - Normalization is a living specification and should use the latest stable version of Unicode.
- [`spec.json`](https://github.com/adraffy/ens-normalize.js/blob/main/derive/output/spec.json) contains all [necessary data](#description-of-specjson) for normalization.
- [`nf.json`](https://github.com/adraffy/ens-normalize.js/blob/main/derive/output/nf.json) contains all [necessary data](#description-of-nfjson) for [Unicode Normalization Forms](https://unicode.org/reports/tr15/) NFC and NFD.

### Definitions

- Terms in **bold** throughout this document correspond with [components of `spec.json`](#description-of-specjson).
- A string is a sequence of Unicode codepoints.
  - Example: `"abc"` is `61 62 63`
- An [Unicode emoji](https://www.unicode.org/reports/tr51/) is a [single entity](https://unicode.org/reports/tr29/#Grapheme_Cluster_Boundaries) composed of one or more codepoints:
  - An **Emoji Sequence** is the preferred form of an emoji, resulting from input that [tokenized](#tokenize) into an `Emoji` token.
    - Example: `💩︎︎ [1F4A9]` → `Emoji[1F4A9 FE0F]`
      - `1F4A9 FE0F` is the **Emoji Sequence**.
  - [`spec.json`](#description-of-specjson) contains the complete [list of valid](https://github.com/adraffy/ens-normalize.js/blob/main/tools/ensip/emoji.md) **Emoji Sequences**.
    - [Derivation](#derivation) defines which emoji are normalizable.
    - Not all Unicode emoji are valid.
      - `‼ [203C] double exclamation mark` → _error: Disallowed character_
      - `🈁 [1F201] Japanese “here” button` → `Text["ココ"]`
  - An **Emoji Sequence** may contain characters that are disallowed:
    - `👩‍❤️‍👨 [1F469 200D 2764 FE0F 200D 1F468] couple with heart: woman, man` — contains ZWJ
    - `#️⃣ [23 FE0F 20E3] keycap: #` — contains `23 (#)`
    - `🏴󠁧󠁢󠁥󠁮󠁧󠁿 [1F3F4 E0067 E0062 E0065 E006E E0067 E007F]` — contains `E00XX`
  - An **Emoji Sequence** may contain other emoji:
    - Example: `❤️ [2764 FE0F] red heart` is a substring of `❤️‍🔥 [2764 FE0F 200D 1F525] heart on fire`
  - Single-codepoint emoji may have various [presentation styles](https://www.unicode.org/reports/tr51/#Presentation_Style) on input:
    - Default: `❤ [2764]`
    - Text: `❤︎ [2764 FE0E]`
    - Emoji: `❤️ [2764 FE0F]`
  - However, these all [tokenize](#tokenize) to the same **Emoji Sequence**.
  - All **Emoji Sequence** have explicit emoji-presentation.
  - The convention of ignoring presentation is difficult to change because:
    - Presentation characters (`FE0F` and `FE0E`) are **Ignored**
    - [ENSIP-1](./1.md) did not treat emoji differently from text
    - Registration hashes are immutable
  - [Beautification](#annex-beautification) can be used to restore emoji-presentation in normalized names.

### Algorithm

- Normalization is the process of canonicalizing a name before for [hashing](./1.md#namehash-algorithm).
- It is idempotent: applying normalization multiple times produces the same result.
- For user convenience, leading and trailing whitespace should be trimmed before normalization, as all whitespace codepoints are disallowed. Inner characters should remain unmodified.
- No string transformations (like case-folding) should be applied.

1. [Split](#split) the name into [labels](./1.md#name-syntax).
1. [Normalize](#normalize) each label.
1. [Join](#join) the labels together into a name again.

### Normalize

1. [Tokenize](#tokenize) — transform the label into `Text` and `Emoji` tokens.
   - If there are no tokens, the label cannot be normalized.
1. Apply [NFC](https://unicode.org/reports/tr15/#Norm_Forms) to each `Text` token.
   - Example: `Text["à"]` → `[61 300] → [E0]` → `Text["à"]`
1. Strip `FE0F` from each `Emoji` token.
1. [Validate](#validate) — check if the tokens are valid and obtain the **Label Type**.
   - The **Label Type** and **Restricted** state may be presented to user for additional security.
1. Concatenate the tokens together.
   - Return the normalized label.

Examples:

1. `"_$A" [5F 24 41]` → `"_$a" [5F 24 61]` — _ASCII_
1. `"E︎̃" [45 FE0E 303]` → `"ẽ" [1EBD]` — _Latin_
1. `"𓆏🐸" [1318F 1F438]` → `"𓆏🐸" [1318F 1F438]` — _Restricted: Egyp_
1. `"nı̇ck" [6E 131 307 63 6B]` → _error: Disallowed character_

### Tokenize

Convert a label into a list of `Text` and `Emoji` tokens, each with a payload of codepoints. The complete list of character types and [emoji sequences](#appendix-additional-resources) can be found in [`spec.json`](#description-of-specjson).

1. Allocate an empty codepoint buffer.
1. Find the longest **Emoji Sequence** that matches the remaining input.
   - Example: `👨🏻‍💻 [1F468 1F3FB 200D 1F4BB]`
     - Match (1): `👨️ [1F468] man`
     - Match (2): `👨🏻 [1F468 1F3FB] man: light skin tone`
     - Match (4): `👨🏻‍💻 [1F468 1F3FB 200D 1F4BB] man technologist: light skin tone` — longest match!
   - `FE0F` is optional from the input during matching.
     - Example: `👨‍❤️‍👨 [1F468 200D 2764 FE0F 200D 1F468]`
       - Match: `1F468 200D 2764 FE0F 200D 1F468` — fully-qualified
       - Match: `1F468 200D 2764 200D 1F468` — missing `FE0F`
       - No match: `1F468 FE0F 200D 2764 FE0F 200D 1F468` — extra `FE0F`
       - No match: `1F468 200D 2764 FE0F FE0F 200D 1F468` — has (2) `FE0F`
   - This is equivalent to `/^(emoji1|emoji2|...)/` where `\uFE0F` is replaced with `\uFE0F?` and `*` is replaced with `\x2A`.
1. If an **Emoji Sequence** is found:
   - If the buffer is nonempty, emit a `Text` token, and clear the buffer.
   - Emit an `Emoji` token with the fully-qualified matching sequence.
   - Remove the matched sequence from the input.
1. Otherwise:
   1. Remove the leading codepoint from the input.
   1. Determine the character type:
      - If **Valid**, append the codepoint to the buffer.
        - This set can be precomputed from the union of characters in all groups and their NFD decompositions.
      - If **Mapped**, append the corresponding mapped codepoint(s) to the buffer.
      - If **Ignored**, do nothing.
      - Otherwise, the label cannot be normalized.
1. Repeat until all the input is consumed.
1. If the buffer is nonempty, emit a final `Text` token with its contents.
   - Return the list of emitted tokens.

Examples:

1. `"xyz👨🏻" [78 79 7A 1F468 1F3FB]` → `Text["xyz"]` + `Emoji["👨🏻"]`
1. `"A💩︎︎b" [41 FE0E 1F4A9 FE0E FE0E 62]` → `Text["a"]` + `Emoji["💩️"]` + `Text["b"]`
1. `"a™️" [61 2122 FE0F]` → `Text["atm"]`

### Validate

Given a list of `Emoji` and `Text` tokens, determine if the label is valid and return the **Label Type**. If any assertion fails, the name cannot be normalized.

1. If only `Emoji` tokens:
   - Return `"Emoji"`
1. If a single `Text` token and every characters is ASCII (`00..7F`):
   - `5F (_) LOW LINE` can only occur at the start.
     - Must match `/^_*[^_]*$/`
     - Examples: `"___"` and `"__abc"` are valid, `"abc__"` and `"_abc_"` are invalid.
   - The 3rd and 4th characters must not both be `2D (-) HYPHEN-MINUS`.
     - Must not match `/^..--/`
     - Examples: `"ab-c"` and `"---a"`are valid, `"xn--"` and `----` are invalid.
   - Return `"ASCII"`
     - The label is free of **Fenced** and **Combining Mark** characters, and not confusable.
1. Concatenate all the tokens together.
   - `5F (_) LOW LINE` can only occur at the start.
   - The first and last characters cannot be **Fenced**.
     - Examples: `"a’s"` and `"a・a"` are valid, `"’85"` and `"joneses’"` and `"・a・"` are invalid.
   - **Fenced** characters cannot be contiguous.
     - Examples: `"a・a’s"` is valid, `"6’0’’"` and `"a・・a"` are invalid.
1. The first character of every `Text` token must not be a **Combining Mark**.
1. Concatenate the `Text` tokens together.
1. Find the first **Group** that contain every text character:
   - If no group is found, the label cannot be normalized.
1. If the group is not **CM Whitelisted**:
   - Apply NFD to the concatenated text characters.
   - For every contiguous sequence of **NSM** characters:
     - Each character must be unique.
       - Example: `"x̀̀" [78 300 300]` has (2) grave accents.
     - The number of **NSM** characters cannot exceed **Maximum NSM** (4).
       - Example: ` "إؐؑؒؓؔ"‎ [625 610 611 612 613 614]` has (6) **NSM**.
1. [Wholes](#wholes) — check if text characters form a confusable.
1. The label is valid.
   - Return the name of the group as the **Label Type**.

Examples:

1. `Emoji["💩️"]` + `Emoji["💩️"]` → `"Emoji"`
1. `Text["abc$123"]` → `"ASCII"`
1. `Emoji["🚀️"]` + `Text["à"]` → `"Latin"`

### Wholes

A label is [whole-script confusable](https://unicode.org/reports/tr39/#def_whole_script_confusables) if a similarly-looking valid label can be constructed using one alternative character from a different group. The complete list of **Whole Confusables** can be found in [`spec.json`](#description-of-specjson). Each **Whole Confusable** has a set of non-confusing characters (`"valid"`) and a set of confusing characters (`"confused"`) where each character may be the member of one or more groups.

Example: **Whole Confusable** for `"g"`

|   Type   |   Code | Form | Character                | Latn | Hani | Japn | Kore | Armn | Cher | Lisu |
| :------: | -----: | :--: | :----------------------- | :--: | :--: | :--: | :--: | :--: | :--: | :--: |
|  valid   |   `67` | `g`  | LATIN SMALL LETTER G     |  A   |  A   |  A   |  A   |
| confused |  `581` | `ց`  | ARMENIAN SMALL LETTER CO |      |      |      |      |  B   |
| confused | `13C0` | `Ꮐ`  | CHEROKEE LETTER NAH      |      |      |      |      |      |  C   |
| confused | `13F3` | `Ᏻ`  | CHEROKEE LETTER YU       |      |      |      |      |      |  C   |
| confused | `A4D6` | `ꓖ`  | LISU LETTER GA           |      |      |      |      |      |      |  D   |

1. Allocate an empty character buffer.
1. Start with the set of **ALL** groups.
1. For each unique character in the label:
   - If the character is **Confused** (a member of a **Whole Confusable**):
     - Retain groups with **Whole Confusable** characters excluding the **Confusable Extent** of the matching **Confused** character.
     - If no groups remain, the label is not confusable.
     - The **Confusable Extent** is the fully-connected graph formed from different groups with the same confusable and different confusables of the same group.
       - The mapping from **Confused** to **Confusable Extent** can be precomputed.
     - In the table above, **Whole Confusable** for `"g"`, the rectangle formed by each capital letter is a **Confusable Extent**:
       - `A` is [`g`] ⊗ [*Latin*, *Han*, *Japanese*, *Korean*]
       - `B` is [`ց`] ⊗ [*Armn*]
       - `C` is [`Ꮐ`, `Ᏻ`] ⊗ [*Cher*]
       - `D` is [`ꓖ`] ⊗ [*Lisu*]
     - A **Confusable Extent** can span multiple characters and multiple groups. Consider the (incomplete) **Whole Confusable** for `"o"`:
       - `6F (o) LATIN SMALL LETTER O` → _Latin_, _Han_, _Japanese_, and _Korean_
       - `3007 (〇) IDEOGRAPHIC NUMBER ZERO` → _Han_, _Japanese_, _Korean_, and _Bopomofo_
       - **Confusable Extent** is [`o`, `〇`] ⊗ [*Latin*, *Han*, *Japanese*, *Korean*, *Bopomofo*]
   - If the character is **Unique**, the label is not confusable.
     - This set can be precomputed from characters that appear in exactly one group and are not **Confused**.
   - Otherwise:
     - Append the character to the buffer.
1. If any **Confused** characters were found:
   - If there are no buffered characters, the label is confusable.
   - If any of the remaining groups contain all of the buffered characters, the label is confusable.
   - Example: `"0х" [30 445]`
     1. `30 (0) DIGIT ZERO`
        - Not **Confused** or **Unique**, add to buffer.
     1. `445 (х) CYRILLIC SMALL LETTER HA`
        - **Confusable Extent** is [`х`, `4B3 (ҳ) CYRILLIC SMALL LETTER HA WITH DESCENDER`] ⊗ [*Cyrillic*]
        - **Whole Confusable** excluding the extent is [`78 (x) LATIN SMALL LETTER X`, ...] → [*Latin*, ...]
        - Remaining groups: **ALL** ∩ [*Latin*, ...] → [*Latin*, ...]
     1. There was (1) buffered character:
        - _Latin_ also contains `30` → `"0x" [30 78]`
     1. The label is confusable.
1. The label is not confusable.

A label composed of confusable characters isn't necessarily confusable.

- Example: `"тӕ" [442 4D5]`
  1.  `442 (т) CYRILLIC SMALL LETTER TE`
      - **Confusable Extent** is [`т`] ⊗ [*Cyrillic*]
      - **Whole Confusable** excluding the extent is [`3C4 (τ) GREEK SMALL LETTER TAU`] → [*Greek*]
      - Remaining groups: **ALL** ∩ [*Greek*] → [*Greek*]
  1.  `4D5 (ӕ) CYRILLIC SMALL LIGATURE A IE`
      - **Confusable Extent** is [`ӕ`] ⊗ [*Greek*]
      - **Whole Confusable** excluding the extent is [`E6 (æ) LATIN SMALL LETTER AE`] → [*Latin*]
      - Remaining groups: [*Greek*] ∩ [*Latin*] → ∅
  1.  No groups remain so the label is not confusable.

### Split

- Partition a name into labels, separated by `2D (.) FULL STOP`, and return the resulting array.
  - Example: `"abc.123.eth"` → `["abc", "123", "eth"]`
- The empty string is 0-labels: `""` → `[]`

### Join

- Assemble an array of labels into a name, inserting `2D (.) FULL STOP` between each label, and return the resulting string.
  - Example: `["abc", "123", "eth"]` → `"abc.123.eth"`

## Description of `spec.json`

- **Groups** (`"groups"`) — [groups](#appendix-additional-resources) of characters that can constitute a label
  - `"name"` — ASCII name of the group (or abbreviation if **Restricted**)
    - Examples: _Latin_, _Japanese_, _Egyp_
  - **Restricted** (`"restricted"`) — **`true`** if [Excluded](https://www.unicode.org/reports/tr31#Table_Candidate_Characters_for_Exclusion_from_Identifiers) or [Limited-Use](https://www.unicode.org/reports/tr31/#Table_Limited_Use_Scripts) script
    - Examples: _Latin_ → **`false`**, _Egyp_ → **`true`**
  - `"primary"` — subset of characters that define the group
    - Examples: `"a"` → _Latin_, `"あ"` → _Japanese_, `"𓀀"` → _Egyp_
  - `"secondary"` — subset of characters included with the group
    - Example: `"0"` → _Common_ but mixable with _Latin_
  - **CM Whitelist(ed)** (`"cm"`) — (optional) set of allowed compound sequences in NFC
    - Each compound sequence is a character followed by one or more **Combining Marks**.
      - Example: `à̀̀` → `E0 300 300`
    - Currently, every group that is **CM Whitelist** has zero compound sequences.
    - **CM Whitelisted** is effectively **`true`** if `[]` otherwise **`false`**
- **Ignored** (`"ignored"`) — [characters](#appendix-additional-resources) that are ignored during normalization
  - Example: `34F (�) COMBINING GRAPHEME JOINER`
- **Mapped** (`"mapped"`) — characters that are mapped to a sequence of **valid** characters
  - Example: `41 (A) LATIN CAPITAL LETTER A` → `[61 (a) LATIN SMALL LETTER A]`
  - Example: `2165 (Ⅵ) ROMAN NUMERAL SIX` → `[76 (v) LATIN SMALL LETTER V, 69 (i) LATIN SMALL LETTER I]`
- **Whole Confusable** (`"wholes"`) — groups of characters that look similar
  - `"valid"` — subset of confusable characters that are allowed
    - Example: `34 (4) DIGIT FOUR`
  - **Confused** (`"confused"`) — subset of confusable characters that confuse
    - Example: `13CE (Ꮞ) CHEROKEE LETTER SE`
- **Fenced** (`"fenced"`) — [characters](#appendix-additional-resources) that cannot be first, last, or contiguous
  - Example: `2044 (⁄) FRACTION SLASH`
- **Emoji Sequence(s)** (`"emoji"`) — valid [emoji sequences](#appendix-additional-resources)
  - Example: `👨‍💻 [1F468 200D 1F4BB] man technologist`
- **Combining Marks / CM** (`"cm"`) — [characters](#appendix-additional-resources) that are [Combining Marks](https://unicode.org/faq/char_combmark.html)
- **Non-spacing Marks / NSM** (`"nsm"`) — valid [subset](#appendix-additional-resources) of **CM** with general category (`"Mn"` or `"Me"`)
- **Maximum NSM** (`"nsm_max"`) — maximum sequence length of unique **NSM**
- **Should Escape** (`"escape"`) — [characters](#appendix-additional-resources) that shouldn't be printed
- **NFC Check** (`"nfc_check"`) — valid [subset](#appendix-additional-resources) of characters that [may require NFC](https://unicode.org/reports/tr15/#NFC_QC_Optimization)

## Description of `nf.json`

- `"decomp"` — [mapping](https://www.unicode.org/reports/tr44/tr44-30.html#Character_Decomposition_Mappings) from a composed character to a sequence of (partially)-decomposed characters
  - [`UnicodeData.txt`](https://www.unicode.org/reports/tr44/tr44-30.html#UnicodeData.txt) where `Decomposition_Mapping` exists and does not have a [formatting tag](https://www.unicode.org/reports/tr44/tr44-30.html#Formatting_Tags_Table)
- `"exclusions"` — set of characters for which the `"decomp"` mapping is not applied when forming a composition
  - [`CompositionExclusions.txt`](https://www.unicode.org/reports/tr44/tr44-30.html#CompositionExclusions.txt)
- `"ranks"` — sets of characters with increasing [`Canonical_Combining_Class`](https://www.unicode.org/reports/tr44/tr44-30.html#Canonical_Combining_Class_Values)
  - [`UnicodeData.txt`](https://www.unicode.org/reports/tr44/tr44-30.html#UnicodeData.txt) grouped by `Canonical_Combining_Class`
  - Class `0` is not included
- `"qc"` — set of characters with property [`NFC_QC`](https://www.unicode.org/reports/tr44/tr44-30.html#Decompositions_and_Normalization) of value `N` or `M`
  - [`DerivedNormalizationProps.txt`](https://www.unicode.org/reports/tr44/tr44-30.html#DerivedNormalizationProps.txt)
  - **NFC Check** (from [`spec.json`](#description-of-specjson)) is a subset of this set

## Derivation

- [IDNA 2003](https://unicode.org/Public/idna/15.1.0/IdnaMappingTable.txt)
  - `UseSTD3ASCIIRules` is **`true`**
  - `VerifyDnsLength` is **`false`**
  - `Transitional_Processing` is **`false`**
  - The following [deviations](https://unicode.org/reports/tr46/#Table_Deviation_Characters) are **valid**:
    - `DF (ß) LATIN SMALL LETTER SHARP S`
    - `3C2 (ς) GREEK SMALL LETTER FINAL SIGMA`
  - `CheckHyphens` is **`false`** ([WHATWG URL Spec § 3.3](https://url.spec.whatwg.org/#idna))
  - `CheckBidi` is **`false`**
  - [ContextJ](https://datatracker.ietf.org/doc/html/rfc5892#appendix-A.1):
    - `200C (�) ZERO WIDTH NON-JOINER` (ZWNJ) is **disallowed everywhere**.
    - `200D (�) ZERO WIDTH JOINER` (ZWJ) is **only allowed** in emoji sequences.
  - [ContextO](https://datatracker.ietf.org/doc/html/rfc5892#appendix-A.3):
    - `B7 (·) MIDDLE DOT` is **disallowed**.
    - `375 (͵) GREEK LOWER NUMERAL SIGN` is **disallowed**.
    - `5F3 (׳) HEBREW PUNCTUATION GERESH` and `5F4 (״) HEBREW PUNCTUATION GERSHAYIM` are _Greek_.
    - `30FB (・) KATAKANA MIDDLE DOT` is **Fenced** and _Han_, _Japanese_, _Korean_, and _Bopomofo_.
    - Some [Extended Arabic Numerals](https://en.wikipedia.org/wiki/Arabic_numerals) are **mapped**:
      - `6F0 (۰)` → `660 (٠) ARABIC-INDIC DIGIT ZERO`
      - `6F1 (۱)` → `661 (١) ARABIC-INDIC DIGIT ONE`
      - `6F2 (۲)` → `662 (٢) ARABIC-INDIC DIGIT TWO`
      - `6F3 (۳)` → `663 (٣) ARABIC-INDIC DIGIT THREE`
      - `6F7 (۷)` → `667 (٧) ARABIC-INDIC DIGIT SEVEN`
      - `6F8 (۸)` → `668 (٨) ARABIC-INDIC DIGIT EIGHT`
      - `6F9 (۹)` → `669 (٩) ARABIC-INDIC DIGIT NINE`
- [Punycode](https://datatracker.ietf.org/doc/html/rfc3492) is not decoded.
- The following ASCII characters are **valid**:
  - `24 ($) DOLLAR SIGN`
  - `5F (_) LOW LINE` with [restrictions](#validate)
- Only label separator is `2E (.) FULL STOP`
  - No character maps to this character.
  - This simplifies name detection in unstructured text.
  - The following alternatives are **disallowed**:
    - `3002 (。) IDEOGRAPHIC FULL STOP`
    - `FF0E (．) FULLWIDTH FULL STOP`
    - `FF61 (｡) HALFWIDTH IDEOGRAPHIC FULL STOP`
- [Many characters](#appendix-additional-resources) are **disallowed** for various reasons:
  - Nearly all punctuation are **disallowed**.
    - Example: `589 (։) ARMENIAN FULL STOP`
  - All parentheses and brackets are **disallowed**.
    - Example: `2997 (⦗) LEFT BLACK TORTOISE SHELL BRACKET`
  - Nearly all vocalization annotations are **disallowed**.
    - Example: `294 (ʔ) LATIN LETTER GLOTTAL STOP`
  - Obsolete, deprecated, and ancient characters are **disallowed**.
    - Example: `463 (ѣ) CYRILLIC SMALL LETTER YAT`
  - Combining, modifying, reversed, flipped, turned, and partial variations are **disallowed**.
    - Example: `218A (↊) TURNED DIGIT TWO`
  - When multiple weights of the same character exist, the variant closest to "heavy" is selected and the rest **disallowed**.
    - Example: `🞡🞢🞣🞤✚🞥🞦🞧` → `271A (✚) HEAVY GREEK CROSS`
    - This occasionally selects an emoji.
      - Example: ✔️ or `2714 (✔︎) HEAVY CHECK MARK` is selected instead of `2713 (✓) CHECK MARK`
  - Many visually confusable characters are **disallowed**.
    - Example: `131 (ı) LATIN SMALL LETTER DOTLESS I`
  - Many ligatures, _n_-graphs, and _n_-grams are **disallowed.**
    - Example: `A74F (ꝏ) LATIN SMALL LETTER OO`
  - Many esoteric characters are **disallowed**.
    - Example: `2376 (⍶) APL FUNCTIONAL SYMBOL ALPHA UNDERBAR`
- Many hyphen-like characters are **mapped** to `2D (-) HYPHEN-MINUS`:
  - `2010 (‐) HYPHEN`
  - `2011 (‑) NON-BREAKING HYPHEN`
  - `2012 (‒) FIGURE DASH`
  - `2013 (–) EN DASH`
  - `2014 (—) EM DASH`
  - `2015 (―) HORIZONTAL BAR`
  - `2043 (⁃) HYPHEN BULLET`
  - `2212 (−) MINUS SIGN`
  - `23AF (⎯) HORIZONTAL LINE EXTENSION`
  - `23E4 (⏤) STRAIGHTNESS`
  - `FE58 (﹘) SMALL EM DASH`
  - `2E3A (⸺) TWO-EM DASH` → `"--"`
  - `2E3B (⸻) THREE-EM DASH` → `"---"`
- Characters are assigned to **Groups** according to [Unicode Script_Extensions](https://www.unicode.org/reports/tr24/#Script_Extensions_Def).
- **Groups** may contain [multiple scripts](#appendix-additional-resources):
  - Only _Latin_, _Greek_, _Cyrillic_, _Han_, _Japanese_, and _Korean_ have access to _Common_ characters.
  - _Latin_, _Greek_, _Cyrillic_, _Han_, _Japanese_, _Korean_, and _Bopomofo_ only permit specific **Combining Mark** sequences.
  - _Han_, _Japanese_, and _Korean_ have access to `a-z`.
  - **Restricted** groups are always single-script.
  - [Unicode augmented script sets](https://www.unicode.org/reports/tr39/#Mixed_Script_Detection)
- Scripts _Braille_, _Linear A_, _Linear B_, and _Signwriting_ are **disallowed**.
- `27 (') APOSTROPHE` is **mapped** to `2019 (’) RIGHT SINGLE QUOTATION MARK` for convenience.
- Ethereum symbol (`39E (Ξ) GREEK CAPITAL LETTER XI`) is case-folded and _Common_.
- Emoji:
  - All emoji are [fully-qualified](https://www.unicode.org/reports/tr51/#def_fully_qualified_emoji).
  - Digits (`0-9`) are [not emoji](#appendix-additional-resources).
  - Emoji [mapped to non-emoji by IDNA](#appendix-additional-resources) cannot be used as emoji.
  - Emoji [disallowed by IDNA](#appendix-additional-resources) with default text-presentation are **disabled**:
    - `203C (‼️) double exclamation mark`
    - `2049 (⁉️) exclamation question mark `
  - Remaining emoji characters are marked as **disallowed** (for text processing).
  - All `RGI_Emoji_ZWJ_Sequence` are **enabled**.
  - All `Emoji_Keycap_Sequence` are **enabled**.
  - All `RGI_Emoji_Tag_Sequence` are **enabled**.
  - All `RGI_Emoji_Modifier_Sequence` are **enabled**.
  - All `RGI_Emoji_Flag_Sequence` are **enabled**.
  - `Basic_Emoji` of the form `[X FE0F]` are **enabled**.
  - Emoji with default emoji-presentation are **enabled** as `[X FE0F]`.
  - Remaining single-character emoji are **enabled** as `[X FE0F]` (explicit emoji-presentation).
  - All singular Skin-color Modifiers are **disabled**.
  - All singular Regional Indicators are **disabled**.
  - Blacklisted emoji are **disabled**.
  - Whitelisted emoji are **enabled**.
- Confusables:
  - Nearly all [Unicode Confusables](https://www.unicode.org/Public/security/15.1.0/confusables.txt)
  - Emoji are not confusable.
  - ASCII confusables are case-folded.
    - Example: `61 (a) LATIN SMALL LETTER A` confuses with `13AA (Ꭺ) CHEROKEE LETTER GO`

## Backwards Compatibility

- 99% of names are still valid.
- Preserves as much [Unicode IDNA](https://unicode.org/reports/tr46/) and [WHATWG URL](https://url.spec.whatwg.org/#idna) compatibility as possible.
- Only [valid emoji sequences](#appendix-additional-resources) are permitted.

## Security Considerations

- Unicode presentation may vary between applications and devices.
  - Unicode text is ultimately subject to font-styling and display context.
  - Unsupported characters (`�`) may appear unremarkable.
  - Normalized single-character emoji sequences do not retain their explicit emoji-presentation and may display with [text or emoji](https://www.unicode.org/reports/tr51/#Presentation_Style) presentation styling.
    - `❤︎` — text-presentation and default-color
    - <span className="text-green-500">`❤︎`</span> — text-presentation and <span className="text-green-500">green</span>-color
    - <span className="text-green-500">`❤️`</span> — emoji-presentation and <span className="text-green-500">green</span>-color
  - Unsupported emoji sequences with ZWJ may appear indistinguishable from those without ZWJ.
    - `💩💩 [1F4A9 1F4A9]`
    - `💩‍💩 [1F4A9 200D 1F4A9]` → _error: Disallowed character_
- Names composed of labels with varying bidi properties [may appear differently](https://discuss.ens.domains/t/bidi-label-ordering-spoof/15824) depending on context.
  - Normalization does not enforce single-directional names.
  - Names may be composed of labels of different directions but normalized labels are never bidirectional.
    - [LTR].[RTL] `bahrain.مصر`
    - [LTR+RTL] `bahrainمصر` → _error: Illegal mixture: Latin + Arabic_
- Not all normalized names are visually unambiguous.
- This ENSIP only addresses **single-character** [confusables](https://www.unicode.org/reports/tr39/).
  - There exist confusable **multi-character** sequences:
    - `"ஶ்ரீ" [BB6 BCD BB0 BC0]`
    - `"ஸ்ரீ" [BB8 BCD BB0 BC0]`
  - There exist confusable emoji sequences:
    - `🚴 [1F6B4]` and `🚴🏻 [1F6B4 1F3FB]`
    - `🇺🇸 [1F1FA 1F1F8]` and `🇺🇲 [1F1FA 1F1F2]`
    - `♥ [2665] BLACK HEART SUIT` and `❤ [2764] HEAVY BLACK HEART`

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).

## Appendix: Reference Specifications

- [EIP-137: Ethereum Domain Name Service](https://eips.ethereum.org/EIPS/eip-137)
- [ENSIP-1: ENS](./1.md)
- [UAX-15: Normalization Forms](https://unicode.org/reports/tr15/)
- [UAX-24: Script Property](https://www.unicode.org/reports/tr24/)
- [UAX-29: Text Segmentation](https://unicode.org/reports/tr29/)
- [UAX-31: Identifier and Pattern Syntax](https://www.unicode.org/reports/tr31/)
- [UTS-39: Security Mechanisms](https://www.unicode.org/reports/tr39/)
- [UAX-44: Character Database](https://www.unicode.org/reports/tr44/)
- [UTS-46: IDNA Compatibility Processing](https://unicode.org/reports/tr46/)
- [UTS-51: Emoji](https://www.unicode.org/reports/tr51)
- [RFC-3492: Punycode](https://datatracker.ietf.org/doc/html/rfc3492)
- [RFC-5891: IDNA: Protocol](https://datatracker.ietf.org/doc/html/rfc5891)
- [RFC-5892: The Unicode Code Points and IDNA](https://datatracker.ietf.org/doc/html/rfc5892)
- [Unicode CLDR](https://github.com/unicode-org/cldr)
- [WHATWG URL: IDNA](https://url.spec.whatwg.org/#idna)

## Appendix: Additional Resources

- [Supported Groups](https://github.com/adraffy/ens-normalize.js/blob/main/tools/ensip/groups.md)
- [Supported Emoji](https://github.com/adraffy/ens-normalize.js/blob/main/tools/ensip/emoji.md)
- [Additional Disallowed Characters](https://github.com/adraffy/ens-normalize.js/blob/main/tools/ensip/disallowed.csv)
- [Ignored Characters](https://github.com/adraffy/ens-normalize.js/blob/main/tools/ensip/ignored.csv)
- [Should Escape Characters ](https://github.com/adraffy/ens-normalize.js/blob/main/tools/ensip/escape.csv)
- [Combining Marks](https://github.com/adraffy/ens-normalize.js/blob/main/tools/ensip/cm.csv)
- [Non-spacing Marks](https://github.com/adraffy/ens-normalize.js/blob/main/tools/ensip/nsm.csv)
- [Fenced Characters](https://github.com/adraffy/ens-normalize.js/blob/main/tools/ensip/fenced.csv)
- [NFC Quick Check](https://github.com/adraffy/ens-normalize.js/blob/main/tools/ensip/nfc_check.csv)

## Appendix: Validation Tests

A list of [validation tests](https://github.com/adraffy/ens-normalize.js/blob/main/validate/tests.json) are provided with the following interpretation:

- Already Normalized: `{name: "a"}` → `normalize("a")` is `"a"`
- Need Normalization: `{name: "A", norm: "a"}` → `normalize("A")` is `"a"`
- Expect Error: `{name: "@", error: true}` → `normalize("@")` throws

## Annex: Beautification

Follow [algorithm](#algorithm), except:

- Do not strip `FE0F` from `Emoji` tokens.
- Replace `3BE (ξ) GREEK SMALL LETTER XI` with `39E (Ξ) GREEK CAPITAL LETTER XI` if the label isn't _Greek_.
- Example: `normalize("‐Ξ1️⃣") [2010 39E 31 FE0F 20E3]` is `"-ξ1⃣" [2D 3BE 31 20E3]`
- Example: `beautify("-ξ1⃣") [2D 3BE 31 20E3]"` is `"-Ξ1️⃣" [2D 39E 31 FE0F 20E3]`
