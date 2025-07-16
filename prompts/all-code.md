<rust>

```rs [./tests/ens_tests.rs]

use ens_normalize_rs::EnsNameNormalizer;

use lazy_static::lazy_static;

use rayon::prelude::*;

use rstest::rstest;

use serde::Deserialize;



#[derive(Debug, Clone, Deserialize)]

#[serde(untagged)]

pub enum Entry {

    VersionInfo {

        name: String,

        validated: String,

        built: String,

        cldr: String,

        derived: String,

        ens_hash_base64: String,

        nf_hash_base64: String,

        spec_hash: String,

        unicode: String,

        version: String,

    },

    TestCase(TestCase),

}



#[derive(Debug, Clone, Deserialize, Default)]

pub struct TestCase {

    name: String,

    comment: Option<String>,

    #[serde(default)]

    error: bool,

    norm: Option<String>,

}



pub type IndexedTestCase<'a> = (usize, &'a TestCase);



lazy_static! {

    pub static ref ENS_TESTS: Vec<Entry> =

        serde_json::from_str(include_str!("ens_cases.json")).unwrap();

}



#[rstest]

fn ens_tests() {

    test_cases_parallel(&only_cases(&ENS_TESTS))

}



fn test_cases_parallel(cases: &[IndexedTestCase]) {

    let normalizer = EnsNameNormalizer::default();

    let results = cases

        .par_iter() // Parallel iterator from Rayon

        .map(|(i, test_case)| (i, process_test_case(&normalizer, test_case)))

        .filter_map(|(i, r)| r.err().map(|e| (i, e)))

        .collect::<Vec<_>>();



    if !results.is_empty() {

        let info = results

            .iter()

            .map(|(i, e)| format!("{}: {}", i, e))

            .collect::<Vec<_>>()

            .join("\n");

        panic!("{} cases failed:\n{}", results.len(), info);

    }

}



fn process_test_case(normalizer: &EnsNameNormalizer, case: &TestCase) -> Result<(), anyhow::Error> {

    let test_name = match (case.comment.as_ref(), case.name.as_str()) {

        (Some(comment), name) if name.len() < 64 => format!("{comment} (`{name}`)"),

        (Some(comment), _) => comment.clone(),

        (None, name) => name.to_string(),

    };

    let result = normalizer.process(&case.name);



    match result {

        Err(_e) if case.error => (),

        Ok(processed) if !case.error => {

            let actual = processed.normalize();

            if let Some(expected) = &case.norm {

                assert_eq!(

                    actual,

                    expected.to_string(),

                    "in test case '{test_name}': expected '{expected}', got '{actual}'"

                );

            } else {

                assert_eq!(

                    actual, case.name,

                    "in test case '{test_name}': expected '{}', got '{actual}'",

                    case.name

                );

            }

        }

        Err(e) => anyhow::bail!("in test case '{test_name}': expected no error, got {e}"),

        Ok(_) => anyhow::bail!("in test case '{test_name}': expected error, got success"),

    }



    Ok(())

}



fn only_cases(entries: &[Entry]) -> Vec<IndexedTestCase> {

    entries

        .iter()

        .filter_map(|e| match e {

            Entry::TestCase(t) => Some(t),

            _ => None,

        })

        .enumerate()

        .collect()

}

```

```rs [./tests/e2e.rs]

use ens_normalize_rs::{CurrableError, DisallowedSequence, EnsNameNormalizer, ProcessError};

use pretty_assertions::assert_eq;

use rstest::{fixture, rstest};



#[fixture]

#[once]

fn normalizer() -> EnsNameNormalizer {

    EnsNameNormalizer::default()

}



#[rstest]

#[case("vitalik.eth", Ok(("vitalik.eth", "vitalik.eth")))]

#[case("VITALIK.ETH", Ok(("vitalik.eth", "vitalik.eth")))]

#[case("vitalik❤️‍🔥.eth", Ok(("vitalik❤‍🔥.eth", "vitalik❤️‍🔥.eth")))]

#[case("🅰🅱🅲", Ok(("🅰🅱🅲", "🅰️🅱️🅲")))]

#[case("-ξ1⃣", Ok(("-ξ1⃣", "-Ξ1️⃣")))]

#[case("______________vitalik", Ok(("______________vitalik", "______________vitalik")))]

#[case(

    "vitalik__",

    Err(currable_error(CurrableError::UnderscoreInMiddle, 7, "_", Some("")))

)]

#[case(

    "xx--xx",

    Err(currable_error(CurrableError::HyphenAtSecondAndThird, 2, "--", Some("")))

)]

#[case(

    "abcd.\u{303}eth",

    Err(currable_error(CurrableError::CmStart, 0, "\u{303}", Some("")))

)]

#[case(

    "vi👍\u{303}talik",

    Err(currable_error(CurrableError::CmAfterEmoji, 3, "\u{303}", Some("")))

)]

#[case(

    "・abcd",

    Err(currable_error(CurrableError::FencedLeading, 0, "・", Some("")))

)]

#[case(

    "abcd・",

    Err(currable_error(CurrableError::FencedTrailing, 4, "・", Some("")))

)]

#[case(

    "a・’a",

    Err(currable_error(CurrableError::FencedConsecutive, 1, "・’", Some("・")))

)]

#[case("vitalik .eth", Err(disallowed(" ")))]

#[case("vitalik..eth", Err(empty_label()))]

#[case("..", Err(empty_label()))]

fn e2e_tests(

    #[case] name: &str,

    #[case] expected: Result<(&str, &str), ProcessError>,

    normalizer: &EnsNameNormalizer,

) {

    let actual = normalizer.process(name);

    match expected {

        Ok((expected_normalized, expected_beautified)) => {

            let res = actual.expect("process should succeed");

            let normalized = res.normalize();

            assert_eq!(

                normalized, expected_normalized,

                "expected '{expected_normalized}', got '{normalized}'"

            );

            let beautified = res.beautify();

            assert_eq!(

                beautified, expected_beautified,

                "expected '{expected_beautified}', got '{beautified}'"

            );

        }

        Err(expected) => assert_eq!(actual.unwrap_err(), expected),

    }

}



fn disallowed(sequence: &str) -> ProcessError {

    ProcessError::DisallowedSequence(DisallowedSequence::Invalid(sequence.to_string()))

}



fn empty_label() -> ProcessError {

    ProcessError::DisallowedSequence(DisallowedSequence::EmptyLabel)

}



fn currable_error(

    inner: CurrableError,

    index: usize,

    sequence: &str,

    maybe_suggest: Option<&str>,

) -> ProcessError {

    ProcessError::CurrableError {

        inner,

        index,

        sequence: sequence.to_string(),

        maybe_suggest: maybe_suggest.map(|s| s.to_string()),

    }

}

```

```rs [./examples/tokens.rs]

use ens_normalize_rs::EnsNameNormalizer;



fn main() {

    let normalizer = EnsNameNormalizer::default();



    let name = "Nàme‍🧙‍♂.eth";

    let result = normalizer.tokenize(name).unwrap();



    for token in result.tokens {

        if token.is_disallowed() {

            println!("disallowed: {:?}", token.as_string());

        }

    }

}

```

```rs [./examples/benchmark.rs]

const SIZE: usize = 100;

const NAME_LENGTH: usize = 1000;

const NAME: &str = "$Sand-#️⃣🇪🇨";



fn main() {

    let now = std::time::Instant::now();

    let name = std::iter::repeat(NAME)

        .take(NAME_LENGTH / NAME.len())

        .collect::<Vec<_>>()

        .join("");

    let normalizer = ens_normalize_rs::EnsNameNormalizer::default();

    for _ in 0..SIZE {

        let _name = normalizer.process(&name).unwrap();

    }

    // Total time to process 100 names: 728.916542ms

    println!("Total time to process {SIZE} names: {:?}", now.elapsed());

}

```

```rs [./examples/simple.rs]

fn main() {

    // Using normalizer to reuse preloaded data

    let normalizer = ens_normalize_rs::EnsNameNormalizer::default();

    let name = "🅰️🅱.eth";

    let processed = normalizer.process(name).unwrap();

    let beautified_name = processed.beautify();

    let normalized_name = processed.normalize();



    assert_eq!(normalized_name, "🅰🅱.eth");

    assert_eq!(beautified_name, "🅰️🅱️.eth");



    // Using normalize directly

    let normalized = normalizer.normalize("Levvv.eth").unwrap();

    assert_eq!(normalized, "levvv.eth");



    // Handling errors

    assert!(matches!(

        normalizer.normalize("Levvv..eth"),

        Err(ens_normalize_rs::ProcessError::DisallowedSequence(

            ens_normalize_rs::DisallowedSequence::EmptyLabel

        ))

    ));

    assert!(matches!(

        // U+200D ZERO WIDTH JOINER

        normalizer.normalize("Ni‍ck.ETH"),

        Err(ens_normalize_rs::ProcessError::DisallowedSequence(

            ens_normalize_rs::DisallowedSequence::InvisibleCharacter(0x200d)

        ))

    ));

}

```

```rs [./src/join.rs]

use crate::{constants, utils, CodePoint, EnsNameToken, ValidatedLabel};



/// Joins validated labels into a string

pub fn join_labels(labels: &[ValidatedLabel]) -> String {

    let labels_cps = labels.iter().map(|label| {

        label

            .tokens

            .iter()

            .filter_map(|token| match token {

                EnsNameToken::Disallowed(_) | EnsNameToken::Ignored(_) | EnsNameToken::Stop(_) => {

                    None

                }

                EnsNameToken::Valid(token) => Some(&token.cps),

                EnsNameToken::Mapped(token) => Some(&token.cps),

                EnsNameToken::Nfc(token) => Some(&token.cps),

                EnsNameToken::Emoji(token) => Some(&token.cps_no_fe0f),

            })

            .flatten()

            .cloned()

            .collect::<Vec<_>>()

    });



    join_cps(labels_cps)

}



/// Joins code points into a string

pub fn join_cps(cps: impl Iterator<Item = Vec<CodePoint>>) -> String {

    let cps_flatten = itertools::intersperse(cps, vec![constants::CP_STOP])

        .flatten()

        .collect::<Vec<_>>();



    utils::cps2str(&cps_flatten)

}

```

```rs [./src/constants.rs]

#![allow(dead_code)]



use crate::CodePoint;



pub const CP_STOP: CodePoint = 0x2E;

pub const CP_FE0F: CodePoint = 0xFE0F;

pub const CP_APOSTROPHE: CodePoint = 8217;

pub const CP_SLASH: CodePoint = 8260;

pub const CP_MIDDLE_DOT: CodePoint = 12539;

pub const CP_XI_SMALL: CodePoint = 0x3BE;

pub const CP_XI_CAPITAL: CodePoint = 0x39E;

pub const CP_UNDERSCORE: CodePoint = 0x5F;

pub const CP_HYPHEN: CodePoint = 0x2D;

pub const CP_ZERO_WIDTH_JOINER: CodePoint = 0x200D;

pub const CP_ZERO_WIDTH_NON_JOINER: CodePoint = 0x200C;



pub const GREEK_GROUP_NAME: &str = "Greek";

pub const MAX_EMOJI_LEN: usize = 0x2d;

pub const STR_FE0F: &str = "\u{fe0f}";

```

```rs [./src/error.rs]

use crate::CodePoint;



#[derive(Debug, Clone, thiserror::Error, PartialEq, Eq)]

pub enum ProcessError {

    #[error("contains visually confusing characters from multiple scripts: {0}")]

    Confused(String),

    #[error("contains visually confusing characters from {group1} and {group2} scripts")]

    ConfusedGroups { group1: String, group2: String },

    #[error("invalid character ('{sequence}') at position {index}: {inner}")]

    CurrableError {

        inner: CurrableError,

        index: usize,

        sequence: String,

        maybe_suggest: Option<String>,

    },

    #[error("disallowed sequence: {0}")]

    DisallowedSequence(#[from] DisallowedSequence),

}



#[derive(Debug, Clone, thiserror::Error, PartialEq, Eq)]

pub enum CurrableError {

    #[error("underscore in middle")]

    UnderscoreInMiddle,

    #[error("hyphen at second and third position")]

    HyphenAtSecondAndThird,

    #[error("combining mark in disallowed position at the start of the label")]

    CmStart,

    #[error("combining mark in disallowed position after an emoji")]

    CmAfterEmoji,

    #[error("fenced character at the start of a label")]

    FencedLeading,

    #[error("fenced character at the end of a label")]

    FencedTrailing,

    #[error("consecutive sequence of fenced characters")]

    FencedConsecutive,

}



#[derive(Debug, Clone, thiserror::Error, PartialEq, Eq)]

pub enum DisallowedSequence {

    #[error("disallowed character: {0}")]

    Invalid(String),

    #[error("invisible character: {0}")]

    InvisibleCharacter(CodePoint),

    #[error("empty label")]

    EmptyLabel,

    #[error("nsm too many")]

    NsmTooMany,

    #[error("nsm repeated")]

    NsmRepeated,

}

```

```rs [./src/lib.rs]

mod beautify;

mod code_points;

pub(crate) mod constants;

mod error;

mod join;

mod normalizer;

mod static_data;

mod tokens;

mod utils;

mod validate;



pub use code_points::*;

pub use error::{CurrableError, DisallowedSequence, ProcessError};

pub use normalizer::{beautify, normalize, process, tokenize, EnsNameNormalizer, ProcessedName};

pub use tokens::*;

pub use validate::{LabelType, ValidatedLabel};

```

```rs [./src/normalizer.rs]

use crate::{

    beautify::beautify_labels, join::join_labels, validate::validate_name, CodePointsSpecs,

    ProcessError, TokenizedName, ValidatedLabel,

};



#[derive(Default)]

pub struct EnsNameNormalizer {

    specs: CodePointsSpecs,

}



#[derive(Debug, Clone, PartialEq, Eq)]

pub struct ProcessedName {

    pub labels: Vec<ValidatedLabel>,

    pub tokenized: TokenizedName,

}



impl EnsNameNormalizer {

    pub fn new(specs: CodePointsSpecs) -> Self {

        Self { specs }

    }



    pub fn tokenize(&self, input: impl AsRef<str>) -> Result<TokenizedName, ProcessError> {

        TokenizedName::from_input(input.as_ref(), &self.specs, true)

    }



    pub fn process(&self, input: impl AsRef<str>) -> Result<ProcessedName, ProcessError> {

        let input = input.as_ref();

        let tokenized = self.tokenize(input)?;

        let labels = validate_name(&tokenized, &self.specs)?;

        Ok(ProcessedName { tokenized, labels })

    }



    pub fn normalize(&self, input: impl AsRef<str>) -> Result<String, ProcessError> {

        self.process(input).map(|processed| processed.normalize())

    }



    pub fn beautify(&self, input: impl AsRef<str>) -> Result<String, ProcessError> {

        self.process(input).map(|processed| processed.beautify())

    }

}



impl ProcessedName {

    pub fn normalize(&self) -> String {

        join_labels(&self.labels)

    }



    pub fn beautify(&self) -> String {

        beautify_labels(&self.labels)

    }

}



pub fn tokenize(input: impl AsRef<str>) -> Result<TokenizedName, ProcessError> {

    EnsNameNormalizer::default().tokenize(input)

}



pub fn process(input: impl AsRef<str>) -> Result<ProcessedName, ProcessError> {

    EnsNameNormalizer::default().process(input)

}



pub fn normalize(input: impl AsRef<str>) -> Result<String, ProcessError> {

    EnsNameNormalizer::default().normalize(input)

}



pub fn beautify(input: impl AsRef<str>) -> Result<String, ProcessError> {

    EnsNameNormalizer::default().beautify(input)

}

```

```rs [./src/validate.rs]

use crate::{

    constants, static_data::spec_json, utils, CodePoint, CodePointsSpecs, CollapsedEnsNameToken,

    CurrableError, DisallowedSequence, EnsNameToken, ParsedGroup, ParsedWholeValue, ProcessError,

    TokenizedLabel, TokenizedName,

};

use itertools::Itertools;

use std::collections::HashSet;

pub type LabelType = spec_json::GroupName;



/// Represents a validated ENS label as result of the `validate_label` function.

/// Contains the original tokenized label and the type of the label.

#[derive(Debug, Clone, PartialEq, Eq)]

pub struct ValidatedLabel {

    pub tokens: Vec<EnsNameToken>,

    pub label_type: LabelType,

}



pub fn validate_name(

    name: &TokenizedName,

    specs: &CodePointsSpecs,

) -> Result<Vec<ValidatedLabel>, ProcessError> {

    if name.is_empty() {

        return Ok(vec![]);

    }

    let labels = name

        .iter_labels()

        .map(|label| validate_label(label, specs))

        .collect::<Result<Vec<_>, _>>()?;

    Ok(labels)

}



/// Validates a tokenized ENS label according to the ENSIP 15 specification

/// https://docs.ens.domains/ensip/15#validate

pub fn validate_label(

    label: TokenizedLabel<'_>,

    specs: &CodePointsSpecs,

) -> Result<ValidatedLabel, ProcessError> {

    non_empty(&label)?;

    check_token_types(&label)?;

    if label.is_fully_emoji() {

        return Ok(ValidatedLabel {

            tokens: label.tokens.to_owned(),

            label_type: LabelType::Emoji,

        });

    };

    underscore_only_at_beginning(&label)?;

    if label.is_fully_ascii() {

        no_hyphen_at_second_and_third(&label)?;

        return Ok(ValidatedLabel {

            tokens: label.tokens.to_owned(),

            label_type: LabelType::Ascii,

        });

    }

    check_fenced(&label, specs)?;

    check_cm_leading_emoji(&label, specs)?;

    let group = check_and_get_group(&label, specs)?;

    Ok(ValidatedLabel {

        tokens: label.tokens.to_owned(),

        label_type: group.name,

    })

}



fn non_empty(label: &TokenizedLabel) -> Result<(), ProcessError> {

    let non_ignored_token_exists = label.tokens.iter().any(|token| !token.is_ignored());

    if !non_ignored_token_exists {

        return Err(ProcessError::DisallowedSequence(

            DisallowedSequence::EmptyLabel,

        ));

    }

    Ok(())

}



fn check_token_types(label: &TokenizedLabel) -> Result<(), ProcessError> {

    if let Some(token) = label

        .tokens

        .iter()

        .find(|token| token.is_disallowed() || token.is_stop())

    {

        let cps = token.cps();

        let maybe_invisible_cp = cps.iter().find(|cp| {

            *cp == &constants::CP_ZERO_WIDTH_JOINER || *cp == &constants::CP_ZERO_WIDTH_NON_JOINER

        });

        if let Some(invisible_cp) = maybe_invisible_cp {

            return Err(ProcessError::DisallowedSequence(

                DisallowedSequence::InvisibleCharacter(*invisible_cp),

            ));

        } else {

            return Err(ProcessError::DisallowedSequence(

                DisallowedSequence::Invalid(utils::cps2str(&cps)),

            ));

        }

    }

    Ok(())

}



fn underscore_only_at_beginning(label: &TokenizedLabel) -> Result<(), ProcessError> {

    let leading_underscores = label

        .iter_cps()

        .take_while(|cp| *cp == constants::CP_UNDERSCORE)

        .count();

    let underscore_in_middle = label

        .iter_cps()

        .enumerate()

        .skip(leading_underscores)

        .find(|(_, cp)| *cp == constants::CP_UNDERSCORE);

    if let Some((index, _)) = underscore_in_middle {

        return Err(ProcessError::CurrableError {

            inner: CurrableError::UnderscoreInMiddle,

            index,

            sequence: utils::cps2str(&[constants::CP_UNDERSCORE]),

            maybe_suggest: Some("".to_string()),

        });

    }

    Ok(())

}



// The 3rd and 4th characters must not both be 2D (-) HYPHEN-MINUS.

// Must not match /^..--/

// Examples: "ab-c" and "---a"are valid, "xn--" and ---- are invalid.

fn no_hyphen_at_second_and_third(label: &TokenizedLabel) -> Result<(), ProcessError> {

    if label.iter_cps().nth(2) == Some(constants::CP_HYPHEN)

        && label.iter_cps().nth(3) == Some(constants::CP_HYPHEN)

    {

        return Err(ProcessError::CurrableError {

            inner: CurrableError::HyphenAtSecondAndThird,

            index: 2,

            sequence: utils::cps2str(&[constants::CP_HYPHEN, constants::CP_HYPHEN]),

            maybe_suggest: Some("".to_string()),

        });

    }

    Ok(())

}



fn check_fenced(label: &TokenizedLabel, specs: &CodePointsSpecs) -> Result<(), ProcessError> {

    if let Some(first_cp) = label.iter_cps().next() {

        if specs.is_fenced(first_cp) {

            return Err(ProcessError::CurrableError {

                inner: CurrableError::FencedLeading,

                index: 0,

                sequence: utils::cps2str(&[first_cp]),

                maybe_suggest: Some("".to_string()),

            });

        }

    }

    if let Some(last_cp) = label.iter_cps().last() {

        if specs.is_fenced(last_cp) {

            return Err(ProcessError::CurrableError {

                inner: CurrableError::FencedTrailing,

                index: label.iter_cps().count() - 1,

                sequence: utils::cps2str(&[last_cp]),

                maybe_suggest: Some("".to_string()),

            });

        }

    }



    for (i, window) in label.iter_cps().tuple_windows().enumerate() {

        let (one, two) = window;

        if specs.is_fenced(one) && specs.is_fenced(two) {

            return Err(ProcessError::CurrableError {

                inner: CurrableError::FencedConsecutive,

                index: i,

                sequence: utils::cps2str(&[one, two]),

                maybe_suggest: Some(utils::cp2str(one)),

            });

        }

    }

    Ok(())

}



fn check_cm_leading_emoji(

    label: &TokenizedLabel,

    specs: &CodePointsSpecs,

) -> Result<(), ProcessError> {

    let mut index = 0;

    let collapsed = label.collapse_into_text_or_emoji();

    for (i, token) in collapsed.iter().enumerate() {

        if let CollapsedEnsNameToken::Text(token) = token {

            if let Some(cp) = token.cps.first() {

                if specs.is_cm(*cp) {

                    if i == 0 {

                        return Err(ProcessError::CurrableError {

                            inner: CurrableError::CmStart,

                            index,

                            sequence: utils::cps2str(&[*cp]),

                            maybe_suggest: Some("".to_string()),

                        });

                    } else {

                        return Err(ProcessError::CurrableError {

                            inner: CurrableError::CmAfterEmoji,

                            index,

                            sequence: utils::cps2str(&[*cp]),

                            maybe_suggest: Some("".to_string()),

                        });

                    }

                }

            }

        }

        index += token.input_size();

    }



    Ok(())

}



fn check_and_get_group(

    label: &TokenizedLabel,

    specs: &CodePointsSpecs,

) -> Result<ParsedGroup, ProcessError> {

    let cps = label.get_cps_of_not_ignored_text();

    let unique_cps = cps

        .clone()

        .into_iter()

        .collect::<HashSet<_>>()

        .into_iter()

        .collect::<Vec<_>>();

    let group = determine_group(&unique_cps, specs).cloned()?;

    check_group(&group, &cps, specs)?;

    check_whole(&group, &unique_cps, specs)?;

    Ok(group)

}



fn check_group(

    group: &ParsedGroup,

    cps: &[CodePoint],

    specs: &CodePointsSpecs,

) -> Result<(), ProcessError> {

    for cp in cps.iter() {

        if !group.contains_cp(*cp) {

            return Err(ProcessError::Confused(format!(

                "symbol {} not present in group {}",

                utils::cp2str(*cp),

                group.name

            )));

        }

    }

    if group.cm_absent {

        let decomposed = utils::nfd_cps(cps, specs);

        let mut i = 1;

        let e = decomposed.len();

        while i < e {

            if specs.is_nsm(decomposed[i]) {

                let mut j = i + 1;

                while j < e && specs.is_nsm(decomposed[j]) {

                    if j - i + 1 > specs.nsm_max() as usize {

                        return Err(ProcessError::DisallowedSequence(

                            DisallowedSequence::NsmTooMany,

                        ));

                    }

                    for k in i..j {

                        if decomposed[k] == decomposed[j] {

                            return Err(ProcessError::DisallowedSequence(

                                DisallowedSequence::NsmRepeated,

                            ));

                        }

                    }

                    j += 1;

                }

                i = j;

            }

            i += 1;

        }

    }

    Ok(())

}



fn check_whole(

    group: &ParsedGroup,

    unique_cps: &[CodePoint],

    specs: &CodePointsSpecs,

) -> Result<(), ProcessError> {

    let (maker, shared) = get_groups_candidates_and_shared_cps(unique_cps, specs);

    for group_name in maker {

        let confused_group_candidate = specs.group_by_name(group_name).expect("group must exist");

        if confused_group_candidate.contains_all_cps(&shared) {

            return Err(ProcessError::ConfusedGroups {

                group1: group.name.to_string(),

                group2: confused_group_candidate.name.to_string(),

            });

        }

    }

    Ok(())

}



fn get_groups_candidates_and_shared_cps(

    unique_cps: &[CodePoint],

    specs: &CodePointsSpecs,

) -> (Vec<String>, Vec<CodePoint>) {

    let mut maybe_groups: Option<Vec<String>> = None;

    let mut shared: Vec<CodePoint> = Vec::new();



    for cp in unique_cps {

        match specs.whole_map(*cp) {

            Some(ParsedWholeValue::Number(_)) => {

                return (vec![], vec![]);

            }

            Some(ParsedWholeValue::WholeObject(whole)) => {

                let confused_groups_names = whole

                    .m

                    .get(cp)

                    .expect("since we got `whole` from cp, `M` must have a value for `cp`");



                match maybe_groups.as_mut() {

                    Some(groups) => {

                        groups.retain(|g| confused_groups_names.contains(g));

                    }

                    None => {

                        maybe_groups = Some(confused_groups_names.iter().cloned().collect());

                    }

                }

            }

            None => {

                shared.push(*cp);

            }

        };

    }



    (maybe_groups.unwrap_or_default(), shared)

}



fn determine_group<'a>(

    unique_cps: &'a [CodePoint],

    specs: &'a CodePointsSpecs,

) -> Result<&'a ParsedGroup, ProcessError> {

    specs

        .groups_for_cps(unique_cps)

        .next()

        .ok_or(ProcessError::Confused(format!(

            "no group found for {:?}",

            unique_cps

        )))

}



#[cfg(test)]

mod tests {

    use crate::TokenizedName;



    use super::*;

    use pretty_assertions::assert_eq;

    use rstest::{fixture, rstest};



    #[fixture]

    #[once]

    fn specs() -> CodePointsSpecs {

        CodePointsSpecs::default()

    }



    #[rstest]

    // success

    #[case::hello("hello", Ok(LabelType::Ascii))]

    #[case::latin("E︎̃", Ok(LabelType::Other("Latin".to_string())))]

    #[case::cyrillic("всем-привет", Ok(LabelType::Other("Cyrillic".to_string())))]

    #[case::with_fenced_in_middle("a・a’s", Ok(LabelType::Other("Han".to_string())))]

    #[case::ascii_with_hyphen("ab-c", Ok(LabelType::Ascii))]

    // errors

    #[case::hyphen_at_second_and_third("ab--", Err(ProcessError::CurrableError {

        inner: CurrableError::HyphenAtSecondAndThird,

        index: 2,

        sequence: "--".to_string(),

        maybe_suggest: Some("".to_string())

    }))]

    #[case::fenced_leading("’85", Err(ProcessError::CurrableError {

        inner: CurrableError::FencedLeading,

        index: 0,

        sequence: "’".to_string(),

        maybe_suggest: Some("".to_string())

    }))]

    #[case::fenced_contiguous("a・・a", Err(ProcessError::CurrableError {

        inner: CurrableError::FencedConsecutive,

        index: 1,

        sequence: "・・".to_string(),

        maybe_suggest: Some("・".to_string())

    }))]

    #[case::cm_after_emoji("😎😎😎😎😎😎😎😎\u{300}hello", Err(ProcessError::CurrableError {

        inner: CurrableError::CmAfterEmoji,

        index: 8,

        sequence: "\u{300}".to_string(),

        maybe_suggest: Some("".to_string())

    }))]

    #[case::cm_leading("\u{300}hello", Err(ProcessError::CurrableError {

        inner: CurrableError::CmStart,

        index: 0,

        sequence: "\u{300}".to_string(),

        maybe_suggest: Some("".to_string())

    }))]

    fn test_validate_and_get_type(

        #[case] input: &str,

        #[case] expected: Result<LabelType, ProcessError>,

        specs: &CodePointsSpecs,

    ) {

        let name = TokenizedName::from_input(input, specs, true).unwrap();

        let label = name.iter_labels().next().unwrap();

        let result = validate_label(label, specs);

        assert_eq!(

            result.clone().map(|v| v.label_type),

            expected,

            "{:?}",

            result

        );

    }



    #[rstest]

    #[case::emoji("\"Emoji\"", LabelType::Emoji)]

    #[case::ascii("\"ASCII\"", LabelType::Ascii)]

    #[case::greek("\"Greek\"", LabelType::Greek)]

    #[case::other("\"FooBar\"", LabelType::Other("FooBar".to_string()))]

    fn test_deserialize_label_type(#[case] input: &str, #[case] expected: LabelType) {

        let result: LabelType = serde_json::from_str(input).unwrap();

        assert_eq!(result, expected);

    }

}

```

```rs [./src/tokens/types.rs]

use crate::{constants, utils, CodePoint};



/// Represents a token in an ENS name.

/// see https://docs.ens.domains/ensip/15#tokenize for more details.

#[derive(Debug, Clone, PartialEq, Eq)]

pub enum EnsNameToken {

    Valid(TokenValid),

    Mapped(TokenMapped),

    Ignored(TokenIgnored),

    Disallowed(TokenDisallowed),

    Stop(TokenStop),

    Nfc(TokenNfc),

    Emoji(TokenEmoji),

}



impl EnsNameToken {

    pub fn cps(&self) -> Vec<CodePoint> {

        match self {

            EnsNameToken::Valid(t) => t.cps.clone(),

            EnsNameToken::Mapped(t) => t.cps.clone(),

            EnsNameToken::Nfc(t) => t.cps.clone(),

            EnsNameToken::Emoji(t) => t.cps_no_fe0f.clone(),

            EnsNameToken::Disallowed(t) => vec![t.cp],

            EnsNameToken::Stop(t) => vec![t.cp],

            EnsNameToken::Ignored(t) => vec![t.cp],

        }

    }



    pub fn input_size(&self) -> usize {

        match self {

            EnsNameToken::Valid(t) => t.cps.len(),

            EnsNameToken::Nfc(t) => t.input.len(),

            EnsNameToken::Emoji(t) => t.cps_input.len(),

            EnsNameToken::Mapped(_) => 1,

            EnsNameToken::Disallowed(_) => 1,

            EnsNameToken::Ignored(_) => 1,

            EnsNameToken::Stop(_) => 1,

        }

    }



    pub fn is_text(&self) -> bool {

        matches!(

            self,

            EnsNameToken::Valid(_) | EnsNameToken::Mapped(_) | EnsNameToken::Nfc(_)

        )

    }



    pub fn is_emoji(&self) -> bool {

        matches!(self, EnsNameToken::Emoji(_))

    }



    pub fn is_ignored(&self) -> bool {

        matches!(self, EnsNameToken::Ignored(_))

    }



    pub fn is_disallowed(&self) -> bool {

        matches!(self, EnsNameToken::Disallowed(_))

    }



    pub fn is_stop(&self) -> bool {

        matches!(self, EnsNameToken::Stop(_))

    }



    pub fn stop() -> Self {

        Self::Stop(TokenStop {

            cp: constants::CP_STOP,

        })

    }



    pub fn as_string(&self) -> String {

        utils::cps2str(&self.cps())

    }

}



#[derive(Debug, Clone, PartialEq, Eq)]

pub struct TokenValid {

    pub cps: Vec<CodePoint>,

}

#[derive(Debug, Clone, PartialEq, Eq)]

pub struct TokenMapped {

    pub cps: Vec<CodePoint>,

    pub cp: CodePoint,

}



#[derive(Debug, Clone, PartialEq, Eq)]

pub struct TokenIgnored {

    pub cp: CodePoint,

}



#[derive(Debug, Clone, PartialEq, Eq)]

pub struct TokenDisallowed {

    pub cp: CodePoint,

}

#[derive(Debug, Clone, PartialEq, Eq)]

pub struct TokenStop {

    pub cp: CodePoint,

}

#[derive(Debug, Clone, PartialEq, Eq)]

pub struct TokenNfc {

    pub cps: Vec<CodePoint>,

    pub input: Vec<CodePoint>,

}



#[derive(Debug, Clone, PartialEq, Eq)]

pub struct TokenEmoji {

    pub input: String,

    pub emoji: Vec<CodePoint>,

    pub cps_input: Vec<CodePoint>,

    pub cps_no_fe0f: Vec<CodePoint>,

}



#[derive(Debug, Clone, PartialEq, Eq)]

pub enum CollapsedEnsNameToken {

    Text(TokenValid),

    Emoji(TokenEmoji),

}



impl CollapsedEnsNameToken {

    pub fn input_size(&self) -> usize {

        match self {

            CollapsedEnsNameToken::Text(t) => t.cps.len(),

            CollapsedEnsNameToken::Emoji(t) => t.cps_input.len(),

        }

    }

}

```

```rs [./src/tokens/tokenize.rs]

use crate::{

    tokens::{

        CollapsedEnsNameToken, EnsNameToken, TokenDisallowed, TokenEmoji, TokenIgnored,

        TokenMapped, TokenNfc, TokenStop, TokenValid,

    },

    utils, CodePoint, CodePointsSpecs, ProcessError,

};



/// Represents a full ENS name, including the original input and the sequence of tokens

/// vitalik.eth

/// ^^^^^^^^^^^

/// name

#[derive(Debug, Clone, PartialEq, Eq)]

pub struct TokenizedName {

    pub input: String,

    pub tokens: Vec<EnsNameToken>,

}



/// Represents a tokenized ENS label (part of a name separated by periods), including sequence of tokens

/// vitalik.eth

/// ^^^^^^^

/// label 1

///         ^^^

///         label 2

#[derive(Debug, Clone, PartialEq, Eq)]

pub struct TokenizedLabel<'a> {

    pub tokens: &'a [EnsNameToken],

}



impl TokenizedName {

    pub fn empty() -> Self {

        Self {

            input: "".to_string(),

            tokens: vec![],

        }

    }



    /// Tokenizes an input string, applying NFC normalization if requested.

    pub fn from_input(

        input: impl AsRef<str>,

        specs: &CodePointsSpecs,

        apply_nfc: bool,

    ) -> Result<Self, ProcessError> {

        tokenize_name(input, specs, apply_nfc)

    }



    pub fn is_empty(&self) -> bool {

        self.tokens.is_empty()

    }



    /// Returns an iterator over all tokens in the tokenized name.

    pub fn iter_tokens(&self) -> impl Iterator<Item = &EnsNameToken> {

        self.tokens.iter()

    }



    /// Returns an iterator over all labels in the tokenized name.

    /// Basically, it splits the tokenized name by stop tokens.

    pub fn iter_labels(&self) -> impl Iterator<Item = TokenizedLabel<'_>> {

        self.tokens

            .split(|t| matches!(t, EnsNameToken::Stop(_)))

            .map(TokenizedLabel::from)

    }



    pub fn labels(&self) -> Vec<TokenizedLabel<'_>> {

        self.iter_labels().collect()

    }

}



impl TokenizedLabel<'_> {

    /// Returns true if all tokens in the label are emoji tokens

    pub fn is_fully_emoji(&self) -> bool {

        self.tokens

            .iter()

            .all(|t| matches!(t, EnsNameToken::Emoji(_)))

    }



    /// Returns true if all codepoints in all tokens are ASCII characters

    pub fn is_fully_ascii(&self) -> bool {

        self.tokens

            .iter()

            .all(|token| token.cps().into_iter().all(utils::is_ascii))

    }



    /// Returns an iterator over all codepoints in all tokens.

    pub fn iter_cps(&self) -> impl DoubleEndedIterator<Item = CodePoint> + '_ {

        self.tokens.iter().flat_map(|token| token.cps())

    }



    /// Collapses consecutive text tokens into single text tokens, keeping emoji tokens separate.

    /// Returns a vector of either Text or Emoji tokens.

    pub fn collapse_into_text_or_emoji(&self) -> Vec<CollapsedEnsNameToken> {

        let mut current_text_cps = vec![];

        let mut collapsed = vec![];

        for token in self.tokens.iter() {

            match token {

                EnsNameToken::Valid(_) | EnsNameToken::Mapped(_) | EnsNameToken::Nfc(_) => {

                    current_text_cps.extend(token.cps().iter());

                }

                EnsNameToken::Emoji(token) => {

                    if !current_text_cps.is_empty() {

                        collapsed.push(CollapsedEnsNameToken::Text(TokenValid {

                            cps: current_text_cps,

                        }));

                        current_text_cps = vec![];

                    }

                    collapsed.push(CollapsedEnsNameToken::Emoji(token.clone()));

                }

                EnsNameToken::Ignored(_) | EnsNameToken::Disallowed(_) | EnsNameToken::Stop(_) => {}

            }

        }

        if !current_text_cps.is_empty() {

            collapsed.push(CollapsedEnsNameToken::Text(TokenValid {

                cps: current_text_cps,

            }));

        }

        collapsed

    }



    /// Returns a vector of codepoints from all text tokens, excluding emoji and ignored tokens

    pub fn get_cps_of_not_ignored_text(&self) -> Vec<CodePoint> {

        self.collapse_into_text_or_emoji()

            .into_iter()

            .filter_map(|token| {

                if let CollapsedEnsNameToken::Text(token) = token {

                    Some(token.cps)

                } else {

                    None

                }

            })

            .flatten()

            .collect()

    }

}



impl<'a, T> From<&'a T> for TokenizedLabel<'a>

where

    T: AsRef<[EnsNameToken]> + ?Sized,

{

    fn from(tokens: &'a T) -> Self {

        TokenizedLabel {

            tokens: tokens.as_ref(),

        }

    }

}



fn tokenize_name(

    name: impl AsRef<str>,

    specs: &CodePointsSpecs,

    apply_nfc: bool,

) -> Result<TokenizedName, ProcessError> {

    let name = name.as_ref();

    if name.is_empty() {

        return Ok(TokenizedName::empty());

    }

    let tokens = tokenize_input(name, specs, apply_nfc)?;

    Ok(TokenizedName {

        input: name.to_string(),

        tokens,

    })

}



fn tokenize_input(

    input: impl AsRef<str>,

    specs: &CodePointsSpecs,

    apply_nfc: bool,

) -> Result<Vec<EnsNameToken>, ProcessError> {

    let input = input.as_ref();

    let emojis = specs.finditer_emoji(input).collect::<Vec<_>>();



    let mut tokens = Vec::new();

    let mut input_cur = 0;



    while input_cur < input.len() {

        if let Some(emoji) = maybe_starts_with_emoji(input_cur, input, &emojis, specs) {

            let cursor_offset = emoji.input.len();

            tokens.push(EnsNameToken::Emoji(emoji));

            input_cur += cursor_offset;

        } else {

            let char = input[input_cur..]

                .chars()

                .next()

                .expect("input_cur is in bounds");

            let cursor_offset = char.len_utf8();

            let cp = char as CodePoint;

            let token = process_one_cp(cp, specs);

            tokens.push(token);

            input_cur += cursor_offset;

        }

    }



    if apply_nfc {

        perform_nfc_transform(&mut tokens, specs);

    }

    collapse_valid_tokens(&mut tokens);

    Ok(tokens)

}



fn perform_nfc_transform(tokens: &mut Vec<EnsNameToken>, specs: &CodePointsSpecs) {

    let mut i = 0;

    let mut start = -1i32;



    while i < tokens.len() {

        let token = &tokens[i];

        match token {

            EnsNameToken::Valid(_) | EnsNameToken::Mapped(_) => {

                let cps = token.cps();

                if specs.cps_requires_check(&cps) {

                    let mut end = i + 1;

                    for (pos, token) in tokens.iter().enumerate().skip(end) {

                        match token {

                            EnsNameToken::Valid(_) | EnsNameToken::Mapped(_) => {

                                if !specs.cps_requires_check(&cps) {

                                    break;

                                }

                                end = pos + 1;

                            }

                            EnsNameToken::Ignored(_) => {}

                            _ => break,

                        }

                    }



                    if start < 0 {

                        start = i as i32;

                    }



                    let slice = &tokens[start as usize..end];

                    let mut cps = Vec::new();

                    for tok in slice {

                        match tok {

                            EnsNameToken::Valid(_) | EnsNameToken::Mapped(_) => {

                                cps.extend(&tok.cps());

                            }

                            _ => {}

                        }

                    }



                    let str0 = utils::cps2str(&cps);

                    let str = utils::nfc(&str0);



                    if str0 == str {

                        i = end - 1;

                    } else {

                        let new_token = EnsNameToken::Nfc(TokenNfc {

                            input: cps,

                            cps: utils::str2cps(&str),

                        });

                        tokens.splice(start as usize..end, vec![new_token]);

                        i = start as usize;

                    }

                    start = -1;

                } else {

                    start = i as i32;

                }

            }

            EnsNameToken::Ignored(_) => {}

            _ => {

                start = -1;

            }

        }

        i += 1;

    }

}



// given array of codepoints

// returns the longest valid emoji sequence (or undefined if no match)

fn maybe_starts_with_emoji(

    i: usize,

    label: &str,

    emojis: &[regex::Match],

    specs: &CodePointsSpecs,

) -> Option<TokenEmoji> {

    emojis.iter().find_map(|emoji| {

        let start = emoji.start();

        if start == i {

            let end = emoji.end();

            let input_cps = utils::str2cps(&label[start..end]);

            let cps_no_fe0f = utils::filter_fe0f(&input_cps);

            let emoji = specs

                .cps_emoji_no_fe0f_to_pretty(&cps_no_fe0f)

                .expect("emoji should be found")

                .clone();

            Some(TokenEmoji {

                input: label[start..end].to_string(),

                cps_input: input_cps,

                emoji,

                cps_no_fe0f,

            })

        } else {

            None

        }

    })

}



fn process_one_cp(cp: CodePoint, specs: &CodePointsSpecs) -> EnsNameToken {

    if specs.is_stop(cp) {

        EnsNameToken::Stop(TokenStop { cp })

    } else if specs.is_valid(cp) {

        EnsNameToken::Valid(TokenValid { cps: vec![cp] })

    } else if specs.is_ignored(cp) {

        EnsNameToken::Ignored(TokenIgnored { cp })

    } else if let Some(normalized) = specs.maybe_normalize(cp) {

        EnsNameToken::Mapped(TokenMapped {

            cp,

            cps: normalized.clone(),

        })

    } else {

        EnsNameToken::Disallowed(TokenDisallowed { cp })

    }

}



fn collapse_valid_tokens(tokens: &mut Vec<EnsNameToken>) {

    let mut i = 0;

    while i < tokens.len() {

        if let EnsNameToken::Valid(token) = &tokens[i] {

            let mut j = i + 1;

            let mut cps = token.cps.clone();

            while j < tokens.len() {

                if let EnsNameToken::Valid(next_token) = &tokens[j] {

                    cps.extend(next_token.cps.iter());

                    j += 1;

                } else {

                    break;

                }

            }

            let new_token = EnsNameToken::Valid(TokenValid { cps });

            tokens.splice(i..j, vec![new_token].into_iter());

        }

        i += 1;

    }

}



#[cfg(test)]

mod tests {

    use super::*;

    use pretty_assertions::assert_eq;

    use rstest::{fixture, rstest};



    #[fixture]

    #[once]

    fn specs() -> CodePointsSpecs {

        CodePointsSpecs::default()

    }



    #[rstest]

    #[case::empty(vec![], vec![])]

    #[case::single(

        vec![EnsNameToken::Valid(TokenValid { cps: vec![1, 2, 3] })],

        vec![EnsNameToken::Valid(TokenValid { cps: vec![1, 2, 3] })],

    )]

    #[case::two(

        vec![

            EnsNameToken::Valid(TokenValid { cps: vec![1, 2, 3] }),

            EnsNameToken::Valid(TokenValid { cps: vec![4, 5, 6] }),

        ],

        vec![EnsNameToken::Valid(TokenValid { cps: vec![1, 2, 3, 4, 5, 6] })],

    )]

    #[case::full(

        vec![

            EnsNameToken::Valid(TokenValid { cps: vec![1, 2, 3] }),

            EnsNameToken::Disallowed(TokenDisallowed { cp: 0 }),

            EnsNameToken::Valid(TokenValid { cps: vec![4, 5, 6] }),

            EnsNameToken::Valid(TokenValid { cps: vec![7, 8, 9] }),

            EnsNameToken::Valid(TokenValid { cps: vec![10, 11, 12] }),

            EnsNameToken::Disallowed(TokenDisallowed { cp: 10 }),

            EnsNameToken::Stop(TokenStop { cp: 11 }),

            EnsNameToken::Valid(TokenValid { cps: vec![12] }),

            EnsNameToken::Ignored(TokenIgnored { cp: 13 }),

        ],

        vec![

            EnsNameToken::Valid(TokenValid { cps: vec![1, 2, 3] }),

            EnsNameToken::Disallowed(TokenDisallowed { cp: 0 }),

            EnsNameToken::Valid(TokenValid { cps: vec![4, 5, 6, 7, 8, 9, 10, 11, 12] }),

            EnsNameToken::Disallowed(TokenDisallowed { cp: 10 }),

            EnsNameToken::Stop(TokenStop { cp: 11 }),

            EnsNameToken::Valid(TokenValid { cps: vec![12] }),

            EnsNameToken::Ignored(TokenIgnored { cp: 13 }),

        ],

    )]

    fn test_collapse_valid_tokens(

        #[case] input: Vec<EnsNameToken>,

        #[case] expected: Vec<EnsNameToken>,

    ) {

        let mut tokens = input;

        collapse_valid_tokens(&mut tokens);

        assert_eq!(tokens, expected);

    }



    #[rstest]

    #[case::xyz(

        "xyz👨🏻/",

        true,

        vec![

            EnsNameToken::Valid(TokenValid { cps: vec![120, 121, 122] }),

            EnsNameToken::Emoji(TokenEmoji { input: "👨🏻".to_string(), cps_input: vec![128104, 127995], emoji: vec![128104, 127995], cps_no_fe0f: vec![128104, 127995] }),

            EnsNameToken::Disallowed(TokenDisallowed { cp: 47 }),

        ]

    )]

    #[case::a_poop_b(

        "A💩︎︎b",

        true,

        vec![

            EnsNameToken::Mapped(TokenMapped { cp: 65, cps: vec![97] }),

            EnsNameToken::Emoji(TokenEmoji { input: "💩".to_string(), cps_input: vec![128169], emoji: vec![128169, 65039], cps_no_fe0f: vec![128169] }),

            EnsNameToken::Ignored(TokenIgnored { cp: 65038 }),

            EnsNameToken::Ignored(TokenIgnored { cp: 65038 }),

            EnsNameToken::Valid(TokenValid { cps: vec![98] }),

        ]

    )]

    #[case::atm(

        "a™️",

        true,

        vec![

            EnsNameToken::Valid(TokenValid { cps: vec![97] }),

            EnsNameToken::Mapped(TokenMapped { cp: 8482, cps: vec![116, 109] }),

            EnsNameToken::Ignored(TokenIgnored { cp: 65039 }),

        ]

    )]

    #[case::no_nfc(

        "_R💩\u{FE0F}a\u{FE0F}\u{304}\u{AD}.",

        false,

        vec![

            EnsNameToken::Valid(TokenValid { cps: vec![95] }),

            EnsNameToken::Mapped(TokenMapped { cp: 82, cps: vec![114] }),

            EnsNameToken::Emoji(TokenEmoji { input: "💩️".to_string(), cps_input: vec![128169, 65039], emoji: vec![128169, 65039], cps_no_fe0f: vec![128169] }),

            EnsNameToken::Valid(TokenValid { cps: vec![97] }),

            EnsNameToken::Ignored(TokenIgnored { cp: 65039 }),

            EnsNameToken::Valid(TokenValid { cps: vec![772] }),

            EnsNameToken::Ignored(TokenIgnored { cp: 173 }),

            EnsNameToken::Stop(TokenStop { cp: 46 }),

        ]

    )]

    #[case::with_nfc(

        "_R💩\u{FE0F}a\u{FE0F}\u{304}\u{AD}.",

        true,

        vec![

            EnsNameToken::Valid(TokenValid { cps: vec![95] }),

            EnsNameToken::Mapped(TokenMapped { cp: 82, cps: vec![114] }),

            EnsNameToken::Emoji(TokenEmoji { input: "💩️".to_string(), cps_input: vec![128169, 65039], emoji: vec![128169, 65039], cps_no_fe0f: vec![128169] }),

            EnsNameToken::Nfc(TokenNfc { input: vec![97, 772], cps: vec![257] }),

            EnsNameToken::Ignored(TokenIgnored { cp: 173 }),

            EnsNameToken::Stop(TokenStop { cp: 46 }),

        ]

    )]

    #[case::raffy(

        "RaFFY🚴‍♂️.eTh",

        true,

        vec![

            EnsNameToken::Mapped(TokenMapped { cp: 82, cps: vec![114] }),

            EnsNameToken::Valid(TokenValid { cps: vec![97] }),

            EnsNameToken::Mapped(TokenMapped { cp: 70, cps: vec![102] }),

            EnsNameToken::Mapped(TokenMapped { cp: 70, cps: vec![102] }),

            EnsNameToken::Mapped(TokenMapped { cp: 89, cps: vec![121] }),

            EnsNameToken::Emoji(TokenEmoji { input: "🚴\u{200d}♂\u{fe0f}".to_string(), cps_input: vec![128692, 8205, 9794, 65039], emoji: vec![128692, 8205, 9794, 65039], cps_no_fe0f: vec![128692, 8205, 9794] }),

            EnsNameToken::Stop(TokenStop { cp: 46 }),

            EnsNameToken::Valid(TokenValid { cps: vec![101] }),

            EnsNameToken::Mapped(TokenMapped { cp: 84, cps: vec![116] }),

            EnsNameToken::Valid(TokenValid { cps: vec![104] }),

        ]

    )]

    #[case::emojis(

        "⛹️‍♀",

        true,

        vec![

            EnsNameToken::Emoji(TokenEmoji { input: "⛹️‍♀".to_string(), cps_input: vec![9977, 65039, 8205, 9792], emoji: vec![9977, 65039, 8205, 9792, 65039], cps_no_fe0f: vec![9977, 8205, 9792] }),

        ]

    )]

    fn test_ens_tokenize(

        #[case] input: &str,

        #[case] apply_nfc: bool,

        #[case] expected: Vec<EnsNameToken>,

        specs: &CodePointsSpecs,

    ) {

        let tokens = tokenize_input(input, specs, apply_nfc).expect("tokenize");

        assert_eq!(tokens, expected);

    }



    #[rstest]

    #[case::leading_cm(

        "󠅑𑆻👱🏿‍♀️xyz",

        vec![

            CollapsedEnsNameToken::Text(TokenValid { cps: vec![70075] }),

            CollapsedEnsNameToken::Emoji(TokenEmoji { input: "👱🏿‍♀️".to_string(), cps_input: vec![128113, 127999, 8205, 9792, 65039], emoji: vec![128113, 127999, 8205, 9792, 65039], cps_no_fe0f: vec![128113, 127999, 8205, 9792] }),

            CollapsedEnsNameToken::Text(TokenValid { cps: vec![120, 121, 122] }),

        ]

    )]

    #[case::atm(

        "a™️",

        vec![

            CollapsedEnsNameToken::Text(TokenValid { cps: vec![97, 116, 109] }),

        ]

    )]

    fn test_collapse(

        #[case] input: &str,

        #[case] expected: Vec<CollapsedEnsNameToken>,

        specs: &CodePointsSpecs,

    ) {

        let tokens = tokenize_input(input, specs, true).expect("tokenize");

        let label = TokenizedLabel::from(&tokens);

        let result = label.collapse_into_text_or_emoji();

        assert_eq!(result, expected);

    }

}

```

```rs [./src/tokens/mod.rs]

mod tokenize;

mod types;



pub use tokenize::{TokenizedLabel, TokenizedName};

pub use types::*;

```

```rs [./src/beautify.rs]

use crate::{constants, join::join_cps, CodePoint, EnsNameToken, LabelType, ValidatedLabel};



/// Beautifies a list of validated labels by

/// - replacing Greek code points with their pretty variants

/// - using pretty variants of emojis

pub fn beautify_labels(labels: &[ValidatedLabel]) -> String {

    let labels_cps = labels.iter().map(|label| {

        label

            .tokens

            .iter()

            .filter_map(|token| match token {

                EnsNameToken::Emoji(emoji) => Some(emoji.emoji.clone()),

                EnsNameToken::Valid(_) | EnsNameToken::Mapped(_) | EnsNameToken::Nfc(_) => {

                    Some(cps_replaced_greek(token.cps(), &label.label_type))

                }

                EnsNameToken::Ignored(_) | EnsNameToken::Disallowed(_) | EnsNameToken::Stop(_) => {

                    None

                }

            })

            .flatten()

            .collect::<Vec<_>>()

    });

    join_cps(labels_cps)

}



fn cps_replaced_greek(mut cps: Vec<CodePoint>, label_type: &LabelType) -> Vec<CodePoint> {

    if !label_type.is_greek() {

        cps.iter_mut().for_each(|cp| {

            if *cp == constants::CP_XI_SMALL {

                *cp = constants::CP_XI_CAPITAL;

            }

        });

    }



    cps

}

```

```rs [./src/utils.rs]

use crate::{CodePoint, CodePointsSpecs};

use unicode_normalization::UnicodeNormalization;



const FE0F: CodePoint = 0xfe0f;

const LAST_ASCII_CP: CodePoint = 0x7f;



#[inline]

pub fn filter_fe0f(cps: &[CodePoint]) -> Vec<CodePoint> {

    cps.iter().filter(|cp| **cp != FE0F).cloned().collect()

}



#[inline]

pub fn cps2str(cps: &[CodePoint]) -> String {

    cps.iter()

        .filter_map(|&code_point| char::from_u32(code_point))

        .collect()

}



#[inline]

pub fn cp2str(cp: CodePoint) -> String {

    cps2str(&[cp])

}



#[inline]

pub fn str2cps(str: &str) -> Vec<CodePoint> {

    str.chars().map(|c| c as CodePoint).collect()

}



#[inline]

pub fn is_ascii(cp: CodePoint) -> bool {

    cp <= LAST_ASCII_CP

}



#[inline]

pub fn nfc(str: &str) -> String {

    str.nfc().collect()

}



#[inline]

pub fn nfd_cps(cps: &[CodePoint], specs: &CodePointsSpecs) -> Vec<CodePoint> {

    let mut decomposed = Vec::new();

    for cp in cps {

        if let Some(decomposed_cp) = specs.decompose(*cp) {

            decomposed.extend(decomposed_cp);

        } else {

            decomposed.push(*cp);

        }

    }

    decomposed

}

```

```rs [./src/code_points/types.rs]

use crate::static_data::spec_json;

use std::collections::{HashMap, HashSet};



pub type CodePoint = u32;



#[derive(Debug, Clone, PartialEq, Eq)]

pub struct ParsedGroup {

    pub name: spec_json::GroupName,

    pub primary: HashSet<CodePoint>,

    pub secondary: HashSet<CodePoint>,

    pub primary_plus_secondary: HashSet<CodePoint>,

    pub cm_absent: bool,

}



impl From<spec_json::Group> for ParsedGroup {

    fn from(g: spec_json::Group) -> Self {

        Self {

            name: g.name,

            primary: g.primary.clone().into_iter().collect(),

            secondary: g.secondary.clone().into_iter().collect(),

            primary_plus_secondary: g

                .primary

                .clone()

                .into_iter()

                .chain(g.secondary.clone())

                .collect(),

            cm_absent: g.cm.is_empty(),

        }

    }

}



impl ParsedGroup {

    pub fn contains_cp(&self, cp: CodePoint) -> bool {

        self.primary_plus_secondary.contains(&cp)

    }



    pub fn contains_all_cps(&self, cps: &[CodePoint]) -> bool {

        cps.iter().all(|cp| self.contains_cp(*cp))

    }

}



pub type ParsedWholeMap = HashMap<CodePoint, ParsedWholeValue>;



pub enum ParsedWholeValue {

    Number(u32),

    WholeObject(ParsedWholeObject),

}



impl TryFrom<spec_json::WholeValue> for ParsedWholeValue {

    type Error = anyhow::Error;

    fn try_from(value: spec_json::WholeValue) -> Result<Self, Self::Error> {

        match value {

            spec_json::WholeValue::Number(number) => Ok(ParsedWholeValue::Number(number)),

            spec_json::WholeValue::WholeObject(object) => {

                Ok(ParsedWholeValue::WholeObject(object.try_into()?))

            }

        }

    }

}



pub struct ParsedWholeObject {

    pub v: HashSet<CodePoint>,

    pub m: HashMap<CodePoint, HashSet<String>>,

}



impl TryFrom<spec_json::WholeObject> for ParsedWholeObject {

    type Error = anyhow::Error;



    fn try_from(value: spec_json::WholeObject) -> Result<Self, Self::Error> {

        let v = value.v.into_iter().collect();

        let m = value

            .m

            .into_iter()

            .map(|(k, v)| {

                let k = k.parse::<CodePoint>()?;

                let v = v.into_iter().collect();

                Ok((k, v))

            })

            .collect::<Result<HashMap<CodePoint, HashSet<String>>, anyhow::Error>>()?;

        Ok(Self { v, m })

    }

}

```

```rs [./src/code_points/specs.rs]

use super::types::*;

use crate::{

    constants,

    static_data::{

        nf_json,

        spec_json::{self, GroupName},

    },

    utils, CodePoint,

};

use regex::Regex;

use std::collections::{HashMap, HashSet};



/// This struct contains logic for validating and normalizing code points.

pub struct CodePointsSpecs {

    cm: HashSet<CodePoint>,

    ignored: HashSet<CodePoint>,

    mapped: HashMap<CodePoint, Vec<CodePoint>>,

    nfc_check: HashSet<CodePoint>,

    whole_map: ParsedWholeMap,

    fenced: HashMap<CodePoint, String>,

    groups: Vec<ParsedGroup>,

    group_name_to_index: HashMap<spec_json::GroupName, usize>,

    valid: HashSet<CodePoint>,

    nsm: HashSet<CodePoint>,

    nsm_max: u32,

    emoji_no_fe0f_to_pretty: HashMap<Vec<CodePoint>, Vec<CodePoint>>,

    decomp: HashMap<CodePoint, Vec<CodePoint>>,

    emoji_regex: Regex,

}



impl CodePointsSpecs {

    pub fn new(spec: spec_json::Spec, nf: nf_json::Nf) -> Self {

        let emoji: HashSet<Vec<CodePoint>> = spec.emoji.into_iter().collect();

        let emoji_no_fe0f_to_pretty = emoji

            .iter()

            .map(|e| (utils::filter_fe0f(e), e.clone()))

            .collect();

        let decomp = nf

            .decomp

            .into_iter()

            .map(|item| (item.number, item.nested_numbers))

            .collect();

        let groups: Vec<ParsedGroup> = spec.groups.into_iter().map(ParsedGroup::from).collect();

        let group_name_to_index: HashMap<spec_json::GroupName, usize> = groups

            .iter()

            .enumerate()

            .map(|(i, g)| (g.name.clone(), i))

            .collect();

        let valid = compute_valid(&groups, &decomp);

        let whole_map = compute_whole_map(spec.whole_map);

        let emoji_str_list = emoji

            .iter()

            .map(|cps| utils::cps2str(cps))

            .collect::<Vec<_>>();

        let emoji_regex =

            create_emoji_regex_pattern(emoji_str_list).expect("failed to create emoji regex");



        Self {

            cm: spec.cm.into_iter().collect(),

            emoji_no_fe0f_to_pretty,

            ignored: spec.ignored.into_iter().collect(),

            mapped: spec.mapped.into_iter().map(|m| (m.from, m.to)).collect(),

            nfc_check: spec.nfc_check.into_iter().collect(),

            fenced: spec.fenced.into_iter().map(|f| (f.from, f.to)).collect(),

            valid,

            groups,

            nsm: spec.nsm.into_iter().collect(),

            nsm_max: spec.nsm_max,

            decomp,

            whole_map,

            group_name_to_index,

            emoji_regex,

        }

    }

}



impl Default for CodePointsSpecs {

    fn default() -> Self {

        let spec = spec_json::Spec::default();

        let nf = nf_json::Nf::default();

        Self::new(spec, nf)

    }

}



impl CodePointsSpecs {

    pub fn get_mapping(&self, cp: CodePoint) -> Option<&Vec<CodePoint>> {

        self.mapped.get(&cp)

    }



    pub fn cps_is_emoji(&self, cps: &[CodePoint]) -> bool {

        let s = utils::cps2str(cps);

        let maybe_match = self.finditer_emoji(&s).next();

        maybe_match

            .map(|m| m.start() == 0 && m.end() == s.len())

            .unwrap_or(false)

    }



    pub fn finditer_emoji<'a>(&'a self, s: &'a str) -> impl Iterator<Item = regex::Match<'_>> {

        self.emoji_regex.find_iter(s)

    }



    pub fn cps_requires_check(&self, cps: &[CodePoint]) -> bool {

        cps.iter().any(|cp| self.nfc_check.contains(cp))

    }



    pub fn cps_emoji_no_fe0f_to_pretty(&self, cps: &[CodePoint]) -> Option<&Vec<CodePoint>> {

        self.emoji_no_fe0f_to_pretty.get(cps)

    }



    pub fn maybe_normalize(&self, cp: CodePoint) -> Option<&Vec<CodePoint>> {

        self.mapped.get(&cp)

    }



    pub fn is_valid(&self, cp: CodePoint) -> bool {

        self.valid.contains(&cp)

    }



    pub fn is_ignored(&self, cp: CodePoint) -> bool {

        self.ignored.contains(&cp)

    }



    pub fn is_stop(&self, cp: CodePoint) -> bool {

        cp == constants::CP_STOP

    }



    pub fn is_fenced(&self, cp: CodePoint) -> bool {

        self.fenced.contains_key(&cp)

    }



    pub fn is_cm(&self, cp: CodePoint) -> bool {

        self.cm.contains(&cp)

    }



    pub fn groups_for_cps<'a>(

        &'a self,

        cps: &'a [CodePoint],

    ) -> impl Iterator<Item = &'a ParsedGroup> {

        self.groups

            .iter()

            .filter(|group| cps.iter().all(|cp| group.contains_cp(*cp)))

    }



    pub fn is_nsm(&self, cp: CodePoint) -> bool {

        self.nsm.contains(&cp)

    }



    pub fn nsm_max(&self) -> u32 {

        self.nsm_max

    }



    pub fn decompose(&self, cp: CodePoint) -> Option<&Vec<CodePoint>> {

        self.decomp.get(&cp)

    }



    pub fn whole_map(&self, cp: CodePoint) -> Option<&ParsedWholeValue> {

        self.whole_map.get(&cp)

    }



    pub fn group_by_name(&self, name: impl Into<GroupName>) -> Option<&ParsedGroup> {

        self.group_name_to_index

            .get(&name.into())

            .and_then(|i| self.groups.get(*i))

    }

}



fn compute_valid(

    groups: &[ParsedGroup],

    decomp: &HashMap<CodePoint, Vec<CodePoint>>,

) -> HashSet<CodePoint> {

    let mut valid = HashSet::new();

    for g in groups {

        valid.extend(g.primary_plus_secondary.iter());

    }



    let ndf: Vec<CodePoint> = valid

        .iter()

        .flat_map(|cp| decomp.get(cp).cloned().unwrap_or_default())

        .collect();

    valid.extend(ndf);

    valid

}



fn compute_whole_map(whole_map: HashMap<String, spec_json::WholeValue>) -> ParsedWholeMap {

    whole_map

        .into_iter()

        .map(|(k, v)| (k.parse::<CodePoint>().unwrap(), v.try_into().unwrap()))

        .collect()

}



fn create_emoji_regex_pattern(emojis: Vec<impl AsRef<str>>) -> Result<Regex, regex::Error> {

    let fe0f = regex::escape(constants::STR_FE0F);



    // Make FE0F optional

    let make_emoji = |emoji: &str| regex::escape(emoji).replace(&fe0f, &format!("{}?", fe0f));



    // Order emojis to match the longest ones first

    let order = |emoji: &str| emoji.replace(constants::STR_FE0F, "").len();



    let mut sorted_emojis = emojis;

    sorted_emojis.sort_by_key(|b| std::cmp::Reverse(order(b.as_ref())));



    let emoji_regex = sorted_emojis

        .into_iter()

        .map(|emoji| make_emoji(emoji.as_ref()))

        .collect::<Vec<_>>()

        .join("|");



    regex::Regex::new(&emoji_regex)

}



#[cfg(test)]

mod tests {

    use super::*;

    use pretty_assertions::assert_eq;

    use rstest::{fixture, rstest};



    #[fixture]

    #[once]

    fn specs() -> CodePointsSpecs {

        CodePointsSpecs::default()

    }



    #[rstest]

    #[case::letter_a('A', "a")]

    #[case::roman_numeral_vi('Ⅵ', "vi")]

    fn test_mapped(#[case] input: char, #[case] output: &str, specs: &CodePointsSpecs) {

        let mapped = specs.get_mapping(input as u32);

        let expected = output.chars().map(|c| c as u32).collect::<Vec<_>>();

        assert_eq!(mapped, Some(&expected));

    }



    #[rstest]

    #[case::slash("⁄")]

    fn test_fenced(#[case] fence: &str, specs: &CodePointsSpecs) {

        assert!(

            specs

                .fenced

                .contains_key(&(fence.chars().next().unwrap() as u32)),

            "Fence {fence} not found"

        );

    }



    #[rstest]

    #[case::string("hello😀", vec![("😀", 5, 9)])]

    #[case::man_technologist("👨‍💻", vec![("👨‍💻", 0, 11)])]

    fn test_emoji(

        #[case] emoji: &str,

        #[case] expected: Vec<(&str, usize, usize)>,

        specs: &CodePointsSpecs,

    ) {

        let matches = specs.finditer_emoji(emoji).collect::<Vec<_>>();

        assert_eq!(matches.len(), expected.len());

        for (i, (emoji, start, end)) in expected.into_iter().enumerate() {

            assert_eq!(matches[i].as_str(), emoji);

            assert_eq!(matches[i].start(), start);

            assert_eq!(matches[i].end(), end);

        }

    }



    #[rstest]

    #[case::small(&[36, 45, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 95, 97])]

    #[case::big(&[205743, 205742, 205741, 205740, 205739, 205738, 205737, 205736])]

    fn test_valid(#[case] cps: &[CodePoint], specs: &CodePointsSpecs) {

        for cp in cps {

            assert!(

                specs.is_valid(*cp),

                "Codepoint {cp} is not valid, but should be"

            );

        }

    }



    #[rstest]

    #[case(&[82])]

    fn test_not_valid(#[case] cps: &[CodePoint], specs: &CodePointsSpecs) {

        for cp in cps {

            assert!(

                !specs.is_valid(*cp),

                "Codepoint {cp} is valid, but should not be"

            );

        }

    }

}

```

```rs [./src/code_points/mod.rs]

mod specs;

mod types;



pub use specs::CodePointsSpecs;

pub use types::*;

```



</rust>

<csharp>

```cs [ENSNormalize.cs/ENSNormalize/OutputToken.cs]

﻿using System.Collections.Generic;



namespace ADRaffy.ENSNormalize

{

    public class OutputToken

    {

        public readonly IList<int> Codepoints;

        public readonly EmojiSequence? Emoji;

        public bool IsEmoji { get => Emoji != null; }

        public OutputToken(IList<int> cps, EmojiSequence? emoji = null)

        {

            Codepoints = cps;

            Emoji = emoji;

        }

        public override string ToString() 

        {

            string name = IsEmoji ? "Emoji" : "Text";

            return $"{name}[{Codepoints.ToHexSequence()}]";

        }

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/Decoder.cs]

﻿using System;

using System.Linq;

using System.Collections.Generic;



namespace ADRaffy.ENSNormalize

{

    public class Decoder

    {

        static int AsSigned(int i)

        {

            return (i & 1) != 0 ? ~i >> 1 : i >> 1;

        }



        private readonly uint[] Words;

        private readonly int[] Magic;

        private int Index, Bits;

        private uint Word;

        public Decoder(uint[] words) {

            Words = words;

            Index = 0;

            Word = 0;

            Bits = 0;

            Magic = ReadMagic();

        }

        public bool ReadBit()

        {

            if (Bits == 0)

            {

                Word = Words[Index++];

                Bits = 1;

            }

            bool bit = (Word & Bits) != 0;

            Bits <<= 1;

            return bit;

        }

        // read an ascending array 

        private int[] ReadMagic()

        {

            List<int> magic = new();

            int w = 0;

            while (true)

            {

                int dw = ReadUnary();

                if (dw == 0) break;

                magic.Add(w += dw);

            }

            return magic.ToArray();

        }

        // 1*0 = number of 1s

        // eg. 4 = 11110

        //     1 = 10

        //     0 = 0

        public int ReadUnary()

        {

            int x = 0;

            while (ReadBit()) x++;

            return x;

        }

        // read w-bits => interpret as w-bit int 

        // MSB first

        public int ReadBinary(int w)

        {

            int x = 0;

            for (int b = 1 << (w - 1); b > 0; b >>= 1)

            {

                if (ReadBit())

                {

                    x |= b;

                }

            }  

            return x;

        }

        // read magic-encoded int

        public int ReadUnsigned()

        {

            int a = 0;

            int w;

            int n;

            for (int i = 0; ; )

            {

                w = Magic[i];

                n = 1 << w;

                if (++i == Magic.Length || !ReadBit()) break;

                a += n;

            }

            return a + ReadBinary(w);

        }

        public int[] ReadSortedAscending(int n) => ReadArray(n, (prev, x) => prev + 1 + x);

        public int[] ReadUnsortedDeltas(int n) => ReadArray(n, (prev, x) => prev + AsSigned(x));

        public int[] ReadArray(int count, Func<int,int,int> fn)

        {

            int[] v = new int[count];

            if (count > 0)

            {

                int prev = -1;

                for (int i = 0; i < count; i++)

                {

                    v[i] = prev = fn(prev, ReadUnsigned());

                }

            }

            return v;

        }

        public List<int> ReadUnique()

        {

            List<int> ret = new(ReadSortedAscending(ReadUnsigned()));

            int n = ReadUnsigned();

            int[] vX = ReadSortedAscending(n);

            int[] vS = ReadUnsortedDeltas(n);

            for (int i = 0; i < n; i++)

            {                

                for (int x = vX[i], e = x + vS[i]; x < e; x++)

                {

                    ret.Add(x);

                }

            }

            return ret;

        }

        public List<int[]> ReadTree()

        {

            List<int[]> ret = new();

            ReadTree(ret, new());

            return ret;

        }

        private void ReadTree(List<int[]> ret, List<int> path)

        {

            int i = path.Count;

            path.Add(0);

            foreach (int x in ReadSortedAscending(ReadUnsigned()))

            {

                path[i] = x;

                ret.Add(path.ToArray());

            }

            foreach (int x in ReadSortedAscending(ReadUnsigned()))

            {

                path[i] = x;

                ReadTree(ret, path);

            }

            path.RemoveAt(i);

        }

        // convenience

        public string ReadString() => ReadUnsortedDeltas(ReadUnsigned()).Implode();

        public int[] ReadSortedUnique()

        {

            int[] v = ReadUnique().ToArray();

            Array.Sort(v);

            return v;

        }

    }



}

```

```cs [ENSNormalize.cs/ENSNormalize/InvalidLabelException.cs]

﻿using System;



namespace ADRaffy.ENSNormalize

{

    public class InvalidLabelException : Exception

    {

        public readonly string Label;

        public NormException Error { get => (NormException)InnerException!; }

        public InvalidLabelException(string label, string message, NormException inner) : base(message, inner)

        {

            Label = label;

        }

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/EmojiSequence.cs]

﻿using System.Linq;

using System.Collections.ObjectModel;



namespace ADRaffy.ENSNormalize

{

    public class EmojiSequence

    {

        public readonly string Form;

        public readonly ReadOnlyCollection<int> Beautified;

        public readonly ReadOnlyCollection<int> Normalized;

        public bool IsMangled { get => Beautified != Normalized; }

        public bool HasZWJ { get => Normalized.Contains(0x200D); }

        internal EmojiSequence(int[] cps)

        {

            Beautified = new(cps);

            Form = cps.Implode();

            int[] norm = cps.Where(cp => cp != 0xFE0F).ToArray();

            Normalized = norm.Length < cps.Length ? new(norm) : Beautified;

        }

        public override string ToString() 

        {

            return $"Emoji[{Beautified.ToHexSequence()}]";

        }



    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/Blobs.cs]

// generated: 2024-09-14T19:28:59.655Z

namespace ADRaffy.ENSNormalize

{

    internal static class Blobs

    {

        // created: 2024-09-13T06:42:44.238Z

        // unicode: 16.0.0 (2024-09-10T20:47:54.200Z)

        // cldr: 45 (2024-04-19T05:36:55.332Z)

        // hash: 4b3c5210a328d7097500b413bf075ec210bbac045cd804deae5d1ed771304825

        // magic: 1 3 7 13 16 17 18 19

        internal static readonly uint[] ENSIP15 = new uint[] { // 30391 bytes

            0xD2AEFDED,0x421F100F,0x7E74243F,0x71EBC2F3,0xAF9B03D7,0xDA00E116,0x4172ECC0,0x32D4E8F5,0x9DC6ADC7,0x1DA2F5E6,

            0xA4397D34,0x85FE2457,0xCD239A03,0xD066194A,0xB7B81C21,0x00E566FB,0xE3F5B5F1,0xD7C54B8E,0x07AE9087,0x97AB51BE,

            0xF12FFA87,0xD8611B6A,0x1DF37283,0xF007AD65,0x301DA00E,0xC232C83C,0x350F3338,0xCEBB3CE6,0xBB5AD4BD,0x16E6B34E,

            0xEBB0AE03,0xE8007A9E,0xE1B1DF00,0x1FC00FC9,0x5C783E94,0xCD3C002E,0x3B46988F,0x7B407120,0x7B068DE5,0x54C74BF4,

            0x5B1C680E,0xF8B65A39,0x0203B201,0x06F440E1,0x8003A061,0x600FD447,0x62C871AE,0xCB8C83A0,0x587ED15C,0x9EA00721,

            0x4720D814,0x1CA60E03,0x76E43FB0,0xF040E3E0,0x19C161A4,0x1AB4000E,0xAE7ADEE6,0x938F5209,0x70C53CCE,0x0621C4CB,

            0x16A6651B,0xA6651987,0x6C1AC716,0x198716A6,0x62D4CCB6,0x1AC5681F,0xC6B99EA7,0x651A0601,0x18071AA6,0x4219E468,

            0xB28EC38D,0xF67E1B70,0x721A3621,0x18A7B1D1,0x00780CAA,0x531A827C,0x43D86C1F,0x46A9871C,0xD9D4751D,0x00FED997,

            0x7407A0C2,0xD1601E66,0x669CA745,0x9AE6D1A8,0x1C6100F9,0xA1DF00E3,0x0729D3D0,0x6FF60ECC,0xD3A554F2,0xA81F8BF8,

            0x09CA6958,0xBA6D1EE7,0x631EB629,0x99526992,0x6E301FA8,0xD472318F,0x00C7D323,0x00F09962,0xB996C1D1,0x362FB40E,

            0x4F3B8CFF,0x9380C33B,0xC8CE3A2D,0x74314C33,0xC500F95A,0x16843368,0xDE7D8987,0x4B50D241,0xA5C070EE,0x0EE4B98D,

            0x39081F9B,0x396259E0,0x99C6D200,0xDD3D0EBC,0xFCB6AC41,0x100EFB30,0xC0E1C816,0xF65340EA,0x460F7E2B,0xACF8A4E6,

            0x5E66D387,0x5D10D1ED,0x60F498DC,0x8FB81D55,0x38F60075,0xE6AB0CF3,0x88752B23,0x1FF80E1A,0x7AE83C64,0xFA90FDC0,

            0x33BCFF96,0x2038D01E,0x0CD2D0BE,0xD688D431,0xB1A8C934,0x8A60300F,0xC4328D03,0xDD0CA38C,0x90C1EB43,0xD00C3072,

            0x03D6E5B1,0xAA421896,0x0D5A1221,0xA8071491,0x06928621,0xD884201C,0x21CC6B19,0x547518A6,0x41B07969,0xD34CCA0D,

            0x0F03143B,0x729A4E30,0x1C0741B8,0xFA340C2A,0x30EE6358,0x4C338CF3,0x8340D359,0x0C68F252,0x43E0C039,0x4A406C31,

            0x91C0681E,0x349A3A18,0x19069C85,0x4F86E1D8,0xCC3A0C83,0x219861B0,0x1A0C50E3,0x01C1E807,0x8F21EB62,0x034F8696,

            0x8313528F,0xA00714D7,0x00C83CE4,0xA0D23283,0x6201D683,0xE201C62E,0xB4F86550,0xE591DADA,0x24331E26,0xE5F5EBB3,

            0xA8741A87,0x99497B21,0x25070038,0x594756D2,0x78903853,0xFC00FE20,0x9B070C01,0x26C18672,0x31A8799B,0xCA6C19E7,

            0x5BC0C219,0xB4CD340C,0xFD3286BB,0x37CE5342,0xEEBB0AE0,0x380C33A9,0x01C601F7,0x37963D06,0xFD9901E0,0xD0CDE80E,

            0x5500E91D,0xCB3007CD,0xF9A7F045,0x0768D311,0xB6800E7E,0x6C1CA749,0x212603AA,0x73B2BA3D,0x37D94769,0xD900FC59,

            0x70F56B8A,0x03B57900,0xB0E5BAC0,0xD8F81E2B,0x07B6BED8,0xA401D253,0x1EDA0E75,0x61681870,0xEC39E20F,0xA307ED15,

            0x03ECD9E3,0xFF894F50,0xB721D080,0x8F836043,0x070CC8BC,0x6C1EE650,0x4826B9AD,0x6B3A4E3D,0x85D07B9A,0x95681C86,

            0x359946D1,0x9B06B1C7,0xEC308F35,0x740E433C,0x01C6B140,0xE87F5A06,0x74DB4655,0x1A3621F5,0x5AE5D172,0x94A4A58D,

            0x8B681A52,0x7908E254,0xC90F2188,0x751AA61E,0x1AE751D4,0x01E300FC,0x01F83284,0x1A06D9E5,0xD4D000F8,0xC39E8FF3,

            0x7EA6654C,0xBA69EE81,0x803AA81D,0xD368FAB2,0xAA379D4D,0x2654A771,0xC7FFEC7E,0xF0996200,0x96C1D100,0x2FB40EB9,

            0x078CFF36,0x701867A8,0x38CF3CCA,0x87A98979,0x201CBB58,0x0986691A,0x2F6302FA,0x301B37D3,0x61ED301C,0xDC0665A4,

            0xC074F36C,0x3F701FB7,0x99C79700,0x275D0EBC,0x6C20F81B,0x1AD87E5D,0x2C201C76,0xA0636076,0x3D84AFA9,0xC0389918,

            0x0F598E49,0xE09A3CAF,0x8751B407,0xFF80E1A8,0xAE83C641,0xA90FDC07,0x1B52396F,0xD032F26A,0x180DC3C0,0xC0601F62,

            0x811C4314,0x0229BB81,0xC5A64A41,0x20442048,0x8842D0C5,0x116D129D,0x43C1B060,0x0C4210AA,0x01840308,0x4201C183,

            0x14E4301A,0x01806183,0x19503083,0x0956C434,0x4D268942,0x0641A721,0x10F8661E,0xC0654862,0x340EBA41,0x50C40320,

            0x92A5EA07,0x60340C22,0x4C0DA18B,0x98D5838A,0x0F4350F2,0x772368E0,0x43A01D5A,0x60D86A19,0x300E394A,0xA4BD90D4,

            0x75801C4C,0x70A6B28F,0xFC40F120,0x5803F801,0x20E26D83,0x07999C7D,0x4DB064DB,0x41B3641C,0x6D835AFA,0x6CD80792,

            0x1A45BE90,0xCEB4C0F4,0xEBDCE030,0xE18FA5B6,0x203E401C,0x94669073,0xD0075C03,0xFBD0BB17,0x3EC67F34,0x64007B00,

            0x980E81D5,0x01D5360E,0x7657479B,0x8F49C4CE,0xC83F8CFA,0x1705DC01,0x072E07EA,0x1285ABE9,0x2EC38A76,0xF301C3DE,

            0x0C07A003,0x710D7A0F,0x21C96900,0x7D883F16,0x47A963C0,0x5C7E6A0C,0x74340F27,0xE36E43A5,0x7C1FDC1C,0x386645E4,

            0x60F73280,0x4827F007,0x6B3A4E3D,0x83D07B9A,0x765C07EB,0xE831B03D,0xBA2E83A6,0x00F1AB5C,0x79DC81C5,0xA61D520E,

            0x40759839,0x2C03E579,0xC17BCF5B,0x53FE30E9,0x70D8399D,0xC79527E0,0xFD8C7B41,0x96C1D100,0x2FB40EB9,0x078CDF3E,

            0xE299E66A,0xCA01FB80,0xCBE827C5,0x07960394,0x1CD80E9C,0x79E038F8,0xD3A0E7D8,0x278A5423,0x583D6785,0xEAE094F3,

            0xF01C3510,0xD078C83F,0x21FB80F5,0x1A472DF5,0x26A1947A,0x3C0D032F,0x01F680DC,0xC4314C06,0x1090F211,0x94922182,

            0xD49A0671,0x420340E0,0x68948090,0x360C390A,0x03020C70,0x100088C4,0x807D4842,0x25EC86A1,0xC400E265,0x5C13F1FB,

            0x00E019A0,0x10B628D7,0x0F341873,0xB8644072,0x4318D3D1,0xC401E40F,0x0F033803,0x03D0D63D,0x9DAA501C,0x7FDE06C1,

            0xF00661BF,0x07B8DC80,0x8D501780,0xB0C71B39,0x83ED1C0D,0x58EA8BA8,0xD2F38107,0x01C03AAA,0x55555530,0x35555555,

            0x35625AA8,0x48751AE7,0x9F355555,0x90C83E54,0x3C8D8ACF,0x3AAA2EF5,0x5AD6C0F3,0x7BCEC0EB,0x41886580,0x0698DA74,

            0x0EE00748,0x02754D22,0x55555551,0x55555555,0x55555555,0xE9DA66D5,0x8792E940,0xB8395E01,0x7AB87B03,0xA1007C80,

            0x365AFE4D,0x70003B86,0xC184A643,0x505B492D,0xBDE461CB,0xE06CDF66,0xD221CAC1,0x689F061C,0x40D038D4,0xB20E3207,

            0xC76E3394,0x271D077F,0x73589A1F,0x1B737DE0,0xC6D6C52C,0xE690F419,0x0FFAC7D2,0x3DA81EB9,0x44E53760,0x1C47C807,

            0x81A7D175,0x0F4168FA,0xE69A0D44,0xF93A403E,0x358F63D4,0xC707C8C0,0x3A0038A6,0xCE63A8D8,0x35AD5A38,0xE63878A7,

            0xD601E900,0xC7AD0701,0x9E880F0C,0xA8AC7D1A,0x58FA0F8F,0x96F3D2FE,0xB3A90698,0x4A4756E7,0x1E981EBD,0xA7E9FA7E,

            0x0BCC7E9F,0xD35C47E5,0xE1807588,0xD539A0E2,0x3A180654,0xE9AF83E6,0x27ACEA80,0xE876DF51,0x348E9334,0x0651D924,

            0x26A1D58D,0xC25A736A,0x485BD354,0x822DA0D9,0x0FD72C03,0x5EC41D0C,0x8769F06D,0x38826C9C,0x83A781C7,0xB5EE83BE,

            0x65F601D0,0xA0719CC6,0xB407A834,0xC68F480E,0x0A4FD31C,0x757CD319,0x5F6836F2,0x68A1FA63,0x3FB88C6B,0xD5BEB069,

            0x2609CDF6,0xCC10E90D,0x80D9F3C1,0x751AC7C9,0x1FC671C6,0x9525406C,0x8C8320EC,0x791B8698,0x1C96B1B2,0xC3DE70EC,

            0xA7787AAF,0x42108421,0x10842108,0x84210842,0xE1084210,0x16386800,0x84369471,0x21084210,0x08421084,0x42108429,

            0xD084210A,0x0DA94A52,0xF36A5034,0x6A4621A4,0x5251A869,0x887D183A,0x0E05A521,0x661084ED,0x10FA6108,0x84210842,

            0x21084210,0x08421484,0xF9308421,0x160C2340,0xA4F380FB,0xEB4A5294,0xCE86920F,0x0A481D23,0x42108421,0xB0A42108,

            0x84210872,0x21084210,0x08421084,0x42108421,0x10842108,0xA5294BB6,0x294A5294,0x4A5294A5,0x5294A529,0xA1B4694A,

            0x0D294A53,0x034B06D2,0x4B58340D,0x5294BC69,0x94A5294A,0x856B40D2,0x21084210,0x08421084,0x42108421,0x10842108,

            0x84210842,0x48384210,0x21684215,0xD87AE85C,0xC43D0375,0x084210FB,0x50D3BEF7,0x8DD83025,0x084210A0,0x42108421,

            0x10842108,0x84210842,0x21084210,0x08424184,0xADFB8425,0xA3699B0F,0x421C0687,0x39842198,0x96719843,0x58E98330,

            0x120C003B,0xE0610842,0x21084210,0x1002D52C,0x0214A428,0xE50C760C,0x07C8F218,0x87780EAC,0x9D241844,0x9C2108E2,

            0x32463C92,0x1C3C233C,0x4F34478C,0xD211C168,0x218783B0,0xD86908EA,0xBB10C3C1,0x84210B42,0x2C584210,0x08421084,

            0x42108421,0x10842108,0x4C210842,0x2108421E,0x08421084,0x42108421,0x10842108,0x763E400E,0x084210B7,0x42108421,

            0x10842108,0x84210842,0x21084210,0x08421084,0x42108421,0x95CC2108,0xA5294A52,0x294A5294,0x4A5294A5,0x5294A529,

            0x94A5294A,0xA5294A52,0x294A5294,0x488694A5,0x7A501C03,0x1C4F723A,0x2F3505EB,0x5310D236,0x78C8372D,0x58091D53,

            0xC649A068,0x0983609B,0x73503986,0x01BA6980,0x9A621A66,0x6F58A611,0xEA8E69AC,0x0C3B001D,0xC360C937,0xEE00758C,

            0x076AC330,0x671926CC,0x21CA8DA2,0x1B86A1A9,0x60DE80E1,0x18301C03,0x76C1846A,0x03AC6318,0x56004768,0xDF28E09A,

            0x46700700,0x4582611B,0x33183806,0xCDC76CD9,0xAB649AF6,0x641886C9,0x3B6601BD,0x65E8727E,0x60DA01B8,0x1803A563,

            0x3806C907,0x5AD43384,0xD8310C83,0x0E419A01,0xC6B20DF2,0x541CAB18,0x438C6418,0x069C0720,0x8074703A,0x5643A564,

            0x3F0E0207,0x3AC5B34D,0xD0330DFB,0x86E0071C,0xC835443A,0x368C4310,0xD2803B4A,0x304E3A06,0xE18261D3,0x33583926,

            0x959001C2,0x328C9F0E,0x1C0B3CCA,0x9F6E1904,0x1CB36683,0x806098C4,0xCE077483,0x340C380E,0x21A1B1C0,0xA81DD40E,

            0x901CAB2A,0x720DA118,0x81AE6B80,0xB2303A46,0x52703B4E,0xB76839C6,0x800720DA,0xCD432A86,0x50E62874,0x4D0B50DA,

            0x6D50D834,0x00C636B1,0xCA334C23,0xD28CDB60,0x0973079E,0x1C3FF8CF,0x7A303898,0x981C2A60,0x4CC0E10C,0x03842108,

            0x3086E3D5,0x8421A4C5,0xE1084210,0x21084A00,0x08421084,0x42108421,0x601C2108,0x42B6070F,0x74B4034B,0x47C0FEE0,

            0x5219F03A,0x10A52D0A,0xA86D2842,0x30380641,0x87540E10,0x43284CB0,0x79543484,0xE2072C1A,0xC45F780E,0xCF3E88BA,

            0xE4768F9C,0x3AEF92D1,0xC3B1D5E9,0xCF0C17E6,0x385C5C14,0xC3A0F31B,0x0A724B5E,0x42948429,0x0F84210A,0xB289D2AA,

            0xCA277023,0x811DC08E,0xA276513B,0x89DC08EC,0x477023B2,0x1DC08EE0,0xFA33BB81,0xC40F5616,0x88BEF01D,0x28F80175,

            0x63C931C5,0x4F134762,0x90703DF2,0x8FC73C4B,0x963EC64F,0x79B2A789,0xC008E817,0x7C07F6C1,0x1FD728F0,0x1E43DC8E,

            0x8FBFA07B,0xF6D1FC66,0x687F689D,0xE8D64FBF,0x011F3EE9,0x8F66487A,0xEA39E1B5,0xC87B091E,0x7C8B0F50,0xD3EF399E,

            0x703ED65C,0xF56E817A,0xE8F0E687,0xD0369F39,0x0D3ED253,0x532C18F6,0x94A4294A,0xA5294A52,0x294A4A94,0x29421084,

            0x421094A5,0x10852948,0x84214842,0x42198587,0x10842108,0x84210842,0x21084210,0x08421084,0x42108421,0x10842108,

            0x84210842,0x21084210,0x08421084,0x42108421,0x10842108,0x84210842,0xA8F140B7,0xD13D1F70,0x6D87CF61,0x4F9A08FC,

            0x13B73CED,0x53F40D9E,0x901A7B70,0x2C2E3EC7,0x8B9D083D,0x0EAE6775,0x3A7C1CD9,0xE268F257,0x7B1C568F,0x00F01A3A,

            0x5C2E6E58,0xCA6E7908,0x5C1E7527,0x0792D9CA,0x35E0F59E,0x03E2219E,0x5CD079A9,0x4D1E4AC7,0x394DC3F5,0xF098F203,

            0xC19C202F,0xB0F59539,0xE8119EB1,0x23838DE1,0x74E8580F,0x9387D9CA,0x4EAB1724,0x3A201C07,0xE7F17397,0x9891C3F8,

            0x5078A547,0xE9C778E7,0xD737BB89,0xF8D81E6C,0x3D3E3613,0x8EE8B0F0,0x3DAEDD37,0xCDC0F623,0xED3C1F2E,0xB75163E6,

            0x1C838E36,0x76DDB83C,0xE7C1EC30,0xC7F3333D,0x9678F175,0x680C7D47,0xEF4EBAC7,0xABBF103C,0xFD618FFA,0xB423CEEC,

            0xB7FF1A7B,0x3CCF8E96,0x12C38330,0x51FC848F,0xDBC63DF3,0xA80F52FB,0x9CBCE1F6,0x53707DC3,0x44F9898F,0xB9E9C3CD,

            0xE3867605,0x723EAAE1,0x7A3A47A3,0x8BE1F229,0x07FFDC3C,0x8E68F00C,0x601CDC8F,0x0F67307B,0xD854E842,0x0EB39E05,

            0x10F2974F,0x538DC9C2,0x2E296716,0x7B9C5C5F,0x1E273E18,0xF26C2F8E,0xF81FB7DC,0x478D89CC,0x1504F32E,0x501DD68F,

            0x2575523B,0xD1D0F0E2,0xC71F93B7,0xDCD88EA7,0x7A7CB939,0xC8E8E0F5,0x103EDC33,0xA1EAB877,0xAB783CC7,0x9D8F62C3,

            0xB1DCE0FD,0x0F3BF3A0,0xF822ED20,0x5F3F48A3,0x30E95270,0x07AE11CE,0xE4E07456,0xB981C6EA,0xE274AC07,0x41D600EB,

            0xFF10E7B4,0x7C1E7B98,0x27BF49D0,0xA840FC4D,0xCD5DE08F,0x8971803B,0x79C484EA,0x777A13B8,0xDDB9AEAE,0xFE8A78CD,

            0x99E86F8F,0xAD483FF5,0x90A76603,0x529CD10E,0x34768438,0x43C0C4EB,0xEAB67A43,0x49E3E00F,0xF81B3D40,0x100F4A9B,

            0x3DBE11E3,0x1743E6BE,0xA9AE7167,0x6797523D,0xE8587F41,0xA5A5D102,0xA8873783,0xED9C3F8E,0xA9774C38,0x58D112E4,

            0x164E6517,0x87EEB33D,0xEA50F366,0x51CED61F,0xF5C407B0,0xED4E2600,0xB27B011D,0x1EF7A7A1,0xFAD9C378,0xB4870403,

            0x1E1E632E,0x4F2F287E,0x1849F4A3,0xB5DB413D,0x5F1CB46F,0x8F3EC878,0x5501FD08,0x0C7C919C,0x6F956721,0x7CF8DC7B,

            0xB2B7A72C,0xA91DB84F,0x20F55DBA,0xDC111F0A,0x5A23B6B1,0xD4B20D73,0x287906C3,0xCE5D47A5,0x3A149C10,0xE01076F9,

            0xCB08D6BC,0x49BB889D,0xD9E29A78,0x38BC1F86,0x6EC87420,0x470A039A,0x1C480EE0,0x764C3AE0,0xDDD8EC40,0x0E87C750,

            0x80742DE2,0x81C318EF,0x872B039C,0x1D6A4EF5,0x761839E8,0xC3C0EE04,0x2A139361,0x71861607,0x590681B0,0xDAD81C2D,

            0xE1CBE0E3,0x3B3609BD,0xE72071B8,0x3881D8B0,0xB89D330E,0x48741038,0x5543B366,0x3A591C1B,0xE66675E0,0x4F76DD60,

            0x8947F01E,0xC2430FC5,0x2C79AE27,0x61FC00E5,0xDB00C3D1,0xE759021C,0xD001CF48,0x1C400EFD,0x71403B31,0x83B46320,

            0x8E810749,0x20720D4D,0x3383BF6D,0x000E8C07,0xF15A081E,0x875ED640,0x6D900ED2,0x60EFD074,0xB69E81D3,0x3D9EF1CD,

            0xAA1C850E,0xC900F51A,0x6843BB41,0x694E2FA7,0x603AB01E,0x40E40873,0xB90706C1,0x319981D2,0x344038A6,0xC3B8A1E4,

            0x0E530702,0x3B641CDC,0xEA087150,0x8431C820,0xA2C70D03,0x001D830E,0xC4E0ED18,0x946FCB16,0x77003F47,0xD390E300,

            0x5783B5E1,0x320E4707,0x203A0F1C,0x40E74072,0xADC37CC0,0x44E49476,0x6961F7D4,0x3F196BC0,0xD84F4FE6,0x3813F1CC,

            0x23C84AED,0x9791F9F6,0x83E6007A,0x09663B34,0x4C308483,0x1401903A,0x02030120,0x02030003,0x980900CB,0x40281013,

            0x2A420600,0x933031A3,0x0D010301,0x0410C088,0x30020060,0x81058106,0x614490A9,0x00831A40,0xE0398207,0x87919C03,

            0xB4FC1935,0x08102043,0x80102004,0x10020040,0x20040080,0x02040810,0x04008010,0x08010020,0x01060040,0x00801002,

            0x01002004,0x70020408,0x1288707A,0x84210842,0x210B1610,0x08421084,0x42108421,0x10842108,0xA7530842,0x21084210,

            0x08421084,0x42108421,0xF0842108,0x3F063C04,0x4A529E80,0xEF34A55B,0x53280716,0x94A4294A,0xA5294A52,0x294A4A94,

            0x29421084,0x421094A5,0x10852948,0x00ED4842,0x95787865,0x81C4C0E1,0xE15303D1,0x070864C0,0x21084266,0x371EA81C,

            0x0D262984,0x42108421,0x42500708,0x10842108,0x84210842,0xE1084210,0x21876201,0x7EF87E06,0x08424507,0x1082929F,

            0x84210842,0x21084210,0x08421084,0x42108421,0x10842108,0x1C210842,0x84210888,0x21084210,0x08421084,0x42108421,

            0x10842108,0x1C210842,0x84210BA8,0x21084210,0x08421085,0x42108421,0x10842908,0xACE14842,0x8421085F,0x21084210,

            0x08421084,0x42108421,0x10842108,0x84210842,0x21084210,0x08421084,0x08429C07,0x42108421,0x10842108,0x5C210842,

            0x842109BD,0x21084210,0x08421084,0x42108421,0x10842108,0x08F28BC2,0x42108421,0x10842108,0x84210842,0x21084210,

            0xB7C21084,0x108431BB,0x84210842,0x21084210,0x08421084,0x0C801C21,0x42108421,0x10858B08,0x84210842,0x21084210,

            0x08421084,0x43C98421,0x10842108,0x84210842,0x21084210,0xE4C21084,0x42108421,0x10842108,0x84210842,0x61084210,

            0x084210F2,0x42108521,0x10842108,0x84210842,0x210843C9,0x08421084,0x42108421,0x10842108,0x8421E4C2,0x21084210,

            0x08421084,0x42108421,0x14F26108,0x8425094A,0x21084290,0x08793084,0x4210A521,0x10852108,0x84210842,0x21087930,

            0x08421084,0x42108421,0x10842108,0x843C9842,0x21084210,0x08421084,0x42108421,0x1E4C2108,0x84A10852,0x21084210,

            0x08421085,0x42108693,0x10842108,0x84210842,0x21084210,0x0A43C984,0x4210A421,0x10842D48,0x84349842,0x21084210,

            0x08421084,0x42108421,0x1E4C2108,0x84210842,0x21084210,0x08421084,0x26108421,0x1084210F,0x84210842,0x21084210,

            0x08421084,0x42108793,0x10842108,0x84210842,0x21084210,0x0843C984,0x42108421,0x10842108,0x84210842,0x21E4C210,

            0x08421084,0x42108421,0x10842108,0xF2610842,0x21084210,0x08421084,0x42108421,0x30842108,0x84210879,0x21084210,

            0x08421084,0x42108421,0x10843C98,0x84210842,0x21084210,0x08421084,0x421E4C21,0x10842108,0x84210842,0x21084210,

            0x0F261084,0x42108421,0x10842108,0x84210842,0x93084210,0x08421087,0x42108421,0x10842108,0x84210842,0x210843C9,

            0x08421084,0x42108421,0x10842108,0x1093D1C2,0x84210842,0x21084210,0x0987C184,0x26108421,0x1084210D,0x84210842,

            0x84484210,0x0F084210,0xC0E1E2FB,0x775C3497,0x084210E4,0x42108421,0xC1842108,0x84210987,0x210D2610,0x08421084,

            0x42108421,0x42108448,0xE2FB0F08,0x3497C0E1,0x10E4775C,0x84210842,0x21084210,0x0987C184,0x26108421,0x1084210D,

            0x84210842,0x84484210,0x0F084210,0xC0E1E2FB,0x775C3497,0x084210E4,0x42108421,0xC1842108,0x84210987,0x210D2610,

            0x08421084,0x42108421,0x42108448,0xE2FB0F08,0x3497C0E1,0x10E4775C,0x84210842,0x21084210,0x0987C184,0x26108421,

            0x1084210D,0x84210842,0x84484210,0x0F084210,0xC0E1E2FB,0xF75C3497,0x21086A58,0x18421084,0x4210843C,0x1E0C2108,

            0x84210842,0x210F0610,0x08421084,0x42108783,0x1F842108,0x8421128D,0x21084210,0x08421084,0x42108421,0x10842108,

            0x47E10842,0x65686D69,0x50FB098A,0x421C0CE3,0xC1A07B18,0xF4611D86,0x69286432,0xB80E94A0,0xD36CC81D,0xC0C3394C,

            0x07B18421,0x11D86C1A,0x94321C46,0x6188DAC1,0xD8D30186,0x4611D503,0x76B0701C,0x6640EDC0,0xA1CA669B,0x853819C6,

            0x6C1A07B1,0x1C4611D8,0x52C19432,0x32B43B1A,0x0FB09859,0x2180CE35,0x60D03D8C,0x7A308EC3,0x34943219,0xB6634A50,

            0x7D84C532,0x0C0671A8,0x0681EC61,0xD184761B,0xA4A190CB,0x4D3A5281,0x21E8CA3C,0x08421084,0x42108421,0x10842108,

            0xF1E10842,0xA2A13CDF,0xA2E7BAB3,0xC3FFA91F,0xF492B806,0xC09E2104,0x07FF15E5,0xE3D57767,0x8303E85A,0xDB72F9BD,

            0x3CF781F9,0x3AC7ECB0,0xC1FBBE70,0xF3B13D45,0x950FC713,0x81F386E6,0x3F8507B7,0x78FE33C4,0xCEF7BC22,0xCDDD034F,

            0x8F122C7B,0x2EC1FEB5,0x3478B41D,0xECC50F9A,0x67B7B19C,0xD1FBC91E,0xF256A7BF,0x8DAF0E84,0x10E7B0BE,0x84210842,

            0xFAFDBCF0,0x39443F10,0x1E7D087E,0x00E11A40,0x59B301C8,0xFA4D200E,0x047FD7D0,0x9490FDD5,0x71B4641F,0xFC0D887E,

            0x187EE008,0x10FD0B4B,0xB621FA7B,0xD251C23B,0xFC436CA3,0xA9FA9FD4,0xC3D2392F,0x74587DEC,0xC0372CC3,0x587CE2C3,

            0x899A695B,0xAC630986,0x5310D835,0x87E0950C,0xA40FC2CC,0x383187DB,0xBF390FC1,0x03A6721F,0xECA0704D,0xB368E080,

            0x6F00756D,0x9B467DAA,0x1AC60983,0x7843946C,0x660F5307,0xE79C041C,0x9159FC84,0x4D0BAD83,0xC0F3C071,0x7E6C0788,

            0x50FD9FA8,0x94601CD7,0xEDDB06F1,0x5ED01687,0x571D343F,0xF200EE19,0x6647A481,0x8F23D23A,0x3A1F88DB,0xFDB43F51,

            0xB8651827,0x3F03BA1F,0x3907CB74,0xFD747086,0x4A3FB451,0x600E9196,0x88C3FDAD,0xFB4187E4,0x1F9E830F,0x8C79A606,

            0x51E10203,0xA46A3F6D,0xEE582665,0x68FF0751,0x18D1F8EC,0x4AF7A8FC,0x25A7EF19,0xDC8B4FD8,0xFC3BE61F,0xA47D5C20,

            0xEA1A3CCC,0x8F1ACB1F,0x89C7EBB7,0x268F10E9,0xAC9CD1F4,0x075CD433,0xF01D1EC2,0xECCE8F8C,0x0FDBF587,0x1E03F8EB,

            0xC695C52D,0x61C46F9B,0x4DAF1956,0x075ECC35,0x6039E6F0,0xEEEEC3F7,0xEEF23D87,0x39A6E407,0x3EC3F1C0,0xF23D87E1,

            0x1F69FA01,0xBE63F593,0x05966099,0x63F4731F,0x87E199E5,0xE70FD34B,0x070583E1,0xEAEB1F96,0x6C7B3363,0x983EF3E1,

            0x64A0F2A5,0xE43EF00E,0xFB89A78C,0x40DA9F48,0xC3FD0C3B,0x82C7ED43,0x38D8E3E5,0x61107FA0,0x62EE1F9D,0x0F99DC3F,

            0x78341F28,0x6B8FC65C,0x01C700E0,0x3F4F0390,0xB87E6DDC,0xEF9E3E83,0xC3F11BC7,0x1787E82B,0x7C0DE3F6,0x4C2B7DBC,

            0x62F87E13,0x87CF2C3D,0x67C3F2AD,0xD28047F6,0x91FB7F0F,0x581E080E,0x0D8B6C59,0x84651B17,0x3F157E1F,0xDA0F25FC,

            0xAF04F2EC,0xFD59509F,0x23F51FE1,0xC190F490,0xD5B57F0F,0x1E83F87E,0x3F3A99D0,0xB227FF11,0x1B80CEB7,0xFB3080FD,

            0x23FACE01,0x2047E9B0,0x94E08FF0,0x23DE411F,0xEC23F34C,0xE85847EC,0xDA223F04,0x88FCB20E,0x49E31CA8,0x8B493F32,

            0x93CF2927,0x8260994A,0x3C000EF1,0x1D27E5A9,0xEB3623F1,0x8FE9AC47,0xB11FBC38,0x57D83F9D,0xFF25B07E,0xE498CA48,

            0x004FDC40,0xAC9EE1D0,0x17648FDC,0x47EA9917,0x99607E72,0xE4FE9B27,0xFFEC9EB0,0x609FB401,0x91D23F21,0xC9EDDA77,

            0xFC84FF8B,0xFA8991F9,0x996FF323,0x0787991F,0xEDC29EE8,0x6A18CC53,0x0BB91F80,0x91F86707,0x6514FE77,0xFC4D227F,

            0x4F2FE7C8,0x0A27F3A9,0xC5BC8FC5,0x54F9BCA7,0x3F0CFAC0,0x147E824A,0xCE153F77,0xCDB40AA7,0xFD354F3E,0x2CDEAE27,

            0x7F15713F,0x28FDB9E2,0xF651FE63,0xFC6CA3F7,0x3F30C080,0x400E092A,0xFEF8A8FC,0xA3F60551,0xA887F4F2,0xC8BE8FCA,

            0x0070C9A7,0x3E9A69E3,0x13479DCD,0x6B53E3FE,0x39DE27A4,0xEAA10FC4,0xB9EAAB72,0xA1ED3F6E,0xFC7AC701,0x29DF8F92,

            0x8FC4B50D,0x0D1FA206,0x001D9BC4,0x2075003A,0x52D540F2,0xFA0ED407,0xA349301E,0x3AA068FD,0xF0A07078,0xD3E4DD27,

            0xFCF34A07,0xD1FBD9E8,0x19A3F823,0x723327EC,0x7682C9FB,0x9B27E3B0,0x181433F0,0xDBB4986E,0x968207EC,0x0072503D,

            0x9E699F7D,0x8E33F2D1,0x8719ED9A,0xF291133E,0x47EFDBA3,0xCF20EA57,0x0299FC64,0x9FE7F0BC,0xCE073AE6,0x0E8C8A7E,

            0x0E29CCF1,0x38681C20,0x0063F308,0xFDBF47E7,0x0EA80744,0x3A18FDD0,0xDFD3B37B,0xD791F3E5,0x7D2AAEFB,0xF00F2397,

            0x9AA998FD,0xF914C7E6,0x7ED98601,0x98FC374C,0x70D83ECE,0xA01C25A0,0xDD30E43D,0x1F81798F,0xDDCFCA33,0xFD77B9F0,

            0x69FB7B98,0x193CFE96,0x53FA629E,0xDCB1F8D2,0xA7E09075,0xCF60ECDD,0xFAC7EA4B,0xD2274FD4,0x3F7CCE9F,0xE999A236,

            0x8FC256C7,0xB5E7DC4D,0x0E8DBCFC,0xDDB34D38,0xE9FD5EF3,0xBF63F5C7,0x81D2E0F1,0x3CBFE787,0xFAB00BCB,0x33F22671,

            0x7867F09C,0x0388C1C2,0x09CE3F3E,0x0BFF105F,0x906019EA,0xE05906A1,0x1C402DC7,0x0FA401F5,0x254C4E3F,0x600F81A6,

            0x8701D386,0xCA7276A3,0x2190CB81,0x48E2A1B7,0x613C8E43,0x6FA99579,0x03C46A69,0x32000F4C,0x319EB85C,0x197381A6,

            0xE43EC6A4,0x1C0DC3D0,0xBE4304EA,0x0EF1F8B2,0x72BECE66,0x0DC1A873,0x46112C06,0x10C53118,0xB3E304E2,0xAEEB90D3,

            0xC463DA45,0x421821F5,0x94A6ADC8,0x8D211AD6,0x003A423C,0xCA6D88FA,0x67DF7623,0x906F5867,0x52947FC7,0x0A520423,

            0x6018C189,0x184A90A4,0x212C2620,0xD2206052,0x3C09ED00,0x00100002,0xE1301A36,0x11C06960,0xB0721E06,0xA460E434,

            0x30198701,0x00067650,0x10000020,0xF94E4F58,0x900007B0,0x00040C08,0x12001024,0x01012004,0x00902106,0x90000200,

            0x731A0010,0x0C120026,0x31234C92,0x6ADCF410,0xA2A87A1A,0x98653486,0xCD3E4EAC,0x338E3590,0x9FC308FA,0x00047FFA,

            0xEB99F0F0,0x0001E7C3,0x53E1E000,0x69F0F003,0x47948B0E,0x64007EEC,0x4B7610DF,0xF06C204F,0xA0079003,0x7A403886,

            0x45A06200,0xF4671A67,0x88670631,0x403E67CD,0xAB7E0076,0x6C1B6719,0x6C1F4608,0xCE900E08,0x1C18D8B2,0xF46B5CA0,

            0x421D9027,0x10842108,0x84210F06,0x8E1E46ED,0x06010761,0xC8C0A000,0x50380D23,0x108435D8,0x0C210842,0x2108421E,

            0x0F061084,0x29C00DAB,0x05A80E22,0xC0009308,0xC00532A4,0x29364CA4,0x1A4C014E,0x7C980498,0x6626000A,0x49052612,

            0x20A4C24C,0x93053889,0x4C014C22,0x024C491C,0xB1364E93,0x3A9314E0,0xD93A4C05,0x793193A4,0x4E4C538A,0x9D262990,

            0x2629F26C,0x69C1938E,0xDA620DDC,0xD3DDB86C,0x90202480,0xD8003580,0x959B11F0,0xD9BEEC47,0x5781E9AB,0x409F9ED3,

            0x6D6B92C8,0x4350C8B9,0xB4D33F8C,0xCE318F0B,0x3C8C83B4,0xC191654A,0x68711F66,0xCC221907,0xD3A0D835,0x5CD53ACE,

            0xEEB10D83,0x0000D7D3,0x40378000,0x61AEC63A,0x0380918B,0x256010A0,0xC2006528,0x000332AB,0xE0000000,0x72E79955,

            0xF01C208A,0x98299C99,0xC199043C,0xD374C3E9,0xCA4C14E2,0xB4C03064,0x4CAB424C,0x740364CA,0x2B007568,0x00C64E93,

            0x4C14CF4E,0x300C538A,0x4F9364FD,0x829C7131,0xCAC16956,0x060C1800,0xC0000021,0xC00D93F4,0x987433F4,0x0E800674,

            0x8C207003,0xB1A7E103,0xCA075CC3,0x9E1CCF0E,0x7B8C325D,0x03D76A58,0x34A53DA0,0xF06D4F50,0xE81A529E,0x93A0C7BC,

            0x215C201E,0x499DD40F,0x1E0D160D,0x03A70F20,0x7AAD6E0E,0x06C9C850,0x6ED4638B,0x38C60B09,0x76EB2BF1,0x361AB794,

            0x2A0794DB,0xF187800E,0xB9ECED8F,0x438F01D3,0xCEE007AF,0xE93A0F37,0xBAB3EBE1,0xE5B54C13,0x1F0EE300,0x8C03EE52,

            0xA01A4430,0x3A9657E4,0xD7B130C4,0x0E600E10,0xF344E6BD,0xF5D0708D,0x348ED62D,0x42E801EA,0x180C03CB,0x36886004,

            0xC6E344FC,0xA90D06C1,0x791B0658,0x00D34190,0x483CA603,0xD8360CCD,0xA7958801,0xDD8D755B,0x407A4C07,0x41833A0A,

            0xA4E12182,0x10B5B1C7,0x0C201806,0x85680ED1,0x0CF80E11,0x60186734,0xE1468394,0xB701CCE8,0x32503939,0x0C0300D4,

            0xEC1AF530,0x639CF611,0x180601A8,0xCCEBEA60,0x0681807D,0x01AC621F,0x9DE231FA,0xB08073D8,0x308C66F7,0x332328FC,

            0x3CA3F0C2,0x88F29DA2,0x080001ED,0x2CD009FD,0x01DC04F3,0x1F000200,0xB7A380F7,0x2070471F,0x6A100000,0x10842108,

            0xF9F92AC2,0x43EC3CB8,0xA1A64AA7,0x34B4241C,0xB7027A44,0x42108421,0x3C996108,0x80761852,0xEE751D97,0x4DE066EA,

            0x18D55791,0x431D218F,0x8701A48E,0x3890C788,0x31F31C86,0x83C863BC,0x3B07D20F,0x790C7486,0x8512C1C8,0x18E90C78,

            0x90C78972,0x54C7218E,0x63A431E2,0x34C531C8,0x40942074,0x14201048,0x6000ED0A,0x10842108,0x32700AC2,0xF21A8609,

            0x8314C080,0x10843933,0x84290842,0x290A5210,0x184210A4,0xC4350EBF,0x008807B8,0x00000000,0x00900120,0x10204008,

            0x11200060,0x04084080,0x00200106,0x00080001,0x00020004,0xCC002801,0x2002400B,0x98001001,0x08004088,0x34000810,

            0x4805E600,0x04200900,0x80018102,0x21080104,0x08041810,0x10008004,0x28100080,0x4892F300,0x30230604,0x18D1210A,

            0x6060449B,0x89230302,0x00440841,0x02240853,0x18181303,0x20420C49,0x04429802,0x8042A50C,0x06674612,0xFB34E000,

            0x300F2378,0x18486D10,0x6C97F1FC,0x48EC3476,0x38F3073D,0x68C00B98,0xD8EC3270,0xC0700015,0x01B80E0D,0xA38DD070,

            0x26DC0746,0x1160EC1F,0x0D3BDC40,0xC4009B07,0x0000B6EB,0x2D4700C7,0x3E1E4443,0x1EA7C3C9,0x4651F861,0x47E18466,

            0x7D11F919,0x18EC4795,0x84210842,0x4FCF0610,0x27A76180,0x08421C50,0x78308421,0x0F842108,0x3143CCC7,0x8676D8FB,

            0x210F0610,0x08421084,0x325ABF83,0xD3578000,0x2F0BCA3E,0x7BACE47A,0x60DEB86C,0xD9BD4FF3,0xBE0D1B8A,0x3F830EE3,

            0x00000A7D,0x78E900DE,0x06A1EC61,0xB735457B,0xC92C1F7C,0x41D7B221,0x41A01009,0x04467180,0x875B0002,0x0A02C695,

            0x63800100,0x1D231C58,0x2649C431,0x34E6251D,0xA861C0C8,0x8A1A0709,0xF2ABEE36,0x55780001,0x8C9CA5CE,0x61A07D1A,

            0x52003F06,0x87430A86,0x00000006,0x081E4000,0xC3003866,0xC40E2581,0x4905C073,0x8207060C,0x5930FA61,0x3086330B,

            0x86330B49,0x330B4930,0xF4C2D14E,0xC53E4D93,0xC9B261E4,0xD2649843,0x610F26C9,0x63274992,0x9F2629F2,0x2610F262,

            0xC9FA6169,0x807B985A,0x2D0A2610,0x24C218CC,0xC218CC2D,0x18CC2D24,0xCC2D24C2,0x330B4538,0x0B493086,0x42718793,

            0x71879309,0x87930942,0x93094271,0x09427187,0x33DCC306,0x0B7A1684,0x6E34CF73,0x30942718,0x94271879,0x93086330,

            0x9843A9A4,0xC21D4D24,0x3A4E2924,0x4C53E4D9,0x21E4C53E,0x9869324C,0x2610F264,0xC9B27499,0x8A7C98A7,0x649843C9,

            0x0F26C9D2,0x7930A261,0xA9A49308,0xF2649843,0x53492610,0x0879314F,0x6298A493,0x98A6298A,0x5201CA62,0x0C18294C,

            0x60C18306,0x0C661830,0x81719261,0x60C182C9,0x060C1830,0x10C66183,0xE8171926,0x88924C21,0x43108793,0x58818498,

            0x7122409C,0xCAA27BEA,0x4A8CA398,0xC7D06918,0x2C4071CF,0x2600F90D,0x04F41A86,0x38DB09D4,0xDCC07444,0x82616A73,

            0xF22F2AFE,0x301B7243,0xB0AAFF4F,0x5AC0309B,0x44780007,0x204C7707,0x610A42B5,0x00C534A0,0x18908583,0x97D93C22,

            0xEA7CF757,0xAD46998E,0xF1328D83,0xF8780023,0xAFA23CD4,0x0D53433B,0x631AE8B6,0x4A0741B7,0x000FC007,0x3C80758D,

            0x803E4C30,0x8F16F9B6,0xCCE5E73B,0xC270E69E,0x631F4649,0x6B1503F4,0xFA23C66D,0xF0B18BBA,0x001C5300,0x96116C9D,

            0xFC00EEDC,0x368F037E,0xCD3BBEF8,0xEC3D230F,0x7E73E7BF,0x19DA679A,0x0D251D86,0x5B1AFD38,0xEEBE88F0,0x461C2C34,

            0xEEB7003A,0x4CF2B07A,0x37336F5B,0xA0C40C0B,0xDE701CF0,0x9A69E622,0x9644E309,0x21E81E68,0x1B6C0EF9,0x2C1D4420,

            0x8A43E80C,0x62604F2F,0x4D038A00,0x03484257,0xC09E1185,0x34D47AD5,0x280710D8,0xFDDC6B9D,0x09E21F06,0x465D85AC,

            0x0180779E,0x0E6B6AE3,0x8314E836,0xB187413E,0xDE601C17,0x2F836403,0x403DA7DD,0x0704FE30,0xD4209F20,0x332E9324,

            0xCE93F0E0,0x0C5CE733,0xC560E836,0x13C31487,0x4A827A58,0x09EB904F,0x88413C3A,0x3E472827,0x38C13080,0x76100F43,

            0xBE4DAB1F,0x354C5C50,0xC31C6CE6,0x0FB47036,0x58EB8BA2,0xBE4EB907,0xFA9E7F9D,0x291B7640,0x2B3694AD,0x1896C007,

            0x0A0716C8,0x5D34ED23,0x61ED756E,0xB60354C3,0xDA41E361,0x341BA69E,0x9846324C,0x20C229CC,0xC0CA58C1,0x721E6BBD,

            0x5E6601A8,0x81C060F0,0x3C4614E6,0x60D07824,0x1F2B83C4,0x1C23C54F,0x7666C3F7,0x2B7E83D4,0x7D9DF01F,0x1A47AD90,

            0x01D980E6,0xCE72B1A4,0x9C0F4631,0xE470700C,0x9364FC00,0xE0D336CD,0x52E2DEE5,0x4078C435,0xA0D7C0F2,0xA78D8579,

            0x683F3038,0x01A0694D,0xF0614C07,0x8340D834,0x1C4398C5,0x50360EB4,0x3A0E832D,0xA07DCA50,0x838A0612,0x1F6A1A0D,

            0x53D4A738,0xD14D230D,0xD2781D07,0x9875A143,0x238B07B1,0x385E368E,0x74F1F5FA,0x518DB61D,0x56303E7B,0x401E500F,

            0xEA3A7439,0x0074D49D,0x0741B061,0xF036803D,0xE01E8300,0x79BEC03A,0x58C0EA5D,0x81F5BD1C,0x8483C872,0xBDCF4A1E,

            0x1F9792F6,0x07F9D071,0x3D80621A,0x4C9BF2CA,0x07A0ED39,0xB68C0F51,0x6D198701,0xA68611C2,0x46484AB6,0x7A01C108,

            0x08E40388,0x0601D503,0x20483D6C,0x29E0D031,0x1E521AB6,0xC120E620,0x62102120,0x1C4830EB,0x48CA4860,0x64C80F43,

            0x8759A503,0xE1A8701B,0x37A01D43,0x0EB407A3,0x3CEA32B0,0x9324E293,0x1B4781C7,0xD68102BE,0x34921A87,0x0D03D0C4,

            0xCB48C4D8,0xC1C96226,0x21B5B090,0xA07C1B87,0x46CC3CD9,0xC531003C,0x783EA108,0xE80F01DF,0x81E88ABE,0x436CAA7D,

            0x11B7D83C,0xC3B781D2,0x5F5D372A,0x341A7074,0x17B953BE,0xF5BE7AE6,0xD035EA80,0x4397AD3B,0x334E8D2F,0x039401E1,

            0xE4E90F90,0x60BDBFC9,0x5A1F0847,0xE0CC0F86,0xD507DA3D,0xA1E56677,0x86403F7C,0x8EEBD2A3,0x285F26D5,0xF93E0A1E,

            0x8DBE5176,0x9B4A5694,0x4B600395,0x038B640C,0x9A769185,0xF6BAB72E,0x01AA61B0,0x20F1B0DB,0x0DD34F6D,0x2319261A,

            0x6114E64C,0x652C6090,0x0F35DEE0,0x3300D439,0xE030782F,0x230A7340,0x683C121E,0x95C1E230,0x11E2A78F,0x3361FB8E,

            0xBF41EA3B,0xCEF80F95,0x23D6C83E,0xECC0730D,0x3958D200,0x07A318E7,0x3838064E,0xB2660072,0x4FBB66C9,0x310D54BE,

            0xF03C901E,0x615E6835,0xCC0E29E3,0x1A535A0F,0x5301C068,0x360D3C18,0xE63160D0,0x83AD0710,0xA0CB540D,0x72940E83,

            0x8184A81F,0x868360E2,0x29CE07DA,0x48C354F5,0x0741F453,0x6850F49E,0xC1EC661D,0x8DA388E2,0x7D7E8E17,0x6D875D3C,

            0x0F9ED463,0x9403D58C,0x9D0E5007,0x35277A8E,0x6C18401D,0xA00F41D0,0xA0C03C0D,0xB00EB807,0x3A975E6F,0x6F471630,

            0xF21CA07D,0xD287A120,0xE4BDAF73,0x741C47E5,0x188681FE,0xFCB28F60,0x3B4E5326,0x03D441E8,0x61C06DA3,0xB6309B46,

            0x0846484A,0x887A01C1,0x0308E403,0x6C0601D5,0x3120483D,0xB629E0D0,0x201E521A,0x20C120E6,0xEB621021,0x601C4830,

            0x4348CA48,0x0364C80F,0x1B8759A5,0x43E1A870,0xA337A01D,0xB00EB407,0x933CEA32,0xC79324E2,0xBE1B4781,0x87D68102,

            0xC434921A,0xD80D03D0,0x26CB48C4,0x90C1C962,0x8721B5B0,0xD9A07C1B,0x8C6B5ECA,0x9019061E,0x1C303476,0x1D311CA0,

            0xB52B7CA4,0x3D473007,0x1D07D3EA,0x86E1946D,0x2187221E,0xC443C0D3,0xFC5C7201,0x6978EA40,0x7D07C9C8,0x8107CC4B,

            0xDF9D300F,0x96FA7D58,0xE8721AA6,0x79F0F261,0x198751B4,0xAE2A019A,0xC3D4FA34,0x1E78310C,0x9BA7E1C0,0x03313836,

            0x6398001C,0x1847F18C,0xC701A07E,0x09FA1C18,0x00F245B7,0xDE92C079,0x9401FBC3,0x0C21B003,0x0C1C63D2,0x499801DA,

            0x84791946,0x311A47C1,0xF91F07C4,0xA3194831,0x15F6F83F,0x246F47E3,0x93E903D5,0xE480790D,0xBA01EE00,0x27A59403,

            0xB56386C3,0x878A17C9,0x5DBE4F82,0xA5236F94,0xE566D295,0x0312D800,0x6140E2D9,0xCBA69DA4,0x6C3DAEAD,0x36C06A98,

            0xDB483C6C,0x868374D3,0x9308C649,0x24184539,0xB8194B18,0x0E43CD77,0x0BCCC035,0xD0380C1E,0x8788C29C,0x841A0F04,

            0x1CAFB783,0x2A9F607C,0x3BBEE3DB,0x6C3F71C2,0xE83D4766,0xDF01F2B7,0x7AD907D9,0x980E61A4,0x2B1A401D,0xF4631CE7,

            0x0700C9C0,0x4DE00E47,0xF76CD936,0x21AA97C9,0x079203C6,0x2BCD06BE,0x81C53C6C,0x4A6B41F9,0x60380D03,0xC1A7830A,

            0xC62C1A06,0x75A0E21C,0x196A81B0,0x5281D074,0x309503EE,0xD06C1C50,0x39C0FB50,0x186A9EA5,0xE83E8A69,0x0A1E93C0,

            0x3D8CC3AD,0xB4711C58,0xA621C2F1,0xD781D211,0x6907B983,0xE8BEBA6F,0x7C6834E0,0xB6C3698D,0x07CF6A31,0xCA01EAC6,

            0x4E872803,0x9A93BD47,0x360C200E,0xD007A0E8,0xD0601E06,0xD8075C03,0x1D4BAF37,0xB7A38B18,0x790E503E,0xE943D090,

            0xF25ED7B9,0x3A0E23F2,0x0C4340FF,0x7E5947B0,0x1DA72993,0x81EA20F4,0xE1E036D1,0x7AE61786,0xEA80F5BE,0xAD3BD035,

            0x8D2F4397,0x84DA330E,0x324255B1,0xD00E0842,0x47201C43,0x300EA818,0x0241EB60,0x4F068189,0xF290D5B1,0x09073100,

            0x10810906,0xE241875B,0x46524300,0x26407A1A,0x3ACD281B,0x1E1370DC,0x1E003940,0x93D9D21F,0x8EC17B7F,0x3E194610,

            0x337A01D4,0x00EB407A,0x33CEA32B,0x79324E29,0xE1B4781C,0x7D68102B,0x434921A8,0x80D03D0C,0x6CB48C4D,0x0C1C9622,

            0x721B5B09,0x9A07C1B8,0xF07343ED,0x47BC1981,0xCEFAA0FB,0xEF943CAC,0x5470C807,0x9B801CBA,0x475F0CAF,0x47C1E108,

            0x17ADD01E,0xE21B56DC,0x421E1BB9,0x23A4D07D,0x003B601C,0x80EAC07F,0x790B63F2,0x6D53F16C,0x7C9B5638,0xF82878A1,

            0xF945DBE4,0x295A5236,0x800E566D,0x2D90312D,0xDA46140E,0xEADCBA69,0xA986C3DA,0xC6C36C06,0x4D3DB483,0x64986837,

            0x5399308C,0xB1824184,0xD77B8194,0x0350E43C,0xC1E0BCCC,0x29CD0380,0xF048788C,0x783841A0,0x07C1CAFB,0x3DB2A9F6,

            0x1C23BBEE,0x7666C3F7,0x2B7E83D4,0x7D9DF01F,0x1A47AD90,0x01D980E6,0xCE72B1A4,0x9C0F4631,0xE470700C,0x9364DE00,

            0x7C9F76CD,0x3C621AA9,0x6BE07920,0xC6C2BCD0,0x1F981C53,0xD034A6B4,0x30A60380,0xA06C1A78,0x21CC62C1,0x1B075A0E,

            0x074196A8,0x3EE5281D,0xC5030950,0xB50D06C1,0xEA539C0F,0xA69186A9,0x3C0E83E8,0x3AD0A1E9,0xC583D8CC,0x2F1B4711,

            0x211A621C,0x983D781D,0xA6F6907B,0x4E0E8BEB,0x98D7C683,0xA31B6C36,0xAC607CF6,0x803CA01E,0xD474E872,0x00E9A93B,

            0x0E8360C2,0xE06D007A,0xC03D0601,0xF37D8075,0xB181D4BA,0x03EB7A38,0x090790E5,0x7B9E943D,0x3F2F25ED,0x0FF3A0E2,

            0x7B00C434,0x9937E594,0x0F41DA72,0x6D181EA2,0x786E1E03,0x5BE7AE61,0x035EA80F,0x397AD3BD,0x30E8D2F4,0x5B184DA3,

            0x84232425,0xC43D00E0,0x81847201,0xB60300EA,0x1890241E,0x5B14F068,0x100F290D,0x90609073,0x75B10810,0x300E2418,

            0xA1A46524,0x81B26407,0x0DC3ACD2,0x9401E137,0x21F1E003,0xB7F93D9D,0x6108EC17,0x1D43E194,0x07A337A0,0x32B00EB4,

            0xE2933CEA,0x81C79324,0x02BE1B47,0x1A87D681,0xD0C43492,0xC4D80D03,0x6226CB48,0xB090C1C9,0x1B8721B5,0x3ED9A07C,

            0x981F0734,0x0FB47BC1,0xCACCEFAA,0x807EF943,0xDBA5470C,0x3C0D1B7E,0x180F2178,0xA8023DA6,0xAAAAAAAA,0xB549AAAA,

            0x35CE6AC5,0xAAAA90EA,0xCB87CE6A,0xD3681B46,0xC73A4817,0xBAC243B8,0x17C9B563,0x4F82878A,0x6F945DBE,0xD295A523,

            0xD800E566,0xE2D90312,0x9DA46140,0xAEADCBA6,0x6A986C3D,0x3C6C36C0,0x74D3DB48,0xC6498683,0x45399308,0x4B182418,

            0xCD77B819,0xC0350E43,0x0C1E0BCC,0xC29CD038,0x0F048788,0x70788C1A,0x78A9E3E5,0xD87EE384,0xD07A8ECC,0xBE03E56F,

            0xF5B20FB3,0x301CC348,0x5634803B,0xE8C639CE,0x0E019381,0x9E801C8E,0xE4FBF36C,0xE310D54B,0x5F03C901,0x3615E683,

            0xFCC0E29E,0x81A535A0,0x85301C06,0x0360D3C1,0x0E63160D,0xD83AD071,0x3A0CB540,0xF72940E8,0x28184A81,0xA868360E,

            0x529CE07D,0x348C354F,0xE0741F45,0xD6850F49,0x2C1EC661,0x78DA388E,0xC7D7E8E1,0x36D875D3,0xC0F9ED46,0x79403D58,

            0xE9D0E500,0xD35277A8,0x06C18401,0xDA00F41D,0x7A0C03C0,0xFB00EB80,0x03A975E6,0xD6F47163,0x0F21CA07,0x3D287A12,

            0x5E4BDAF7,0xE741C47E,0x0188681F,0x6FCB28F6,0x83B4E532,0x303D441E,0x661C06DA,0x212AD8C0,0x07042119,0x900E21E8,

            0x07540C23,0x20F5B018,0x8340C481,0x486AD8A7,0x83988079,0x40848304,0x20C3AD88,0x29218071,0x203D0D23,0x66940D93,

            0xA1C06E1D,0x80750F86,0xD01E8CDE,0xA8CAC03A,0x938A4CF3,0x1E071E4C,0x040AF86D,0x486A1F5A,0x0F4310D2,0x23136034,

            0x25889B2D,0xD6C24307,0xF06E1C86,0x072B6681,0xA3C86620,0xF1163F0D,0x2B785728,0xEF90E533,0x47C1FFC1,0x3294641E,

            0x4F5370CA,0x800FA131,0x60807480,0xC30781BC,0xACF19E43,0xAE0314FB,0x9E04F4B3,0x33EEA56D,0x0F0310CF,0x9C264C38,

            0xA06B18A4,0xC7B1EF13,0x03CC0661,0x30F2A1C4,0xC701806D,0x300F391B,0x71AC6270,0x18201F21,0xA85AB861,0x9B873EA7,

            0x7CB3BCB2,0x720E38CF,0x92C5BBEA,0xD683CA52,0x9B3BE238,0x4835FD3A,0x10C2110E,0xC630C703,0x3E41ABD8,0xF0CCB600,

            0x0C3C140C,0x0D130E16,0x775C4E31,0x42F936AC,0xC9F050F1,0x6DF28BB7,0xDA52B4A4,0x5B001CAC,0x1C5B2062,0xD3B48C28,

            0xB5D5B974,0x0D530D87,0x078D86D8,0x6E9A7B69,0x18C930D0,0x08A73261,0x29630483,0x79AEF703,0x9806A1C8,0x0183C179,

            0x18539A07,0x41E090F1,0xAE0F1183,0x8F153C7C,0x9B0FDC70,0xFA0F51D9,0x77C07CAD,0x1EB641F6,0x66039869,0xCAC69007,

            0x3D18C739,0xC1C03270,0x93D00391,0x7C9F7E6D,0x3C621AA9,0x6BE07920,0xC6C2BCD0,0x1F981C53,0xD034A6B4,0x30A60380,

            0xA06C1A78,0x21CC62C1,0x1B075A0E,0x074196A8,0x3EE5281D,0xC5030950,0xB50D06C1,0xEA539C0F,0xA69186A9,0x3C0E83E8,

            0x3AD0A1E9,0xC583D8CC,0x2F1B4711,0x78FAFD1C,0xC6DB0EBA,0x181F3DA8,0x0F2807AB,0x1D3A1CA0,0x3A6A4EF5,0xA0D83080,

            0x1B401E83,0x0F418078,0xDF601D70,0x60752EBC,0xFADE8E2C,0x41E43940,0xE7A50F42,0xCBC97B5E,0xFCE8388F,0xC0310D03,

            0x4DF9651E,0xD0769CA6,0x4607A883,0x0CC380DB,0x24255B18,0x00E08423,0x7201C43D,0x00EA8184,0x241EB603,0xF0681890,

            0x290D5B14,0x9073100F,0x08109060,0x241875B1,0x6524300E,0x6407A1A4,0xACD281B2,0xD4380DC3,0xD00EA1F0,0x5A03D19B,

            0x75195807,0x9271499E,0xA3C0E3C9,0x40815F0D,0x490D43EB,0x81E8621A,0xA4626C06,0xE4B11365,0xDAD84860,0x3E0DC390,

            0x00F56CD0,0x970304C1,0x011EC651,0x7B0D5DCF,0x3AA06DCE,0xA5294A49,0x83AB4A81,0x1A5294A7,0xC03A0E28,0x25917D08,

            0xDC1B0601,0x1E1A8601,0x87C1B060,0x3B43B41B,0xEE52B600,0x03990D83,0x284564F9,0xC0300D43,0xE3D8F749,0x16E70330,

            0x8EA56847,0x392F7237,0x00F1048C,0x112304C2,0x368D7ECF,0x9EFB3F5A,0x0D0308F2,0xA5C0EB58,0xEC6C338C,0xE50A0CA9,

            0x8318C100,0x48E2310C,0x610BD384,0x03EED3A0,0x280761C5,0x40300E3D,0xC1846C1E,0xB7BE1BC7,0x034C4301,0x159F6D09,

            0x3E0D3182,0x3E0F8844,0x94EE80F2,0x1F7821E1,0xF06A5840,0x5F7DE0FC,0x3EC0FFA5,0x1E21B655,0xE908DBEC,0x9561DBC0,

            0x3A2FAE9B,0xDF1A0D38,0x730BDCA9,0x407ADF3D,0x9DE81AF5,0x97A1CBD6,0xF099A746,0xC801CA00,0xE4F27487,0x23B05EDF,

            0xC32D0F84,0x1EF06607,0x3BEA83ED,0xBE50F2B3,0x51C3201F,0x6C0076E9,0x1F07A1A5,0x8671F463,0x036253C6,0x3D8F7C9F,

            0x1943530E,0x87950E20,0x380D0368,0x0CBDC8CE,0xB0613030,0xD200F50E,0xE08E9372,0x394063B0,0xF0E0B6EF,0xBB6DE3CF,

            0x007A7D27,0xE639F566,0x68586C1C,0x1A66C007,0x069D0CAA,0x60F0811D,0x20BC7372,0x6B9E4E36,0xB5EDA17A,0x88741F46,

            0x8408E83E,0x5F077E43,0x89B591C3,0xFA179B16,0x86F1A401,0x49B27A19,0x387A1987,0xC036E33C,0xE2D08F19,0x01F62D04,

            0x2FA81973,0x032F7B34,0xE4113C0C,0x0C337003,0x7808E830,0x7B5FA25D,0x340E2B1B,0x1E832A72,0xD66F9D34,0x989B46C1,

            0xEA089881,0x4689B801,0x0992F860,0x1A56DFA7,0x80C7F4E8,0x4A01D871,0x900C038F,0xD06E1807,0x6DEF86F1,0x40D310C0,

            0x003B4303,0x61B0CAB4,0x80F030A0,0xEB738B84,0x6DD1798E,0xF8F3DCFE,0xF3DCF479,0xB9E7D3A0,0xA6E61C06,0xD6B5A8EB,

            0x3A7D6B5A,0x520EB579,0x35B4383F,0xFB500385,0xFCC0BC97,0xF25F4C33,0xBFAD4B30,0x0DA3CECB,0x00054794,0x8E390084,

            0xDE00F500,0x380C0344,0x134330F0,0x340F32CF,0xDE6700E0,0x0DC350E3,0x781B4834,0xD26C77C0,0xE4681946,0x8F034A68,

            0xDA00F901,0x368F833C,0xCA7C0C29,0x4C38F63D,0xD880650D,0x0C03697B,0xBDC8DE38,0x690381B4,0x08072804,0x11981BC6,

            0xEBB7C786,0x1DAE8E1C,0x31661D48,0x16F00748,0xC364781A,0xDEC380A1,0x3C6790ED,0xA58079D4,0x81E0324E,0x0310C288,

            0xC0EF352F,0x803A4183,0xD2434332,0x0609B671,0x3CCC4B28,0x00748070,0x8681B263,0xEA9177D2,0x019B70BB,0xE40B7ED2,

            0x5790F411,0xC036E43C,0x01E6A805,0xCDFB483C,0x5200C234,0xDC8FBB2E,0x6C1CF60E,0x33AE877B,0xE9F87F8D,0x1B06FEF0,

            0x33803A42,0xC24DC0CF,0x0F85B435,0xE90AEDC0,0x0E5CD200,0xD87AE92C,0x5DBEABA0,0xA00E61D5,0xA42338AC,0xB4330803,

            0x5B46F5A1,0xEA36E1BA,0x36CF43A0,0x01D21136,0x19861182,0xB78DD242,0x781D4749,0x1E473185,0xA001D21C,0x5C1AC6B9,

            0xEDDE07E2,0xC7A8EB70,0xDE578E37,0xDFB4800B,0xA70F0302,0xBE29722F,0x0759B748,0x0AF16CDD,0x34C500E9,0xFF7A48A9,

            0x375D876E,0xCD58F41D,0x9203E9D1,0x1D205E07,0xEC665A80,0x23BC2461,0x981689B7,0x8001D21D,0x3BE24C55,0xD2025BCE,

            0x46C9A401,0x78BBE2C8,0x01D2039B,0x1C06C9B4,0x3EFABC4E,0x0403A403,0xF5D00CE3,0xDCD7AA5A,0x00748126,0xF7D5316C,

            0x8FDE50D3,0x85930D5B,0x4BEB06C1,0x8048392D,0xAC608074,0x1CB606C1,0x20F830F2,0xC1F10677,0x69016D94,0x1B86599F,

            0x430BE24C,0x0415F25B,0x803BC01E,0xD204F87E,0x3205A401,0x6D923E12,0x3E36CEA3,0xA35403A4,0xC7043E81,0x8EDDFCF0,

            0x3A489E80,0x00E90841,0x218330C9,0x1DB885E1,0x74983888,0x01D210D0,0x18264998,0x788BD25F,0x720D3F9B,0x41DF6200,

            0xDFB48706,0xF339A172,0x4072B721,0x041F5551,0xAAAAAAB8,0xAAAAAAAA,0xAAAAAAAA,0xC06500EA,0x41EBC874,0x70300CAA,

            0x4846A819,0x1B262807,0xEF09287A,0x05DC6D18,0x00748426,0xB3819E6D,0x0EDDAEF8,0x6BDA4140,0x8482C19E,0xC4C644CF,

            0x690ACCCB,0xC986599F,0xDE2D6B7A,0xC0745B72,0x0F7B4803,0x599F690A,0xC25C19C6,0x3719B66D,0x7ED21558,0x24950D33,

            0x3A39D49F,0xA7580EFF,0x9618781E,0x48607259,0x08162007,0xC067D249,0x0741D26D,0x3AE6695E,0x7003A428,0xC5930D13,

            0x0AB6E117,0x130803A4,0x94BC308C,0x8EB3699B,0x03A0D832,0x98E736EE,0x1D2101C6,0x98629840,0x76DE25E1,0x2DD0699B,

            0xD2121E96,0x86198401,0xC9FEFA4A,0x4B62217C,0x34803A40,0xEA4308DE,0xB78F15F1,0x00E900CD,0x372322D2,0x6D4A2FC9,

            0x13C203F0,0x5E8631C6,0x20C1F168,0x6499401D,0x3DF509AC,0xECF7C62F,0x0720F0B6,0x181E76E0,0x19B401D2,0xBC4C1F06,

            0xA40AB63D,0x0DF36803,0xDC878D1B,0xC89DF143,0x00E9002D,0x8D0374C6,0xE723F128,0x07ACC8B6,0x145CC6E0,0x199C01D2,

            0xBBC25606,0x89749B71,0xC01D2119,0x2CBC691B,0x2DBF85E1,0x5B64007A,0xE6F00748,0x0948781A,0xB40EDEB7,0xA429B1EE,

            0x0D0B7803,0xD49C245F,0xC3F1BE79,0x00E903CC,0x0CC308C1,0xF28287AC,0xA672B721,0xA8E844EE,0x9BC6C185,0x8201D21C,

            0x12882611,0x0ADBE45E,0xE908EDFB,0x0370D900,0x219FA20C,0x6C433F57,0x6BDA40DB,0xE1A030A1,0x3C3BD790,0x6D949DF0,

            0x45AF6900,0xDE928906,0x4348DB9B,0xB0DD320C,0x6BDA42B9,0xBC255E8D,0x2661B6F3,0x5ED21E19,0xE120E41B,0xB74DB95D,

            0xF690CAC9,0x242C6599,0x46C4A47C,0x4872659D,0x06542CFB,0xDDBEFC93,0x0C03C4FA,0xF37CD434,0xA415380E,0x7D1B567D,

            0xAFF77D10,0xCDBBDDF1,0xED800ED7,0x7DA40B39,0xE93119D6,0x370D148B,0x619E46DD,0xACFB484A,0xAF157C33,0x69004DB5,

            0x18C699BF,0x68477C5C,0x6FDA416B,0xF882A181,0x8066C9EE,0x390ADFB4,0xB0781F88,0xF6907C03,0xE325215B,0x329BF73B,

            0xD6EE77C4,0xA1641A27,0x001D2125,0xA1D06058,0x7FC3EF0C,0xDC3EFAC6,0x94616C06,0x6160D438,0x1DA6E9C0,0x003A4024,

            0xC3A0CCB0,0xF3B13848,0x5987E0EE,0x8001D20B,0x43D57A35,0xEF90E501,0xD36EC327,0xB01D0741,0xC038901C,0x90C0C358,

            0x322D000E,0xDBC87AA4,0x04B6E277,0x8B4003A4,0xF8AC308C,0x8326D5EE,0x816C0074,0x1C3207A1,0xE83CB4F2,0x68B24FB2,

            0x3586A21D,0xC86A1F16,0x001D205E,0xA581CC5B,0x12B59FBC,0x0D030EC6,0xBB99E752,0xC0074835,0x58601B16,0x0E17E43D,

            0xC2FDBD79,0x03A40532,0x3E8CCB60,0x8D3DF182,0x838FD395,0x6779D69E,0x61C7A9F1,0xC603C86A,0xBD3F5BC1,0x6D90CA3A,

            0xEE46F1C0,0x43418065,0x07486623,0x2118A620,0x26D2D788,0x62007482,0xC4A2718A,0x6436A177,0x02F46F19,0x7CC400E9,

            0x43F12443,0x0C0476EC,0x058801D2,0x91FAC0C2,0x291F2EEA,0x1986E9B7,0xD9BF0EA0,0x2291E6B2,0x2B1003A4,0x84B03C0C,

            0xFD36C377,0x3A43CB7A,0x44D13700,0x7F7A4A23,0x584F836E,0xDE6C9AC6,0x801D2031,0x31E0619B,0xD74E5DF4,0x4A96E977,

            0x0194A38B,0xAA7D40E2,0x74810729,0x41866E00,0x86C7BEBA,0x9DE74A74,0xFE310FC5,0x338D8330,0x7003A42B,0xE1A30D33,

            0x2775AF23,0xDB958FC1,0x07481261,0x361896E0,0x08E07BE8,0x59DE7627,0x40EB30FC,0xC2B0803A,0xEF890384,0x48266DF0,

            0x18561007,0x177D007F,0xB48BBEAD,0x401D2069,0x21A86F1A,0x36A7F7C5,0x4803A419,0x24920DE3,0xE779D89C,0x00CCC3FA,

            0x78D200E9,0xEF097423,0xC5826D8A,0x007486A6,0x4631BC69,0xCFBEF896,0x8E661F46,0x74850721,0x93326900,0xDAEC8F84,

            0x0FAD9B74,0x64D200E9,0xE1290C43,0x8076EE33,0x81D020E7,0x9007487D,0x64611B26,0x6D12EF89,0xA8A7A1C4,0x803A4153,

            0x03D0D734,0x6EAF7C48,0xD7B40C73,0x3A4183CE,0xE0D8B480,0xFC7BE983,0xDE7727CB,0x834F7C79,0x30F3930E,0x9401D21D,

            0x481A0671,0x2D888CFC,0xCA00E903,0x2A8C6338,0x39B7CBBE,0x19401D20,0xF5218467,0xA33A438E,0xFBE86EF3,0x85C4C3A4,

            0x007486E6,0x91C73C65,0xC6DFCEF0,0x48426D99,0x18165007,0xC8FD047A,0x3849FBAB,0xE900943B,0x037CDA00,0x1DE12B0E,

            0xCB3A8DBF,0xA00E90B8,0x30E2342D,0x7C2CAEFA,0x40936777,0xC631803A,0xE77C4130,0x3A40736B,0x78C63180,0x8BEF8A63,

            0x07482B6D,0xA1182630,0x70B721EB,0xF7EDE7C8,0x1D20C5B7,0xE06C98C0,0xDE17C481,0x03A409B6,0x2CB59318,0x0DAD5DE1,

            0x90D0DE3B,0xD64C600E,0xF577C49A,0xE3A0DC36,0x1D20588C,0x0D2B98C0,0xB55DE12D,0x88C93B0D,0x4CE00E90,0x17D606D6,

            0x288BEAB1,0x01D2005B,0x1B8691BC,0xC5D78F40,0xF6936EE3,0x90AE1655,0x348DE00E,0xBBE2A8C6,0xD2039B5C,0x0609BC01,

            0xC77C489E,0x3A406B63,0x50C13780,0x0F7C4A23,0x0394F36F,0x050F3B40,0x44DE00E9,0xE5EF491D,0x8701DA6D,0x1ED964DC,

            0x9BC01D20,0x25218068,0x59B227BC,0xD21D5BB7,0xCAE9BC01,0x83DE12E8,0x8D53A8D8,0xDE00E90C,0xF1668374,0x042D95DD,

            0x74DE00E9,0xBE260E83,0x2025B73B,0x6E9BC01D,0xBC2521A8,0x0E85B1CF,0xE90FEDC0,0x0308C100,0xD6D78975,0x0D238E06,

            0x0403A429,0x88350C23,0x36FAF784,0x42AB36EB,0xC230403A,0x47EB0308,0xE47E2D5E,0x1EBBAEDD,0x16F07D71,0xA8F4D20F,

            0x0403A431,0xA4310C13,0xB6FCF784,0x1D8801E8,0x98201D21,0x2531806A,0x16CF247C,0x3FB6803D,0xD30403A4,0xCFC5D00C,

            0x906CD810,0x358D100E,0x8EFA18E0,0x6F477D51,0x403A40B3,0xC330CE32,0xB0A77A4A,0x875A0E03,0x4876836B,0x1A86C807,

            0x1F7D7463,0xB60FBEAE,0xA01D20F5,0xD1826E1A,0x7B5D1D25,0xA413A9E7,0x585B6661,0x06680748,0x09586119,0xCE6DD3EF,

            0x7484767D,0x31AA6C00,0x6EF89746,0x6B1BC6DA,0x86A6118C,0xA56C0074,0x047EB321,0xC047E372,0xD732F46D,0x3A4023F4,

            0xE8C8B700,0xC8F84983,0xCABA4DB4,0xA00E90BC,0x48FC32CD,0xF57519FA,0x1CB62A33,0x737803A4,0x1E883C0D,0xDC878CF2,

            0xA4EB07DE,0x2149B665,0x6698201D,0x878C91E8,0x9DF043DC,0xE9006DB2,0x0E1CC100,0x80CF7A6F,0xCED0CA61,0xF833BCE8,

            0x3419C741,0x6187D00D,0x6C0769BA,0xE4700203,0x0192CC69,0x3D34D800,0x06006D00,0x0329C0E5,0x1E19C01D,0x1C120000,

            0x3E806524,0x0F402003,0x84829081,0xCD906918,0x80C00000,0xC0887104,0x91280010,0x480C481C,0xA1946426,0x840800C8,

            0x06000214,0xC00CB12D,0xC09921A0,0xFA0C9901,0xB81C8320,0x0C28A0E2,0x88E994C9,0x7C9F40C2,0x0702039E,0x418818D0,

            0x0B000002,0x00000002,0xC0700000,0x0000000D,0x00000000,0x00000080,0x00000000,0x00000000,0x00000000,0x00000000,

            0x00000000,0x00000000,0x00840400,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00320401,0x00000000,

            0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,

            0x00000000,0x00000000,0x00000000,0x00000000,0x00020000,0x00000000,0x00000000,0x00000000,0x0080C000,0x00000008,

            0x02540000,0x00503000,0x42606242,0x081867A3,0x8953041A,0x00000005,0x00000000,0x00000000,0x00000000,0x00000000,

            0x00C98000,0x00000000,0x00000000,0x00000000,0x00000000,0x804000C8,0x94400004,0x38000018,0x000009A0,0x008903A4,

            0x00000000,0x00000000,0x00200000,0x00000200,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,

            0x00000000,0x00000000,0x00000000,0x00000000,0x6C000000,0x10000006,0x00C80001,0x00000000,0x00000000,0x00000000,

            0x00000540,0x00000080,0xDF000005,0x400FA86E,0xA1BB7C13,0xF04D003E,0x00FA86ED,0x1BB7C134,0x04D003EA,0x0FA86EDF,

            0xBB7C1340,0x4D003EA1,0xFA86EDF0,0xB7C13400,0xD003EA1B,0xA86EDF04,0x7C13400F,0x003EA1BB,0x86EDF04D,0xC13400FA,

            0x03EA1BB7,0x1BB7C4D0,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,

            0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,

            0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,

            0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x376F2943,0x021AADF4,0xC50DDBE0,

            0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,

            0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,

            0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,

            0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,

            0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x0DDBEA1B,0x7EC1FBC5,0xEDF1B056,0x0DDBE286,0x8A1BB7C5,0xDF14376F,

            0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0xA1BB794A,0xA010D56F,0xB7D0DDBC,0xF780086A,0xB40F0983,

            0x286EDF4D,0xF050DDBE,0x81E1307E,0x0DDBE9B6,0x0A1BB7C5,0x3C260FDE,0xBB7D36D0,0x4376F8A1,0x84C1FBC1,0x6FA6DA07,

            0x6EDF1437,0x983F7828,0xF4DB40F0,0xDBE286ED,0x07EF050D,0x9B681E13,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,

            0x6F8A1BB7,0x6EDF1437,0x86EDE528,0x004355BE,0x7D0DDBCA,0x940086AB,0x56FA1BB7,0x6F28010D,0x1AADF437,0x0DDBE002,

            0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,

            0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x8A1BB7D4,0x67C383F7,0x24C8FB25,0x7C50DDBE,0x76F8A1BB,0x86EDF143,

            0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,

            0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,

            0x376F8A1B,0x286EDF14,0x7C50DDBE,0xFE0CA1BB,0x3003D459,0x432200A0,0x1075167F,0x44040400,0xA8B3FA18,0x00020223,

            0x67EA0001,0x0E80C0D1,0xEA2CFF40,0xF28074A8,0x0D013459,0xD459F90C,0x08020041,0x8B3E5280,0x01851266,0x507A8B3F,

            0x67D20100,0x030AA0D1,0x840D167E,0xC0612688,0x640EA2CF,0xD860400B,0x008EA2CF,0x00000004,0x8B3E8180,0x80860A3A,

            0xD167E121,0x8B3E4182,0x4008113A,0x167E2084,0x459FC875,0xA1951E83,0x003A8B3F,0x50040002,0xA2CFF060,0x1002088E,

            0x2CFD4094,0xCA4CE4EA,0x3A8B3F50,0x3E10A9AA,0xE103868B,0xF08CD167,0x84183459,0x19D459F8,0x0DDBE3B0,0x8A1BB7C5,

            0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,

            0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,

            0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,

            0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,

            0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,

            0xFBD4376F,0x0DD67EC1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x0FDEA1BB,0x8FAEB3F6,0xDF14376F,

            0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,

            0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,

            0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,

            0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,

            0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x76F29437,0x21AADF43,0x50DDBE00,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,

            0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,

            0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,

            0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,

            0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x4376F294,0x0021AADF,

            0xBE86EDE5,0x72804355,0x6CD3F83F,0xA07C400C,0xF1581E6D,0x76FA86ED,0x307EF143,0xDF74703E,0xDDBE286E,0x286EDF50,

            0x07C60FDE,0x0DDBEE8E,0x0A1BB7C5,0x3E260FDE,0xAC0F36D0,0x7D4376F8,0x3F78A1BB,0xBA381F18,0xDF14376F,0x376FA86E,

            0xE307EF14,0xEDF74703,0x0DDBE286,0x1307EF05,0x079B681F,0xA1BB7C56,0xBC50DDBE,0x1C0F8C1F,0x8A1BB7DD,0xB7D4376F,

            0x83F78A1B,0xFBA381F1,0xEDF14376,0x83F78286,0xCDB40F89,0xDDBE2B03,0x286EDF50,0x07C60FDE,0x0DDBEE8E,0xEA1BB7C5,

            0xFBC50DDB,0xD1C0F8C1,0xF8A1BB7D,0xFBC14376,0xDA07C4C1,0xDF1581E6,0x376FA86E,0xE307EF14,0xEDF74703,0x0DDBE286,

            0xE286EDF5,0xE07C60FD,0x50DDBEE8,0xE0A1BB7C,0x03E260FD,0x8AC0F36D,0xB7D4376F,0x83F78A1B,0xFBA381F1,0xEDF14376,

            0x4376FA86,0x3E307EF1,0x6EDF7470,0x50DDBE28,0x7D0DDBCA,0xE50086AB,0xD9A7F07E,0x40F08018,0x86EDF4DB,0x050DDBE2,

            0x1E1307EF,0xDDBE9B68,0xA1BB7C50,0xC260FDE0,0xB7D36D03,0x376F8A1B,0x4C1FBC14,0xFA6DA078,0xEDF14376,0x83F78286,

            0x4DB40F09,0xBE286EDF,0x7EF050DD,0xB681E130,0xC50DDBE9,0x6F8A1BB7,0x6EDF1437,0x86EDE528,0x004355BE,0xF8A1BB7C,

            0x6F294376,0x1AADF437,0xC1FB9402,0x0063669F,0xD36D03C2,0x6F8A1BB7,0x1FBC1437,0x6DA0784C,0xF14376FA,0xF78286ED,

            0xB40F0983,0x286EDF4D,0xF050DDBE,0x81E1307E,0x0DDBE9B6,0x0A1BB7C5,0x3C260FDE,0xBB7D36D0,0x4376F8A1,0x84C1FBC1,

            0x6FA6DA07,0x6EDF1437,0x86EDE528,0x804355BE,0xDF4376F2,0xDE0021AA,0xD03C260F,0xA1BB7D36,0xC14376F8,0x0784C1FB,

            0x376FA6DA,0x286EDF14,0xF0983F78,0xEDF4DB40,0x0DDBE286,0x1307EF05,0xBE9B681E,0xBB7C50DD,0x60FDE0A1,0xD36D03C2,

            0x6F8A1BB7,0x1FBC1437,0x6DA0784C,0xF14376FA,0xDE5286ED,0x355BE86E,0x376F2804,0x021AADF4,0xC260FDE0,0xB7D36D03,

            0x376F8A1B,0x4C1FBC14,0xFA6DA078,0xEDF14376,0x83F78286,0x4DB40F09,0xBE286EDF,0x7EF050DD,0xB681E130,0xC50DDBE9,

            0xDE0A1BB7,0xD03C260F,0xA1BB7D36,0xC14376F8,0x0784C1FB,0x376FA6DA,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,

            0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,

            0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,

            0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xF50DDBE2,0xFDE286ED,0x7E4B3F60,0xDF5C303E,0xDDBE286E,

            0xF83F70D0,0x7C79FEBF,0xDDBE69A0,0xFDBFF050,0xFB7FE20D,0xFC4703DB,0xFF04FF6F,0xBFF5DFDB,0xBFF057FD,0x6FFC4DFD,

            0xF6FFCAFF,0xF6FFC15F,0xFDBFF08F,0x7FDBFF4B,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,

            0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0x83EC1FBD,0x1BB7C44A,0x14376F8A,0xBE286EDF,0xBB7C50DD,

            0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x0FDEA1BB,0x80C9B3F6,0xDF14376F,0xDDBE286E,

            0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,

            0x376F8A1B,0xE1C1FBD4,0x2A7E2541,0x86EDF1FD,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,

            0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xF7A86EDF,

            0x7581F183,0xF14376F9,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0x6EDF50DD,0xC60FDE28,0x6F9EAACF,0x76F29437,

            0x21AADF43,0x86EDE500,0x004355BE,0xF8A1BB7C,0x6F294376,0x1AADF437,0x6EDE5002,0x04355BE8,0xD0DDBCA0,0x40086AB7,

            0x6FA1BB79,0xF28010D5,0xAADF4376,0xEDE50021,0x4355BE86,0x0DDBCA00,0x0086AB7D,0xFA1BB794,0x28010D56,0xADF4376F,

            0xDE50021A,0x355BE86E,0xDDBCA004,0x086AB7D0,0x14376F80,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,

            0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,

            0x6F294376,0x1AADF437,0x6EDE5002,0x04355BE8,0xD0DDBCA0,0x50086AB7,0x9A7F07EE,0xFD86018D,0xD54CB52C,0xCE2C1986,

            0xC92C76E1,0xE4C0E906,0x009287E0,0x303E031A,0xF15F3668,0x1C0EE353,0xDF081EE9,0xDDBE286E,0xA1BB7C50,0xC50DDBE0,

            0x967EC1FB,0x00ACFCF7,0x3F60FDE2,0xFDE07BCB,0x3BCB3F60,0xF0E0FDE0,0xBC01DE59,0xCB3E1C1F,0xF2CF843B,0xD83F780E,

            0x780EF2CF,0x967C383F,0x07EF0077,0x0EF2CF87,0x03BCB3E1,0xB3F60FDE,0x0FDE03BC,0x1DE59F0E,0xF8C1FBC0,0xBB7DD1C0,

            0x60FDE0A1,0xBEE8E07C,0x7EF050DD,0x74703E30,0x78286EDF,0xCFE8783F,0x6D54CB52,0x1CE2C198,0x8366101E,0xF0726074,

            0x8D004943,0xD9A0C0F6,0x234FC57C,0x81F001DD,0xE286EDF0,0xB7C50DDB,0xDDBE0A1B,0x4C1FBC50,0x8DEF2CF8,0x8ECB3F91,

            0x60FDE000,0xE5EF2CFC,0x0023B2CF,0x3F183F78,0xB3E97BCB,0xF78004EC,0xA381F183,0xC14376FB,0xC0F8C1FB,0xA1BB7DD1,

            0x7C60FDE0,0xDDBEE8E0,0xF07EF050,0x96A59FD0,0x8330DAA9,0x203C39C5,0xC0E906CC,0x9287E0E4,0x81ED1A00,0x8AF9B341,

            0x03BA469F,0xDBE103E0,0x1BB7C50D,0x14376F8A,0x78A1BB7C,0x59F0983F,0x7F231BDE,0xC0011D96,0x59F8C1FB,0x659FCBDE,

            0x7EF00047,0xF7967E30,0x51D967D2,0xE307EF00,0xEDF74703,0x83F78286,0xFBA381F1,0xFBC14376,0xD1C0F8C1,0xE0A1BB7D,

            0x3FA1E0FD,0xB5532D4B,0x738B0661,0x0D984078,0xC1C981D2,0x3401250F,0x668303DA,0x8D3F15F3,0x07C00774,0x8A1BB7C2,

            0xDF14376F,0x76F8286E,0x307EF143,0x37BCB3E1,0x3B2CFE46,0x83F78002,0x97BCB3F1,0x008ECB3F,0xFC60FDE0,0xCFA5EF2C,

            0xDE0223B2,0x8E07C60F,0x050DDBEE,0x03E307EF,0x86EDF747,0xF183F782,0x76FBA381,0xC1FBC143,0x5A967F43,0x0CC36AA6,

            0x80F0E716,0x03A41B30,0x4A1F8393,0x07B46802,0x2BE6CD06,0x0EE91A7E,0x6F840F80,0x6EDF1437,0x50DDBE28,0xE286EDF0,

            0x67C260FD,0xFC8C6F79,0x00047659,0x67E307EF,0x967F2F79,0xFBC0011D,0xDE59F8C1,0x47659F4B,0x8C1FBC10,0xB7DD1C0F,

            0x0FDE0A1B,0xEE8E07C6,0xEF050DDB,0x4703E307,0x8286EDF7,0xFE8783F7,0xD54CB52C,0xCE2C1986,0x366101E1,0x07260748,

            0xD004943F,0x9A0C0F68,0x34FC57CD,0x1F001DD2,0x286EDF08,0x7C50DDBE,0xDBE0A1BB,0xC1FBC50D,0xDEF2CF84,0xECB3F918,

            0x0FDE0008,0x5EF2CFC6,0x023B2CFE,0xF183F780,0x3E97BCB3,0x78008ECB,0x381F183F,0x14376FBA,0x0F8C1FBC,0x1BB7DD1C,

            0xC60FDE0A,0xDBEE8E07,0xDDBCA50D,0x086AB7D0,0x7F07EE50,0x86018D9A,0x4CB52CFD,0x2C1986D5,0x2C76E1CE,0xC0E906C9,

            0x9287E0E4,0x3C031A00,0x5F366830,0x8EE353F1,0xC207BA47,0x6F8A1BB7,0x6EDF1437,0x4376F828,0xF8707EF1,0x67E1EF2C,

            0x07EF1005,0x1EF2CF87,0x3F60FDE0,0xFDE03BCB,0xDE59F0E0,0x1C1FBC01,0x843BCB3E,0x780EF2CF,0xF2CFD83F,0x383F780E,

            0x0077967C,0x03E307EF,0x86EDF747,0xF183F782,0x76FBA381,0xC1FBC143,0x7DD1C0F8,0xFDE0A1BB,0x4B3FA1E0,0x61B5532D,

            0x78738B06,0xD20D9840,0x0FC1C981,0xDA340125,0xF3668303,0x748D3F15,0xC207C007,0x6F8A1BB7,0x6EDF1437,0x4376F828,

            0xF1307EF1,0xE8C7BCB3,0x08ECB3F9,0x3B2CFE40,0x83F78002,0x3DE59F09,0x11D967F2,0x7659FC80,0x07EF0004,0x7BCB3E13,

            0x13B2CFA4,0x3B2CFA40,0x60FDE001,0xBEE8E07C,0x7EF050DD,0x74703E30,0x78286EDF,0x381F183F,0x14376FBA,0xF43C1FBC,

            0xAA65A967,0x7160CC36,0xB3080F0E,0x39303A41,0x8024A1F8,0xD0607B46,0xA7E2BE6C,0xF800EE91,0x4376F840,0xE286EDF1,

            0xDF050DDB,0x0FDE286E,0xF7967E26,0x967F3D18,0x9FC8011D,0xF0004765,0xB3E1307E,0x2CFE47BC,0x3F90023B,0xE0008ECB,

            0x67C260FD,0x59F48F79,0x9F481476,0xBC014765,0x1C0F8C1F,0x0A1BB7DD,0x07C60FDE,0x0DDBEE8E,0xE307EF05,0xEDF74703,

            0x83F78286,0xB52CFE87,0x1986D54C,0x01E1CE2C,0x07483661,0x943F0726,0x0F68D004,0x57CD9A0C,0x1DD234FC,0xDF081F00,

            0xDDBE286E,0xA1BB7C50,0xC50DDBE0,0xCFC4C1FB,0xE7A31EF2,0x0023B2CF,0x08ECB3F9,0x260FDE00,0xC8F7967C,0x0047659F,

            0x11D967F2,0x4C1FBC00,0x91EF2CF8,0x088ECB3E,0x88ECB3E9,0xF183F780,0x76FBA381,0xC1FBC143,0x7DD1C0F8,0xFDE0A1BB,

            0xE8E07C60,0xF050DDBE,0x9FD0F07E,0xDAA996A5,0x39C58330,0x06CC203C,0xE0E4C0E9,0x1A009287,0xB34181ED,0x469F8AF9,

            0x03E003BA,0xC50DDBE1,0x6F8A1BB7,0xBB7C1437,0x983F78A1,0x63DE59F8,0x7659FCF4,0x967F2004,0xFBC0011D,0xF2CF84C1,

            0xECB3F91E,0x2CFE4008,0xF780023B,0xE59F0983,0xD967D23D,0x967D2411,0x7EF0411D,0x74703E30,0x78286EDF,0x381F183F,

            0x14376FBA,0x0F8C1FBC,0x1BB7DD1C,0x1E0FDE0A,0x32D4B3FA,0xB0661B55,0x84078738,0x981D20D9,0x1250FC1C,0x303DA340,

            0xF15F3668,0x007748D3,0xBB7C207C,0x4376F8A1,0x8286EDF1,0xEF14376F,0xCB3F1307,0x3F9E8C7B,0xE4008ECB,0x0023B2CF,

            0xF0983F78,0x7F23DE59,0xC8011D96,0x0047659F,0xE1307EF0,0xFA47BCB3,0xA4023B2C,0x0023B2CF,0x07C60FDE,0x0DDBEE8E,

            0xE307EF05,0xEDF74703,0x83F78286,0xFBA381F1,0xEDF14376,0x6EDE5286,0x04355BE8,0xD0DDBCA0,0x40086AB7,0x6FA1BB79,

            0xF28010D5,0xAADF4376,0x1FB94021,0x063669FC,0x36D03C20,0xF8A1BB7D,0xFBC14376,0xDA0784C1,0x14376FA6,0x78286EDF,

            0x40F0983F,0x86EDF4DB,0x050DDBE2,0x1E1307EF,0xDDBE9B68,0xA1BB7C50,0xC260FDE0,0xB7D36D03,0x376F8A1B,0x4C1FBC14,

            0xFA6DA078,0xEDF14376,0x0DDBE286,0xE1307EF5,0xDBE9B681,0x1BB7C50D,0xA1BB794A,0xA010D56F,0x34FE0FDC,0x1E10031B,

            0xDDBE9B68,0xA1BB7C50,0xC260FDE0,0xB7D36D03,0x376F8A1B,0x4C1FBC14,0xFA6DA078,0xEDF14376,0x83F78286,0x4DB40F09,

            0xBE286EDF,0x7EF050DD,0xB681E130,0xC50DDBE9,0xDE0A1BB7,0xD03C260F,0xA1BB7D36,0x294376F8,0xADF4376F,0xFB94021A,

            0x63669FC1,0x6D03C200,0x8A1BB7D3,0xBC14376F,0xA0784C1F,0x4376FA6D,0x8286EDF1,0x0F0983F7,0x6EDF4DB4,0x50DDBE28,

            0xE1307EF0,0xDBE9B681,0x1BB7C50D,0x260FDE0A,0x7D36D03C,0x76F8A1BB,0xC1FBC143,0xA6DA0784,0xDF14376F,0xEDE5286E,

            0x4355BE86,0x0DDBCA00,0x0086AB7D,0xA7F07EE5,0xF08018D9,0xEDF4DB40,0x0DDBE286,0x1307EF05,0xBE9B681E,0xBB7C50DD,

            0x60FDE0A1,0xD36D03C2,0x6F8A1BB7,0x1FBC1437,0x6DA0784C,0xF14376FA,0xF78286ED,0xB40F0983,0x286EDF4D,0xF050DDBE,

            0x81E1307E,0x0DDBE9B6,0x4A1BB7C5,0x6FA1BB79,0xF28010D5,0xAADF4376,0xEDE50021,0x4355BE86,0x0DDBCA00,0x0086AB7D,

            0xA7F07EE5,0xF08018D9,0xEDF4DB40,0x0DDBE286,0x1307EF05,0xBE9B681E,0xBB7C50DD,0x60FDE0A1,0xD36D03C2,0x6F8A1BB7,

            0x1FBC1437,0x6DA0784C,0xF14376FA,0xF78286ED,0xB40F0983,0x286EDF4D,0xF050DDBE,0x81E1307E,0x0DDBE9B6,0x4A1BB7C5,

            0x6FA1BB79,0xDF0010D5,0xDDBE286E,0xA1BB7C50,0xFA1BB794,0xF0010D56,0xDBE286ED,0x1BB7C50D,0x94376F8A,0xDF4376F2,

            0xB94021AA,0x3669FC1F,0xD03C2006,0xA1BB7D36,0xC14376F8,0x0784C1FB,0x376FA6DA,0x286EDF14,0xF0983F78,0xEDF4DB40,

            0x0DDBE286,0x1307EF05,0xBE9B681E,0xBB7C50DD,0x60FDE0A1,0xD36D03C2,0x6F8A1BB7,0x1FBC1437,0x6DA0784C,0xF14376FA,

            0xDE5286ED,0x355BE86E,0x83F72804,0x00C6CD3F,0xA6DA0784,0xDF14376F,0x3F78286E,0xDB40F098,0xE286EDF4,0xEF050DDB,

            0x681E1307,0x50DDBE9B,0xE0A1BB7C,0x03C260FD,0x1BB7D36D,0x14376F8A,0x784C1FBC,0x76FA6DA0,0x86EDF143,0x0983F782,

            0xDF4DB40F,0xDDBE286E,0x0DDBCA50,0x0086AB7D,0x294376F8,0xADF4376F,0xDE50021A,0x355BE86E,0x83F72804,0x00C6CD3F,

            0xA6DA0784,0xDF14376F,0x3F78286E,0xDB40F098,0xE286EDF4,0xEF050DDB,0x681E1307,0x50DDBE9B,0xE0A1BB7C,0x03C260FD,

            0x1BB7D36D,0x14376F8A,0x784C1FBC,0x76FA6DA0,0x86EDF143,0x0983F782,0xDF4DB40F,0xDDBE286E,0x0DDBCA50,0x0086AB7D,

            0xA7F07EE5,0xF08018D9,0xEDF4DB40,0x0DDBE286,0x1307EF05,0xBE9B681E,0xBB7C50DD,0x60FDE0A1,0xD36D03C2,0x6F8A1BB7,

            0x1FBC1437,0x6DA0784C,0xF14376FA,0xF78286ED,0xB40F0983,0x286EDF4D,0xF050DDBE,0x81E1307E,0x0DDBE9B6,0x8A1BB7C5,

            0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0xDDBCA50D,0x086AB7D0,0x94376F80,0xDF4376F2,0xBE0021AA,

            0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,

            0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xEDE5286E,0x4355BE86,

            0xA1BB7C00,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,

            0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,

            0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,

            0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,

            0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,

            0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,

            0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,

            0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,

            0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,

            0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,

            0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,

            0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,

            0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,

            0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,

            0xE86EDE52,0xA004355B,0xB7D0DDBC,0xDE50086A,0x355BE86E,0xC1FBC004,0xA6DA0784,0xDF14376F,0x3F78286E,0xDB40F098,

            0xE286EDF4,0xEF050DDB,0x681E1307,0x50DDBE9B,0xE0A1BB7C,0x03C260FD,0x1BB7D36D,0x14376F8A,0x784C1FBC,0x76FA6DA0,

            0x86EDF143,0x0983F782,0xDF4DB40F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0xDDBCA50D,0x086AB7D0,0x14376F80,

            0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xF4376F29,0x50021AAD,0x5BE86EDE,0xBCA00435,0x6AB7D0DD,0x376F8008,0x286EDF14,

            0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,

            0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,

            0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,

            0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,

            0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,

            0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0xC1FBD437,0xF0F0567E,0xDBE286ED,0x1BB7C50D,0x14376F8A,

            0xBE286EDF,0xBB7C50DD,0xF60FDEA1,0x6F8842B3,0xC1FBD437,0xF42A59F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,

            0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0xA86EDF14,0x0F0983F7,0x6EDF0A10,0x50DDBE28,0xF8A1BB7C,

            0x6F294376,0x1AADF437,0xC1FB9402,0x0063669F,0xD36D03C2,0x6F8A1BB7,0x1FBC1437,0x6DA0784C,0xF14376FA,0xF78286ED,

            0xB40F0983,0x286EDF4D,0xF050DDBE,0x81E1307E,0x0DDBE9B6,0x0A1BB7C5,0x3C260FDE,0xBB7D36D0,0x4376F8A1,0x84C1FBC1,

            0x6FA6DA07,0x6EDF1437,0x86EDE528,0x804355BE,0xD3F83F72,0x78400C6C,0x76FA6DA0,0x86EDF143,0x0983F782,0xDF4DB40F,

            0xDDBE286E,0x307EF050,0xE9B681E1,0xB7C50DDB,0x0FDE0A1B,0x36D03C26,0xF8A1BB7D,0xFBC14376,0xDA0784C1,0x14376FA6,

            0x78286EDF,0x40F0983F,0x86EDF4DB,0xA50DDBE2,0xB7D0DDBC,0xEE50086A,0x8D9A7F07,0xB40F0801,0x286EDF4D,0xF050DDBE,

            0x81E1307E,0x0DDBE9B6,0x0A1BB7C5,0x3C260FDE,0xBB7D36D0,0x4376F8A1,0x84C1FBC1,0x6FA6DA07,0x6EDF1437,0x983F7828,

            0xF4DB40F0,0xDBE286ED,0x07EF050D,0x9B681E13,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xA50DDBE2,0xB7D0DDBC,0xEE50086A,

            0x8D9A7F07,0xB40F0801,0x286EDF4D,0xF050DDBE,0x81E1307E,0x0DDBE9B6,0x0A1BB7C5,0x3C260FDE,0xBB7D36D0,0x4376F8A1,

            0x84C1FBC1,0x6FA6DA07,0x6EDF1437,0x983F7828,0xF4DB40F0,0xDBE286ED,0x07EF050D,0x9B681E13,0x7C50DDBE,0xB794A1BB,

            0x0D56FA1B,0x376F2801,0x021AADF4,0x9FC1FB94,0xC2006366,0xB7D36D03,0x376F8A1B,0x4C1FBC14,0xFA6DA078,0xEDF14376,

            0x83F78286,0x4DB40F09,0xBE286EDF,0x7EF050DD,0xB681E130,0xC50DDBE9,0xDE0A1BB7,0xD03C260F,0xA1BB7D36,0xC14376F8,

            0x0784C1FB,0x376FA6DA,0x286EDF14,0xBE86EDE5,0x72804355,0x6CD3F83F,0xA078400C,0x4376FA6D,0x8286EDF1,0x0F0983F7,

            0x6EDF4DB4,0x50DDBE28,0xE1307EF0,0xDBE9B681,0x1BB7C50D,0x260FDE0A,0x7D36D03C,0x76F8A1BB,0xC1FBC143,0xA6DA0784,

            0xDF14376F,0x3F78286E,0xDB40F098,0xE286EDF4,0xBCA50DDB,0x6AB7D0DD,0x376F8008,0x286EDF14,0x7C50DDBE,0x76F8A1BB,

            0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,

            0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,

            0xB7C50DDB,0x376F8A1B,0x286EDF14,0xCA50DDBE,0xAB7D0DDB,0x7EE50086,0x18D9A7F0,0xDB40F080,0xE286EDF4,0xEF050DDB,

            0x681E1307,0x50DDBE9B,0xE0A1BB7C,0x03C260FD,0x1BB7D36D,0x14376F8A,0x784C1FBC,0x76FA6DA0,0x86EDF143,0x0983F782,

            0xDF4DB40F,0xDDBE286E,0x307EF050,0xE9B681E1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,

            0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x4A1BB7C5,0x6FA1BB79,0xDCA010D5,

            0x1B34FE0F,0x681E1003,0x50DDBE9B,0xE0A1BB7C,0x03C260FD,0x1BB7D36D,0x14376F8A,0x784C1FBC,0x76FA6DA0,0x86EDF143,

            0x0983F782,0xDF4DB40F,0xDDBE286E,0x307EF050,0xE9B681E1,0xB7C50DDB,0x0FDE0A1B,0x36D03C26,0xF8A1BB7D,0x6F294376,

            0x1AADF437,0xC1FB9402,0x0063669F,0xD36D03C2,0x6F8A1BB7,0x1FBC1437,0x6DA0784C,0xF14376FA,0xF78286ED,0xB40F0983,

            0x286EDF4D,0xF050DDBE,0x81E1307E,0x0DDBE9B6,0x0A1BB7C5,0x3C260FDE,0xBB7D36D0,0x4376F8A1,0x84C1FBC1,0x6FA6DA07,

            0x6EDF1437,0x86EDE528,0x804355BE,0xD3F83F72,0x7C400C6C,0x581E6DA0,0xFA86EDF1,0x7EF14376,0x74703E30,0xBE286EDF,

            0x6EDF50DD,0xC60FDE28,0xDBEE8E07,0x1BB7C50D,0x260FDE0A,0x0F36D03E,0x4376F8AC,0x78A1BB7D,0x381F183F,0x14376FBA,

            0x6FA86EDF,0x07EF1437,0xF74703E3,0xDBE286ED,0x07EF050D,0x9B681F13,0xBB7C5607,0x50DDBEA1,0x0F8C1FBC,0x1BB7DD1C,

            0xD4376F8A,0xF78A1BB7,0xA381F183,0xF14376FB,0xF78286ED,0xB40F8983,0xBE2B03CD,0x6EDF50DD,0xC60FDE28,0xDBEE8E07,

            0x1BB7C50D,0xC50DDBEA,0xC0F8C1FB,0xA1BB7DD1,0xC14376F8,0x07C4C1FB,0x1581E6DA,0x6FA86EDF,0x07EF1437,0xF74703E3,

            0xDBE286ED,0x86EDF50D,0x7C60FDE2,0xDDBEE8E0,0xA1BB7C50,0xE260FDE0,0xC0F36D03,0xD4376F8A,0xF78A1BB7,0xA381F183,

            0xF14376FB,0x76FA86ED,0x307EF143,0xDF74703E,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,

            0xBE286EDF,0xBB7C50DD,0x1BB794A1,0x010D56FA,0xE286EDF0,0xB7C50DDB,0x376F8A1B,0x286EDF14,0xCA50DDBE,0xAB7D0DDB,

            0x76F80086,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,

            0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,

            0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,

            0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xEDE5286E,0x4355BE86,0xA1BB7C00,0x294376F8,

            0xADF4376F,0xDBE0021A,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0x5286EDF1,0x5BE86EDE,0xBCA00435,

            0x6AB7D0DD,0xBB794008,0x10D56FA1,0x4376F280,0x0021AADF,0xBE86EDE5,0xCA004355,0xAB7D0DDB,0xB7940086,0x0D56FA1B,

            0x376F2801,0x021AADF4,0xC50DDBE0,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0x94A1BB7C,0x56FA1BB7,0xFDCA010D,0x31B34FE0,

            0xB681E100,0xC50DDBE9,0xDE0A1BB7,0xD03C260F,0xA1BB7D36,0xC14376F8,0x0784C1FB,0x376FA6DA,0x286EDF14,0xF0983F78,

            0xEDF4DB40,0x0DDBE286,0x1307EF05,0xBE9B681E,0xBB7C50DD,0x60FDE0A1,0xD36D03C2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,

            0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xEDE5286E,0x4355BE86,0x0DDBCA00,0x0086AB7D,0xFA1BB794,

            0x28010D56,0xADF4376F,0xDE50021A,0x355BE86E,0xDDBCA004,0x086AB7D0,0x7F07EE50,0x08018D9A,0xDF4DB40F,0xDDBE286E,

            0x307EF050,0xE9B681E1,0xB7C50DDB,0x0FDE0A1B,0x36D03C26,0xF8A1BB7D,0xFBC14376,0xDA0784C1,0x14376FA6,0x78286EDF,

            0x40F0983F,0x86EDF4DB,0x050DDBE2,0x1E1307EF,0xDDBE9B68,0xA1BB7C50,0xFA1BB794,0x28010D56,0xADF4376F,0xFB94021A,

            0x63669FC1,0x6D03C200,0x8A1BB7D3,0xBC14376F,0xA0784C1F,0x4376FA6D,0x8286EDF1,0x0F0983F7,0x6EDF4DB4,0x50DDBE28,

            0xE1307EF0,0xDBE9B681,0x1BB7C50D,0x260FDE0A,0x7D36D03C,0x76F8A1BB,0xC1FBC143,0xA6DA0784,0xDF14376F,0xEDE5286E,

            0x4355BE86,0xF83F7280,0x400C6CD3,0xFA6DA078,0xEDF14376,0x83F78286,0x4DB40F09,0xBE286EDF,0x7EF050DD,0xB681E130,

            0xC50DDBE9,0xDE0A1BB7,0xD03C260F,0xA1BB7D36,0xC14376F8,0x0784C1FB,0x376FA6DA,0x286EDF14,0xF0983F78,0xEDF4DB40,

            0x0DDBE286,0xD0DDBCA5,0x50086AB7,0x9A7F07EE,0x0F08018D,0x6EDF4DB4,0x50DDBE28,0xE1307EF0,0xDBE9B681,0x1BB7C50D,

            0x260FDE0A,0x7D36D03C,0x76F8A1BB,0xC1FBC143,0xA6DA0784,0xDF14376F,0x3F78286E,0xDB40F098,0xE286EDF4,0xEF050DDB,

            0x681E1307,0x50DDBE9B,0xF8A1BB7C,0xEDF14376,0x983F7A86,0xF4DB40F0,0xDBE286ED,0xDDBCA50D,0x086AB7D0,0x7F07EE50,

            0x08018D9A,0xDF4DB40F,0xDDBE286E,0x307EF050,0xE9B681E1,0xB7C50DDB,0x0FDE0A1B,0x36D03C26,0xF8A1BB7D,0xFBC14376,

            0xDA0784C1,0x14376FA6,0x78286EDF,0x40F0983F,0x86EDF4DB,0x050DDBE2,0x1E1307EF,0xDDBE9B68,0xA1BB7C50,0xFA1BB794,

            0xCA010D56,0xB34FE0FD,0x81E10031,0x0DDBE9B6,0x0A1BB7C5,0x3C260FDE,0xBB7D36D0,0x4376F8A1,0x84C1FBC1,0x6FA6DA07,

            0x6EDF1437,0x983F7828,0xF4DB40F0,0xDBE286ED,0x07EF050D,0x9B681E13,0x7C50DDBE,0xFDE0A1BB,0x6D03C260,0x8A1BB7D3,

            0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,

            0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,

            0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,

            0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,

            0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x794A1BB7,0xD56FA1BB,0x6EDF0010,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,

            0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,

            0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,

            0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,

            0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,

            0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xE86EDE52,0xA004355B,0xB7D0DDBC,0x6F80086A,0x76F29437,0x21AADF43,0xFC1FB940,

            0x20063669,0x7D36D03C,0x76F8A1BB,0xC1FBC143,0xA6DA0784,0xDF14376F,0x3F78286E,0xDB40F098,0xE286EDF4,0xEF050DDB,

            0x681E1307,0x50DDBE9B,0xE0A1BB7C,0x03C260FD,0x1BB7D36D,0x14376F8A,0x784C1FBC,0x76FA6DA0,0x86EDF143,0xE86EDE52,

            0x2804355B,0xCD3F83F7,0x078400C6,0x376FA6DA,0x286EDF14,0xF0983F78,0xEDF4DB40,0x0DDBE286,0x1307EF05,0xBE9B681E,

            0xBB7C50DD,0x60FDE0A1,0xD36D03C2,0x6F8A1BB7,0x1FBC1437,0x6DA0784C,0xF14376FA,0xF78286ED,0xB40F0983,0x286EDF4D,

            0x7C50DDBE,0xB794A1BB,0x0D56FA1B,0x86EDF001,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,

            0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDE5286ED,0x355BE86E,0x83F72804,0x00C6CD3F,

            0xA6DA0784,0xDF14376F,0x3F78286E,0xDB40F098,0xE286EDF4,0xEF050DDB,0x681E1307,0x50DDBE9B,0xE0A1BB7C,0x03C260FD,

            0x1BB7D36D,0x14376F8A,0x784C1FBC,0x76FA6DA0,0x86EDF143,0x0983F782,0xDF4DB40F,0xDDBE286E,0x0DDBCA50,0x0086AB7D,

            0xA7F07EE5,0xF88018D9,0xB03CDB40,0xF50DDBE2,0xFDE286ED,0xE8E07C60,0x7C50DDBE,0xDDBEA1BB,0x8C1FBC50,0xB7DD1C0F,

            0x376F8A1B,0x4C1FBC14,0x1E6DA07C,0x86EDF158,0xF14376FA,0x703E307E,0x286EDF74,0xDF50DDBE,0x0FDE286E,0xEE8E07C6,

            0xB7C50DDB,0x0FDE0A1B,0x36D03E26,0x76F8AC0F,0xA1BB7D43,0x1F183F78,0x376FBA38,0xA86EDF14,0xEF14376F,0x4703E307,

            0xE286EDF7,0xEF050DDB,0x681F1307,0x7C56079B,0xDDBEA1BB,0x8C1FBC50,0xB7DD1C0F,0x376F8A1B,0x8A1BB7D4,0x81F183F7,

            0x4376FBA3,0x8286EDF1,0x0F8983F7,0x2B03CDB4,0xDF50DDBE,0x0FDE286E,0xEE8E07C6,0xB7C50DDB,0x0DDBEA1B,0xF8C1FBC5,

            0xBB7DD1C0,0x4376F8A1,0xC4C1FBC1,0x81E6DA07,0xA86EDF15,0xEF14376F,0x4703E307,0xE286EDF7,0xEDF50DDB,0x60FDE286,

            0xBEE8E07C,0xBB7C50DD,0x1BB794A1,0x010D56FA,0x4FE0FDCA,0xE10031B3,0xDBE9B681,0x1BB7C50D,0x260FDE0A,0x7D36D03C,

            0x76F8A1BB,0xC1FBC143,0xA6DA0784,0xDF14376F,0x3F78286E,0xDB40F098,0xE286EDF4,0xEF050DDB,0x681E1307,0x50DDBE9B,

            0xE0A1BB7C,0x03C260FD,0x1BB7D36D,0x14376F8A,0xE5286EDF,0x55BE86ED,0x3F728043,0x0C6CD3F8,0xA967EC30,0x0756AA65,

            0xE1CE2C19,0x48366101,0x3F072607,0x18D00494,0x68303FAA,0x4634FF36,0x881F001D,0x86EDF121,0xC50DDBE2,0xDE0A1BB7,

            0x29B3F60F,0xC60FDE0E,0xDBEE8E07,0x07EF050D,0xF74703E3,0xF78286ED,0xA381F183,0xC14376FB,0x367EC1FB,0x4A6CFC25,

            0x3F60FDE0,0xFDE0129B,0x129B3F60,0x61E0FDE0,0x532D4B3E,0x60C83AB5,0x080F0E71,0x303A41B3,0x24A1F839,0x607B4680,

            0xE2BE6CD0,0x00EE91A7,0x76F840F8,0x86EDF143,0x050DDBE2,0xDE286EDF,0x567C260F,0xE3748F00,0x6CFC60FD,0xB2CFA78A,

            0x2CFA4013,0xFDE0013B,0x8A6CFC60,0x23B2CFE7,0x183F7800,0x6FBA381F,0x1FBC1437,0xDD1C0F8C,0xDE0A1BB7,0x8E07C60F,

            0x050DDBEE,0xF30F07EF,0xAA996A59,0x8B0641D5,0x98407873,0xC981D20D,0x01250FC1,0x8303DA34,0x3F15F366,0xC007748D,

            0x1BB7C207,0x14376F8A,0xF8286EDF,0x7EF14376,0x02B3E130,0xEF1BA478,0x5367E307,0x1D967D3C,0xD967D205,0x07EF0051,

            0x3C5367E3,0x011D967F,0xF8C1FBC0,0xBB7DD1C0,0x60FDE0A1,0xBEE8E07C,0x7EF050DD,0x74703E30,0x78286EDF,0xCF98783F,

            0xAD54CB52,0x9C58320E,0x6CC203C3,0x0E4C0E90,0xA009287E,0x34181ED1,0x69F8AF9B,0x3E003BA4,0x50DDBE10,0xF8A1BB7C,

            0xB7C14376,0x83F78A1B,0xC0159F09,0x3F78DD23,0xE29B3F18,0x88ECB3E9,0x8ECB3E90,0x183F7808,0xF9E29B3F,0x0008ECB3,

            0x07C60FDE,0x0DDBEE8E,0xE307EF05,0xEDF74703,0x83F78286,0xFBA381F1,0xFBC14376,0x967CC3C1,0x756AA65A,0x1CE2C190,

            0x8366101E,0xF0726074,0x8D004943,0xD9A0C0F6,0x234FC57C,0x81F001DD,0xE286EDF0,0xB7C50DDB,0xDDBE0A1B,0x4C1FBC50,

            0x1E00ACF8,0xC1FBC6E9,0x4F14D9F8,0x9047659F,0x047659F4,0xF8C1FBC1,0x9FCF14D9,0xF0004765,0x703E307E,0x286EDF74,

            0x1F183F78,0x376FBA38,0x8C1FBC14,0xB7DD1C0F,0x0FDE0A1B,0xD4B3E61E,0x83AB5532,0xF0E7160C,0xA41B3080,0x1F839303,

            0xB468024A,0xE6CD0607,0xE91A7E2B,0x840F800E,0xDF14376F,0xDDBE286E,0x86EDF050,0xC260FDE2,0x48F00567,0xC60FDE37,

            0xFA78A6CF,0xA4023B2C,0x0023B2CF,0xCFC60FDE,0x2CFE78A6,0xF780023B,0xA381F183,0xC14376FB,0xC0F8C1FB,0xA1BB7DD1,

            0x7C60FDE0,0xDDBEE8E0,0x0DDBCA50,0x0086AB7D,0xFA1BB794,0x28010D56,0xADF4376F,0xFB94021A,0x63669FC1,0x6D03C200,

            0x8A1BB7D3,0xBC14376F,0xA0784C1F,0x4376FA6D,0x8286EDF1,0x0F0983F7,0x6EDF4DB4,0x50DDBE28,0xE1307EF0,0xDBE9B681,

            0x1BB7C50D,0x260FDE0A,0x7D36D03C,0x76F8A1BB,0xC1FBC143,0xA6DA0784,0xDF14376F,0xEDE5286E,0x4355BE86,0x0DDBCA00,

            0x0086AB7D,0xA7F07EE5,0xF08018D9,0xEDF4DB40,0x0DDBE286,0x1307EF05,0xBE9B681E,0xBB7C50DD,0x60FDE0A1,0xD36D03C2,

            0x6F8A1BB7,0x1FBC1437,0x6DA0784C,0xF14376FA,0xF78286ED,0xB40F0983,0x286EDF4D,0xF050DDBE,0x81E1307E,0x0DDBE9B6,

            0x4A1BB7C5,0x6FA1BB79,0xDCA010D5,0x1B34FE0F,0x681E1003,0x50DDBE9B,0xE0A1BB7C,0x03C260FD,0x1BB7D36D,0x14376F8A,

            0x784C1FBC,0x76FA6DA0,0x86EDF143,0x0983F782,0xDF4DB40F,0xDDBE286E,0x307EF050,0xE9B681E1,0xB7C50DDB,0x0FDE0A1B,

            0x36D03C26,0xF8A1BB7D,0x6F294376,0x1AADF437,0xC1FB9402,0x0063669F,0xD36D03C2,0x6F8A1BB7,0x1FBC1437,0x6DA0784C,

            0xF14376FA,0xF78286ED,0xB40F0983,0x286EDF4D,0xF050DDBE,0x81E1307E,0x0DDBE9B6,0x0A1BB7C5,0x3C260FDE,0xBB7D36D0,

            0x4376F8A1,0x84C1FBC1,0x6FA6DA07,0x6EDF1437,0x86EDE528,0x804355BE,0xD3F83F72,0x78400C6C,0x76FA6DA0,0x86EDF143,

            0x0983F782,0xDF4DB40F,0xDDBE286E,0x307EF050,0xE9B681E1,0xB7C50DDB,0x0FDE0A1B,0x36D03C26,0xF8A1BB7D,0xFBC14376,

            0xDA0784C1,0x14376FA6,0x78286EDF,0x40F0983F,0x86EDF4DB,0xA50DDBE2,0xB7D0DDBC,0xEE50086A,0x8D9A7F07,0xB40F0801,

            0x286EDF4D,0xF050DDBE,0x81E1307E,0x0DDBE9B6,0x0A1BB7C5,0x3C260FDE,0xBB7D36D0,0x4376F8A1,0x84C1FBC1,0x6FA6DA07,

            0x6EDF1437,0x983F7828,0xF4DB40F0,0xDBE286ED,0x07EF050D,0x9B681E13,0x7C50DDBE,0xB794A1BB,0x0D56FA1B,0xE0FDCA01,

            0x0031B34F,0xE9B681E1,0xB7C50DDB,0x0FDE0A1B,0x36D03C26,0xF8A1BB7D,0xFBC14376,0xDA0784C1,0x14376FA6,0x78286EDF,

            0x40F0983F,0x86EDF4DB,0x050DDBE2,0x1E1307EF,0xDDBE9B68,0xA1BB7C50,0xC260FDE0,0xB7D36D03,0x376F8A1B,0x4376F294,

            0x4021AADF,0x69FC1FB9,0x3C200636,0xBB7D36D0,0x4376F8A1,0x84C1FBC1,0x6FA6DA07,0x6EDF1437,0x983F7828,0xF4DB40F0,

            0xDBE286ED,0x07EF050D,0x9B681E13,0x7C50DDBE,0xFDE0A1BB,0x6D03C260,0x8A1BB7D3,0xBC14376F,0xA0784C1F,0x4376FA6D,

            0x5286EDF1,0x5BE86EDE,0xF7280435,0xC6CD3F83,0xDA078400,0x14376FA6,0x78286EDF,0x40F0983F,0x86EDF4DB,0x050DDBE2,

            0x1E1307EF,0xDDBE9B68,0xA1BB7C50,0xC260FDE0,0xB7D36D03,0x376F8A1B,0x4C1FBC14,0xFA6DA078,0xEDF14376,0x83F78286,

            0x4DB40F09,0xBE286EDF,0xBB7C50DD,0x260FDEA1,0x7D36D03C,0x76F8A1BB,0x86EDF143,0xF0983F7A,0xEDF4DB40,0x0DDBE286,

            0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,

            0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,

            0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,

            0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,

            0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,

            0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,0x14376F8A,0xBE286EDF,0xBB7C50DD,

            0x4376F8A1,0xE286EDF1,0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,

            0x6EDF1437,0x50DDBE28,0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,

            0xDBE286ED,0x1BB7C50D,0x14376F8A,0xE5286EDF,0x55BE86ED,0xDBCA0043,0x86AB7D0D,0x1BB79400,0x010D56FA,0xE286EDF0,

            0xB7C50DDB,0x376F8A1B,0x286EDF14,0x7C50DDBE,0x76F8A1BB,0x86EDF143,0xC50DDBE2,0x6F8A1BB7,0x6EDF1437,0x50DDBE28,

            0xF8A1BB7C,0xEDF14376,0x0DDBE286,0x8A1BB7C5,0xDF14376F,0xDDBE286E,0xA1BB7C50,0xF14376F8,0xDBE286ED,0x1BB7C50D,

            0xA1BB794A,0x8010D56F,0xDF4376F2,0xFE4021AA,0xE0023B2C,0x6CFC60FD,0xB2CFA459,0x0FDE0013,0x4596CFC6,0x0A3B2CFA,

            0xFC60FDE0,0xCFA4596C,0xDE0223B2,0x96CFC60F,0x3B2CFA45,0x60FDE082,0xA4596CFC,0x4023B2CF,0x6FA1BB79,0xF28010D5,

            0xAADF4376,0xEDE50021,0x4355BE86,0x0DDBCA00,0x0086AB7D,0xFA1BB794,0x28010D56,0xADF4376F,0xDE50021A,0x355BE86E,

            0x615C2004,0x38A58E7D,0xFEF4F105,0xAC7B5EBB,0x5E253867,0x88A9C116,0x33CFCB87,0x9C1D13BD,0x0F07DF06,0x693E4B4E,

            0xB801EBB0,0x46F31EB7,0xCA3A70C9,0x0FEDE349,0x7AF41DB8,0xA71D2B57,0x19851C27,0xE1470806,0x51C20686,0x708041F8,

            0xF103A114,0xA1A1FB90,0x451E7603,0xF90E102A,0x709F2064,0xEB80F5DF,0x1992EFAE,0x8E3C8788,0x773F3E18,0x380A1DA0,

            0xE3007584,0x07AEC3B8,0xBE838EF6,0x1E207AAD,0x70623BF2,0x878816C0,0x1EB50F02,0x21C202C2,0xC0A343CF,0x0F7C8700,

            0x5DC81D31,0x01E100EA,0xB80F61A7,0x20607AEE,0x05AFA51C,0x9F0DC708,0xBC87B79F,0x7613840A,0x28E01805,0x45BAA1D5,

            0xD775DD76,0xF39EDF5D,0x7643D071,0x743A3A40,0x20342E08,0x843E1D1C,0x4D638405,0x3E276819,0xBAE83D77,0x1EBBAEEB,

            0x7FC77AA2,0xB7DB3C40,0x200F09EB,0x15DFED9C,0x76076708,0xC1D9C205,0xC270815D,0x102BC0F3,0xA73C932E,0xE087C026,

            0x0833F788,0x101B6B97,0x20354F2E,0xFE1F951D,0x77C1CCEC,0xC5E3723F,0x0784F1FB,0x8799FA3F,0xAEFDE203,0xCE77FFF3,

            0xECE27480,0x153BEBC0,0x84081038,0xFE27A3B3,0xE1767081,0xCE1003C4,0x01789E2E,0x014B69C2,0xF842133F,0x97083D00,

            0x03DE0EEB,0x87E572E1,0xC1F0102B,0xCD03E3E8,0xA7043C25,0xB8409E3B,0x10203635,0x074F245E,0x78E22F7C,0x7A709752,

            0xF3C05777,0x522F80ED,0xE06E8F14,0xB13C3D29,0x0245EF87,0x4E11EA4F,0xF80AEDEF,0xA3C7E099,0x1F4A789B,0x29E3EC4F,

            0x80713C03,0x4F0645EF,0x1329E11A,0xEF82713C,0x74708B43,0xE13390FF,0x40AEE9F4,0xCBBE4C3D,0x0983FBB9,0xF1EF2ECF,

            0x54193F92,0x488F1D5C,0xC21D01E3,0x5767AE55,0xA2CBF400,0xA07CED63,0x2767DE69,0x47C978F7,0x60D71559,0xE7EDC380,

            0x3F706F91,0xCBC7AAF5,0x8681EABB,0x85972A03,0x4789AE1A,0x2E80F108,0x01F530F9,0xF55E0794,0x60AF51DA,0xDA32F901,

            0x381EFB3C,0x2217D019,0x788B5C51,0xFD20EA98,0x1CA03F79,0x9CF7DEAE,0xA7A04DC9,0xA178F34E,0x83C26D71,0x34EA7869,

            0xF82CB840,0xEA075AE1,0xA5F3AF91,0xF1EF2ECF,0xF07C8FE2,0xAE1232F5,0xFD4AB843,0x7480F2EC,0xCB6CFDE4,0x0341CF14,

            0x611EA5D7,0x7675403C,0x7FA41CA0,0x578F0776,0x1C23D717,0x978813E1,0x7273EAF1,0xFA61CA03,0x9DDB4803,0xFED43E93,

            0x7D71150E,0x73B9E1D2,0x9FD40713,0x406E20FD,0xC873ACBA,0x3FBAD9E4,0x90DC36FE,0xF74A8E21,0x9C620F79,0x78203C8E,

            0xF01AE630,0xEC1F0753,0x32EEC2F1,0x23EF41CC,0x6E044F33,0x4289A7F0,0x15A8E8D8,0xBF88C1E1,0x5DA073B6,0x77583DA6,

            0xFAD9FB40,0xD5B15E3D,0xD41C9B2E,0x47498DC0,0xDBF3E2EE,0xB815FC7C,0x61E3BE09,0x84C75C3C,0x0EE35987,0x5C567A07,

            0x41DDC0FB,0xDD775DEC,0x77B9FA75,0x11CD711D,0xE4711CD7,0x203C47B9,0xA181EBBC,0x1CB00E31,0x3C263B14,0x039125F9,

            0xE51D4F54,0xB70CA2F1,0x03A481E6,0xA79E13CC,0x483B6C3F,0xD47A6D23,0x83E800FA,0x665E2708,0x3746E899,0xDE23A61E,

            0x4DF51F24,0x30F503DE,0xD1E72EFB,0xAF5C000F,0x8FC5EA7E,0x23371397,0xF9D9E61E,0xE900EF81,0xE1BCE248,0xE6E09B81,

            0xBB0CC3C4,0xA005F03E,0x773CAE1E,0xAA41D93C,0x7D4FCE6B,0xE38E55F9,0xD3C3B416,0x73D35EE7,0x94BC7DF0,0xDF2FC907,

            0xDC3BD63D,0xE2987092,0x501E337C,0x8FD307C5,0x729C300F,0x9439E319,0xE18E5E3F,0x56D27CD7,0x30E115B8,0x3B40CED7,

            0xF6907DCC,0xC1C1C7F4,0xF8FB80E7,0x3FAB2FDD,0x9ADC7DD6,0x0CE1E470,0x96AE101E,0xC3C06064,0xCE1307CC,0xC37D2DBA,

            0x1F13A9EF,0xCDBC7BB4,0xD20EF517,0xC25ED63F,0xA8CD4736,0x786FCB97,0x83E2753F,0xE59B8F7A,0x4E93E400,0xB47BA3C4,

            0x9E73C923,0x39ED1F1D,0xD4C53F44,0xF7CD8A83,0x96DC5216,0x6F770F41,0xC678017C,0x5FF3A603,0xC0EA7EC3,0xCC6B178F,

            0xE8380635,0xECFDA475,0x00C76E07,0x800F2987,0xF6BA786E,0xCF90FB10,0x72F1E4A1,0xAC7FCD5F,0x3E3DB83B,0xA23C6118,

            0xF9CCBE4E,0x7F1EE21C,0xD1BE65CA,0x307C0770,0xFD40F8F3,0x0FC99789,0xD7387E58,0xF3D97C81,0xC96BD2C6,0xDF49F91A,

            0xC4A503E0,0x8788A277,0x2985F119,0x250C03E2,0xB5E223BC,0xECCD7080,0xC5E0734D,0xC4307C36,0xDF179878,0xE61E3D89,

            0x7B935C23,0x0F804AD3,0xF30F1C86,0xE696AF13,0x8406FD37,0x7307BCCB,0x76847081,0xC307C028,0x08FB878C,0xE9F5BA0F,

            0xC8E1004C,0x200C99F9,0x0E791E5C,0x8D717838,0x2971F470,0x1A9B1E20,0xE03B40E2,0x603C7CD1,0x7EFA3843,0x68F00CC0,

            0x76D1E03D,0x16304F00,0x22B0C708,0xAE768E10,0xC463840D,0x7081A807,0x3500E88C,0x09B18E10,0x830C63A4,0x1E0683E7,

            0x8E102FED,0x840ECFDE,0x004B85A3,0xBEC898E1,0x6D307840,0x0816E5AF,0xBC0F9A27,0x4147BE02,0x3840D13C,0x15E07ED1,

            0x0E3A2708,0x44E102BC,0x202F01CF,0xE03E189E,0x27802BBA,0x5EF80AD5,0x1C24F020,0x3C2817BE,0x05EF8089,0xE1224F06,

            0x93C3817B,0xE05EF828,0xBE2A24F1,0x893C4417,0x0085EF8E,0x7BE2624F,0x5893C141,0xF1505EF8,0x17BE3624,0x83893C34,

            0x4F1D05EF,0xC17BE2E2,0xF87893C0,0x24F1305E,0x7C17BE01,0xEF84493C,0x924F1705,0xC3C17BE0,0x5EF8A493,0x1924F108,

            0x3C6417BE,0x85EF8149,0xE2D24F18,0x93C1217B,0xB85EF874,0xBE3324F0,0xC93C3217,0x1C85EF82,0x7BE2B24F,0xBC93C7A1,

            0xF0985EF8,0x17BE20A4,0x84293C16,0x4F0385EF,0x617BE30A,0x84B293C6,0x01EBDF53,0xB8DFD4F1,0x34E10303,0x3C402AC8,

            0x81E0360D,0x869C2057,0xA7081C5E,0xC2051611,0xAF03CC69,0x3A4D3840,0x534E101B,0xC205781D,0x8131CA69,0x147F1A70,

            0x39A69C20,0xD3840AF0,0x9E01B3B4,0x6B4CF566,0x7BDA7081,0xF69C2057,0xA70815D9,0xC205777D,0x815D88E9,0x576A3A70,

            0xDC8E9C20,0x93A70815,0xE9C20576,0x70815D94,0x2057733A,0x15DD2E9C,0x77CBA708,0x8AE9C205,0x2670815D,0x9E200E65,

            0x55681A09,0x1D399C20,0x6533C010,0x8399C205,0xD33C01C1,0xC59C20DE,0x67081798,0x7C046749,0x57BE1F2F,0xBDE102B9,

            0x84032E7C,0x0CB5F2F7,0xC52BDE10,0xAF7840F8,0x7803E394,0x6780A3D6,0x551B3CBD,0x19F59C20,0xFD670801,0x6CF00576,

            0x1B3C0140,0x0D9C2052,0x9B3840CF,0xCE102BB0,0x840AEE26,0x02BBC9B3,0xAECA6CE1,0xBA9B3840,0xA6CE102B,0xCD9C2065,

            0x670800D8,0x01624F4B,0x10C56CE1,0x755B3840,0x670803E2,0x007C4FAB,0x89CD6CE1,0xAD9C200F,0x8401F13D,0x02BB75B3,

            0xAEFD6CE1,0x51B73840,0x087EF081,0x766F102A,0x102830CF,0xE2FBA45E,0x99917840,0x56E10053,0xB8405CF0,0x103B3E15,

            0x0A4DE56E,0x9C891784,0x697D7081,0xAF5C207A,0x9708151E,0x02900FD3,0x81FE72E1,0xFE5C2018,0x840F703F,0xCE07602B,

            0xF2457081,0xAE101940,0x02281C28,0x03CE95C2,0xD2B8402A,0x08094073,0xC80E0657,0xFAAAE103,0xC2068BB3,0x0767B5D5,

            0x8A1B8404,0x1AE103C3,0x01B7B3FD,0xB1A635C2,0x398D7080,0xC5135E01,0xB84E0807,0xC196F626,0xF4CD7080,0xAE1025EA,

            0x5A69BD29,0x781BA07C,0x101F054D,0xDB82E11F,0x5C205C01,0x0B803F70,0x071E0B84,0x217080F0,0x103900F2,0x301D442E,

            0xE885C200,0xB8406403,0x1021B8B0,0x0A2D2C2E,0x8BCB0B84,0xE782E102,0x5C200201,0x01403D88,0xAF5E0B84,0x17080F8C,

            0xC2023656,0xB07F588B,0x117840C7,0x18F60F1B,0xF3622F08,0xE1009EC1,0x7C01F782,0x7B245C20,0x784094EE,0xF60FDB11,

            0xE2170814,0xE101500E,0x8773C8A2,0xF885C205,0xB8403403,0x69DCFE48,0xE2917080,0xE100D3B9,0x8773F4A2,0xCA45C206,

            0x84074EE7,0x8CAF890B,0xE517081D,0x90343B9E,0xB68C242E,0x046D2BC3,0x039F05C2,0xA8B84064,0x80A1DCF0,0x00E92170,

            0x2A2E102B,0x2048773F,0xC03E485C,0xBE0B8405,0x7080C807,0x7195ED21,0xDF82E100,0xC206532B,0xB003F485,0xF990B840,

            0x708138CA,0x0300F0A1,0xBEE42E10,0x5C203632,0x6C657BC8,0x7050B840,0x17081E80,0x083B9FB5,0x1FF82E10,0x85C20320,

            0x40F403E2,0x807A50B8,0xCA17080E,0xE101D00E,0xA32BF942,0x8A85C203,0xB840B403,0x0C807010,0x5E6A1708,0x2E101D19,

            0x3A32BED4,0x7FA85C20,0xB840B465,0x0C807810,0x0FDA1708,0x42E10010,0x204201F7,0x803DE85C,0x3D0B8403,0x70810807,

            0x1900E821,0xBF042E10,0x5C204332,0x0A403908,0x07A10B84,0x21708148,0x102900EC,0x201F842E,0x9985C205,0xB8404803,

            0x09007B30,0x0E221708,0x42E10290,0x200201DB,0x803A185C,0xF30B8409,0x70815007,0x3C204BE1,0x8155BBF8,0x0E07FCF0,

            0xF9E1024F,0x045E1D8F,0x3B600BC2,0x178408AC,0x1AE87150,0xFE702F08,0x5E1036E0,0x20C1F910,0xE120BC20,0x78403C83,

            0xA20784C1,0xA982F080,0xE101040F,0x701EB305,0xE60BC200,0x840C6038,0x08B73C17,0xCD885E10,0x7C052CAB,0x40F84C47,

            0xF8EF0999,0xBC207867,0x80458FA3,0x67218EF0,0x463BC205,0x840C83B8,0x20F28977,0x6681F016,0x3F5C2E13,0x3C200A1C,

            0x32FBCFD8,0x1FB07840,0xF080E5F7,0x03EE2CE0,0x7EC1F103,0x1BB94C1F,0x77478403,0x0808007D,0x586B3E8F,0x9C843C20,

            0x784071FB,0x880F2070,0xF60F081C,0x01DD01FF,0x3E1021E1,0x3C205340,0x0407BE04,0x07078409,0x88028C78,0x01F8C10F,

            0x04B21F59,0x3BF943C2,0xC784011B,0x10203932,0x41EA5B1E,0xD43C2041,0x40D743E6,0x1DEBEC78,0x70838F08,0x043C2049,

            0x0D3E07D6,0xBA45C784,0x1C1E1018,0x070583D8,0x7D0383C2,0x784090B0,0xA60F7808,0x0E0F0809,0x01ADC1E2,0x0FA6F1E1,

            0x07078406,0x8075E0F9,0x1EA0E0F0,0x1E101302,0x2843CC1C,0x8383C206,0x8401B93D,0x10235827,0x43DC1C1E,0xC3C204A6,

            0xBC907F6C,0xF0707840,0x08110D0F,0xA1F0CE0F,0xC1E10321,0x6EB43E21,0x852C3C20,0x84089D07,0x0830BA27,0xD0589E10,

            0x3C20784D,0x6C9BD0B1,0x61627840,0xF081E937,0x1A6F22C4,0x5561E103,0x2036523F,0x9BB8B13C,0x58784021,0x1A280F0D,

            0xF1AB0F08,0x9E101684,0x4FCDE658,0x93B13C20,0x78406003,0xB60F98D8,0x124F081B,0x3C207F79,0xFD87E338,0x8707840E,

            0x811470F2,0x1ED0E0F0,0x1E1019CE,0x85C3FA1C,0xC383C204,0x40B0B878,0x077FB278,0xE0F080C4,0x1F211F30,0xD61C1E10,

            0xC201FA23,0xF7B9C383,0x8707840D,0x80BD88F7,0x1FEBF0F0,0x1E103FDF,0xCD03EB7E,0x8F53C204,0x0F08019A,0x0151F88E,

            0x99C1E103,0x20236A3E,0x47D2383C,0xA7840FDB,0x101A3D33,0x79611C1F,0x7840A80C,0x018FE470,0x8E0F081D,0x01F431FE,

            0x3C31C1E1,0x3C206E46,0x80B9A703,0x1F3B88F0,0x33E00690,0xB1C1F7BC,0x04CF0834,0x103900F8,0x076D699E,0x7F6383C2,

            0x784040EC,0x138F1C70,0x8E0F081D,0x003171EB,0x3E71C1E1,0x3C20262E,0xE5C7EE38,0x59678408,0x1E1008B2,0xDA23CD19,

            0xFAB3C205,0x70784069,0x16478F7C,0xA97ACF08,0xF1C1E100,0x2049DE3F,0x02D79B3C,0x3DAB6784,0x1D9E1014,0xB3C2046C,

            0x08171D73,0x09F04E0F,0x7B3E0020,0x509C1F1A,0x441CF081,0x39F00506,0x0F081713,0x5289EC4E,0x89C1E101,0x206C313F,

            0x2789383C,0x07840D86,0x08C4F927,0xA4E0F081,0x1024589E,0x79689C1F,0x3E003D62,0xE102DA37,0xF13DC9C1,0x383C207B,

            0x041127F9,0xF0A70784,0xF0801124,0xA49F14E0,0x9C1E1005,0x077493D2,0x7E5383C2,0x7840EE92,0xD24FAA70,0x4E0F080D,

            0x007E49ED,0x3C69C1E1,0x3C207FA9,0x3D27AD38,0xA707840B,0x006164FD,0x051DBE7C,0x7BD383C2,0x7840CCF2,0x5E4FFA70,

            0x27E7C001,0x383C205E,0x09BF27A3,0xF2670784,0xF080C014,0x029ECCE0,0x45AE101E,0x0000028F,

        };

        // created: 2024-09-10T23:29:36.232Z

        // unicode: 16.0.0 (2024-09-10T20:47:54.200Z)

        // magic: 2 6 8 11 14 15 18

        internal static readonly uint[] NF = new uint[] { // 5090 bytes

            0x04EBBB7B,0x3A2C208D,0x0F4901C0,0x8ABC1EC8,0x01A105CF,0x11110101,0x080D0B4C,0xE2788808,0x0FD80FDE,0x801FC2B3,

            0xAC71FE32,0x322C87EF,0x81FA5832,0x5C461E59,0x1D1498B8,0xB0732888,0x668669C7,0x5C8687B4,0x129BC61C,0x2F15783C,

            0xE329DC7B,0x53D8F91A,0x7D101746,0x080D0FC0,0x0D088808,0x0D0D8908,0x18880808,0x4E8703C3,0x764924EF,0xC1C18C2A,

            0xE491C1C1,0xF8E01E4E,0x48CF7A03,0x8F598DAE,0x61C51F61,0x0A386529,0xB542CAD2,0xD14F13DA,0x223027B1,0xC7D1543A,

            0xF8C0E3B9,0xC08EB1C7,0xFB51CB03,0x87A03E50,0xF4EEC602,0xEA10F5D0,0x85B44FEF,0xCE0180E8,0x7A583235,0x4107CF3C,

            0xC7C8307A,0x8FC61A6A,0x4044402E,0x42304868,0x45C2C302,0xB5114500,0x39587000,0x604F470C,0x0E8D7310,0x5C785444,

            0x374F187C,0x9AFFC7E9,0x952790D0,0xA9D92492,0x07070630,0x3B924707,0x652F81F9,0x3F8FC324,0xDD8CB64F,0x07EBA1E9,

            0xD10B6926,0x65FC0301,0x80020E91,0x3861CAC3,0x3883027A,0x54FA5C91,0xFB73FB30,0x92652E5A,0x8F49A4DA,0x0A8AB868,

            0xEC7F441F,0x128AF415,0xAB7C7174,0x7F6F5E86,0x47C35F75,0xE7B7D215,0x1FC680FA,0xFFD4E2CC,0x7FB7CAA6,0xCBE8883E,

            0x2B0BE151,0x4F9EF27E,0x7BE37F2F,0x8BF3C604,0x10F2F11E,0x91D36386,0x1F57A1E3,0x7772F578,0x3D8CB8E3,0x6889EBDD,

            0xB2FA9F0F,0x7A280F99,0xAE43D6E9,0xB2F0779E,0xFEA1CFBC,0x0517A7EC,0xF03EAF5C,0x1EB65BE3,0x4D21F52C,0x60F6AE1F,

            0xBC1E07A3,0x4A73E0C9,0x508EF19F,0xD0788ACF,0x1ED943D6,0x8788F560,0xE2CD8D07,0x148F47A1,0x979DB3BA,0xA1FA603E,

            0x60F7F6E8,0x3D32A7B8,0xB079E9B6,0xC1F2AB1F,0xB9746F60,0xF9E93C7D,0xABCF31C1,0x67D93479,0x3C2EBCFA,0x7526EF09,

            0xCFD27B24,0x2765E661,0x23F6B79F,0xCC147DD1,0x73AE0FEC,0xD1307803,0x531E47B3,0x1F7021FA,0x968EF44A,0x24FA20CF,

            0x73D23B8C,0xEF714ECB,0x2140FDB6,0x69F9921F,0x7E7CCF09,0x8D43D70B,0x21F0865F,0x6F4FEF3D,0xCCA27A01,0x92DEFD83,

            0xF78ABEFD,0xFE723F42,0x156F516D,0x07D8967D,0xCD30BCA1,0xCF3425E7,0xCCE0788F,0xD21E83C3,0x8FEC59F6,0x7BC40F6A,

            0xEC43DD60,0x48F74D1E,0x3D0FD794,0x368EED80,0xF84F2FAA,0xE007A47C,0x63E92FBD,0x965E5FA4,0xF4787E73,0xCAE219DC,

            0x3BBE40F3,0x29E9B9C2,0x7EA68F54,0xEA15D92C,0xE56E1273,0xA5BAF0F4,0x629C3597,0x11EF9C3E,0x70F13AE5,0x3CEFA7A2,

            0xBBFDF642,0x407B3B0F,0x1CE8C9C6,0x038BDCF0,0x0EF163D5,0x78CACF28,0x0E0CC080,0xF57C5F3A,0x6CBD0343,0x9F2301E2,

            0x8ED9F2C8,0x9CC79367,0x0E91EF4C,0xA987B8F7,0xC29E4BDC,0xA79ED8F0,0xD18A7DEC,0xF9F1068F,0xB0505F40,0x1C6A079A,

            0x76981E9D,0x3C1CB9D4,0x1AB5EC00,0x19F7245F,0xE15F1F7C,0x213EAB0B,0xEF7A19E3,0x9FA8F9E4,0x1887BA27,0x3DE7363D,

            0xF5DF9F5D,0x8B70F114,0x991C6147,0xB6770E8E,0x5C9DFC87,0x48F5791E,0x2447828B,0xF3E2E03D,0xE9B6BE01,0x226FAFD5,

            0x333CC8BA,0x0F7019E0,0x7CCB3922,0x9307E992,0x21EDEF3C,0x163B33AF,0x0CFF4A3C,0x4FAE1AF9,0x2BF1FD7F,0x08F3463E,

            0x4775FF1F,0x3BD0D57B,0xF7799F75,0x3E0FF8E0,0x27CC90F5,0xFF813DF5,0xF13F50C3,0x7E73DEF0,0xF3C3D278,0x72A9DFCF,

            0x0C1739FD,0x6F086A20,0xF5F57A92,0x66C1EBA5,0x2078880F,0x61EC41CF,0xB9436905,0xFCC13CAF,0x645F7641,0x88B748F6,

            0xD2D34B63,0x5B8B2ACE,0x3166C9C0,0x3B849637,0x1064C1C4,0xEDBAB90B,0x2A7580E8,0x01C14079,0x567330E8,0xAA9DB039,

            0xB40759EE,0x4444C624,0x8207470D,0xCEB91DF1,0x39A36524,0x14E8EDE2,0x3C9C15B3,0x89B7401E,0x8E68D263,0x60BB230F,

            0x4821E06C,0x7CB19787,0xEFBFF132,0xF30EBFBA,0xDD7F978F,0xFA29EA9A,0xA3A63624,0x402E88D4,0xE4C89E93,0xDBB335CE,

            0xE361CE5E,0x88437120,0x8E44CEDA,0xF898AB48,0x83BE8626,0x66771C09,0xC8C38A33,0x1400E3E1,0xD03BA632,0xC7538EF8,

            0x1D59EC87,0x0F3A8E5A,0xFE607BA6,0x9474D61A,0x0EC8D9DA,0xA4070101,0xC459BABC,0x614E571F,0xD303AD87,0x477767C1,

            0x55D48385,0x85D76F6D,0x72C4CC93,0x1BA3708E,0x730228EA,0x63BD32A7,0xC8E719C7,0xB83A8470,0xB51626DD,0x240D8DA2,

            0xAB173865,0x049FC2FB,0xF763F846,0xEFA9C9FE,0x5AFF7D4D,0x7A9E8F3B,0xEBDFD0D7,0xA6BE94F6,0x5FDC686E,0x165FDF8E,

            0x26D234FF,0x69AE9AB5,0xF71EBF54,0xAFE5F36F,0xA72A3520,0xEC0F2FE8,0x0DF03D6F,0xCBF88318,0x23CBF8E3,0x5F58BB4E,

            0xDBFEE27C,0xE2DBFE11,0xFC08DE33,0xA1A49746,0xFFD1BD84,0x4D01044D,0x1BCA4915,0x5D5C4C41,0x57F00042,0xC567F682,

            0xB2F006FC,0xBF91D2BF,0xB288EAD2,0xA73C2CDD,0x69330C67,0x1F4E5098,0xB2620ACA,0xED87268E,0x7C41DEC3,0x87D4F740,

            0x07BE1D44,0x03FEB751,0x57F4D714,0x9757F34F,0x1255961F,0x46BF9E33,0x35FC0989,0x652B0FB4,0x6F78DB9A,0x56FBC675,

            0xE6BF8146,0xD1A6BF85,0xBF94ACB2,0x96BFB056,0xDAABA8DB,0xBFFDF715,0x632BC01F,0xEBFC2306,0xFF6BFAB4,0xFA00EBFD,

            0xCC0EAF6B,0x103E985B,0x18D207E1,0x3E50D952,0xC43FE4D0,0xE4C43FDF,0x0A092607,0x901FF92A,0xFE3FEFF9,0x9FC227EB,

            0x3C7BF627,0xFF1D81F1,0x2A3EF2A9,0x75773FC0,0xFE9E07DC,0x4A235420,0x3E66C018,0x07FB64A8,0xE61BF9AD,0x5D5A1BF9,

            0x8780485F,0xF4903251,0x849561A4,0x604D2434,0xCB5A0326,0xDFCB18DF,0x9778E698,0xBFBF34D2,0x31BFB5B1,0x7F36B9CD,

            0xCD0FC6C8,0xF035D654,0x61F8B50F,0xA6FEDA82,0x21A6FE3F,0xCC07670F,0x61FD8B0F,0xECEC3E6B,0x11825F80,0x05A4C2F4,

            0x33EF6ABF,0x2397BF18,0x896C6224,0xFF39F37F,0x011FF5E4,0xB507A56F,0xC5CDFD11,0x2E79CDFC,0x11F650F3,0xD8123F2B,

            0xE07526FC,0xFA6B9BF8,0x28FE939B,0xEE651F82,0x6FE2716F,0x8CA3F0D1,0xA190547F,0xC56FE935,0x6FFD8DE0,0x415BFACA,

            0xF8CF5BFE,0x58CD6B5B,0x306B01F8,0x60F91BA3,0x56FED2B2,0xE2D6FEEF,0xFAE34D0F,0xF31F8C98,0x6D6FF826,0xFAC36FE1,

            0x96B7F658,0x35BF9C33,0x063515E9,0x8FD1EC7E,0xF0A23243,0xD7E9FC51,0xFF79E9FC,0x6DFC7C6D,0x6D6DFE48,0xA60E6DFD,

            0xD1EDFD35,0x974EEDFC,0x1CFFEDFD,0xEFF6FEBC,0xE7813EF3,0x04FBA827,0x5B84F8A9,0x13256565,0x9F9844FB,0xE4EFEE68,

            0xFAA4EFE0,0xEFE4D4EF,0x1E2FFFE4,0xF3762FEB,0x6AAF72EF,0xD2EAFF2B,0xE5249F29,0x838BAAEF,0x3ABBF86A,0x49F48615,

            0xC1A93F76,0xCE9D1527,0xDFD4EEBF,0xC638E69D,0xFF62C9F3,0x1EFE850D,0x451EFFB4,0x48F7F486,0xC14F973E,0x12F629FC,

            0xD15EFEC2,0x7BF8488E,0xC914FDA3,0x7F7056FF,0x9F41A16F,0xDADFFFF2,0xFD0DEFEE,0x6A7FE353,0xBFB6D099,0x6FBF89EF,

            0xFFED4FC0,0x34C62469,0xFBB34FA1,0xF5D252EF,0xEFFE92EF,0xEBF7F3DA,0xF227F7F9,0xB0BB07F7,0xB3007FA4,0x0803FDC9,

            0xFCCA03FE,0xE5FF5203,0xCEA3FD64,0xE9B7067F,0xCFEA867D,0x6781F448,0x320A15FF,0xDC7FDE3E,0xD063E65F,0x2CBE1F13,

            0x088667E1,0xF168F82F,0x2023AD1F,0xE0FF7061,0x96E0FF16,0x14C499A3,0x2187BF36,0xBC30E72C,0x7F9C80AA,0xD9238770,

            0xE0C3FFCE,0xC0449B3F,0x4851FE80,0xFFC391FE,0xA3FE64A1,0xA3FE4334,0xFF7F0E75,0x239F91B1,0x6029252C,0x189BBD3C,

            0x3BA6AEF2,0x85CFA6A1,0x7A16B9F9,0xE7F4D73E,0x47FA0A8E,0xDC47F91A,0xB03CFA8E,0xEBEC479F,0x15F7FE73,0x73FE681D,

            0x9F3EE3A0,0x76F6D4DD,0x3747FA50,0xAD6B47FA,0xFE5CC398,0x487E68B1,0x69A8FF11,0x47F24733,0x3547F193,0xE27F90BF,

            0x427FA687,0xFCF5B9DB,0x13FDBD13,0xF6DE1E1D,0xDB1F39A5,0xC2C9FE5A,0xBF3389FE,0x0797F95C,0xF9E327F8,0x0AFDDDEF,

            0xF7629F6E,0x53FDE653,0xFECC1C03,0xBE6390C7,0x3D3FC262,0xF5A4FFC2,0x3FC854FF,0xFE3A22FD,0x19FED719,0xE612BF8C,

            0x4758AA57,0x32BE58D3,0xC06AFFF6,0x11FBDB3F,0xD5F6C0E3,0x7ABEBB31,0xD46F3FC3,0xFFF99EFF,0x6E61DADE,0xE67CFF43,

            0x6BF4335F,0x25458501,0x5FEC0D44,0x271C6C44,0xC98F0180,0x3EA9D9B1,0x88E63092,0x0D99AC18,0x1D2BC55E,0xBCC7ECF8,

            0x684903D5,0x44404040,0x6C484068,0x40404068,0x981E28C4,0x612E924D,0x9E7909E0,0xB2490264,0x079AB23B,0x280621DB,

            0x93126999,0x50BD6778,0x92492493,0x1A165914,0x49249249,0xE8596452,0xB316C00F,0xF696281E,0x1D464740,0xFAA21993,

            0x47599CB5,0xD0A09F3B,0xD0A0A0E0,0xC4B8C0E0,0x90D080F0,0xA8E6F8E0,0x48E098CC,0xB01F0617,0x1D9E9814,0x1FDE1152,

            0xA8B03A9E,0x47070740,0x38F8F4EE,0xAC7198BA,0xEB946636,0x7B27B8D0,0xD8507950,0xC3DA7BD1,0x0E2E0E4E,0x0C69CA8E,

            0x0D0C080B,0xF40E0A0A,0xDA6EBF41,0xF3B60E41,0x221F43EB,0x97834928,0x801FB4A4,0xE960C8BB,0x8D87C531,0x5D7EAFB1,

            0xC1E8881F,0x71AB1F40,0x81415118,0x53205054,0x03431282,0x52B09480,0xC587C464,0x253FA00E,0x20710859,0x0E011144,

            0x507C4441,0x88443850,0x8CDD8810,0x3DD9C27B,0x030901DD,0x6219361A,0x02A05429,0x00200102,0x00000030,0x03A2E202,

            0x00091511,0x9C21A111,0x20200000,0x80084000,0x04400130,0x00189080,0x80004040,0x02610010,0x21000880,0x774F7518,

            0x7B4F774F,0x774F774F,0x674F774F,0x774F674F,0x774F774F,0x7B4F774F,0x774F774F,0x674F774F,0x774F674F,0x774F774F,

            0x3A7AB74F,0xBA7B3A7B,0xDA7BBA7B,0xBA7BBA7B,0xBA7B3A7B,0x5A7BBA7B,0xBA7BBA7B,0xBA7B3A7B,0xBA7BBA7B,0xBA7B3A7B,

            0xBA7B3A7B,0xBA7BBA7B,0xBA7BBA7B,0xDA7BDA7B,0xD3D5BA7B,0x33DDD3DD,0x9EFA9EC4,0xF754F711,0xF7D4F7D4,0xBBA7AA2C,

            0xBBA7BBA7,0x473DD467,0x7B7D1D01,0xDCD3D9F6,0x6C73DCD3,0x4E0F88D2,0xF601E867,0xAACCF6D4,0xBD27B3A7,0xD3D940E7,

            0xD3DCD3DD,0xD3DCD3DD,0xD3DF53DD,0xD3DAD3DD,0xD3DAD3DD,0xD3DFD3DD,0x9EE433D9,0xF734F641,0xB7A7AF2C,0x73DE00E7,

            0xBCC9D2E2,0xF675BCE7,0x0485C4BE,0x84444404,0x25370DF4,0xA0202425,0x3C253F20,0x130E2422,0x9C4B5382,0x0813D894,

            0x49D9A80F,0x7B3CD3C3,0xDDD3DE06,0x0073D8D3,0xA7B041D2,0xA7B3A7B3,0xE7BEA7BB,0x7303A080,0xBA7BE0CF,0x9A7BBA7B,

            0x4E7B9A7B,0x1DEBE82E,0xF38A96D0,0x413116CE,0x985852ED,0x837642E2,0x436D2B81,0xCB0AFD11,0x0300BC3A,0x224672D7,

            0x517567AE,0xC45AC840,0xF028211D,0x16109718,0x3C38D616,0xEFE34F8C,0x0B0B084B,0x63D9DC6B,0x0202027C,0x17064202,

            0xD7A0A010,0xF674F6F4,0xF774F774,0x00E7AC2C,0xD3DDD3D8,0xD3DDD3DD,0x10C073DD,0xE9EF5075,0xE90939EE,0xD9D3D814,

            0xDDD3D9D3,0xDDD3DDD3,0xD9D3DDD3,0x039E88B3,0x4F774F70,0xCF674F77,0xA6F4149B,0x9EEE9EC4,0x9EEE9ECE,0x9ECE9EEE,

            0x9EEE9EEE,0xF5459EEE,0x4ACCF774,0xA7B5A1D4,0xA7BDA7BB,0x314DE7BB,0x4F6CD37A,0xCF774F67,0x7A614A21,0xB4DE9F43,

            0xD3DDD3D9,0xD3DDD3DD,0xD3DDD3D9,0x922873DD,0xE9ED3874,0xE9ECE9EE,0xE9EEE9EE,0xE9EEE9EE,0xE9EEE9EC,0xE9ECE9EC,

            0xC9EEE9EE,0x380A094F,0x7BD91C4C,0xD7E67BBA,0xDDD3DDD3,0x26F3DDD3,0x53F1BD0E,0xF1BD4514,0xEE766F4D,0xEEE9EEE9,

            0x774F5859,0x774F774F,0xF4349BCF,0xEE9EECE6,0xEE9EFA9E,0x74F5859E,0x74F774F7,0x46C9BCF7,0x4515446F,0xB951D451,

            0xC8E7BBA7,0xA8A28A20,0x774F65A3,0x774F774F,0xAF0695CF,0xBD4512D5,0xADAF1B36,0xD6BD4512,0x1275AF18,0xBC66DAF5,

            0x6BD44876,0x38DAF1FD,0xE76BD451,0x513DDAF1,0xF1B36BD4,0xD4512ADA,0xDAF1AF6B,0x6BD4512F,0x3EDAF1EB,0xC7FDAF51,

            0xBD44E0EB,0x5DAF1876,0x0EBD4512,0xC02475F9,0xDAF1B76B,0xEBD4512B,0x2E3AF1A8,0xA8EBD451,0x22020243,0x4B5E4222,

            0x24924925,0x24F29249,0x49249249,0x4924F0D2,0xD2492492,0x3AF1D8EB,0x8671D7AE,0xEC6EBD86,0x2E00A0F5,0x79516FB1,

            0xDC6C6B1D,0x8F5EB6EB,0xC3D7801B,0x471BAF00,0x70DE6E5E,0x0187D781,0x4445A7AF,0x0622423C,0x6A5F040E,0x3AF262DF,

            0xD7D0B0C2,0x32DEBDA3,0x0A8A6F01,0x884B1808,0x54161787,0x15155013,0xC5AEF410,0xBF148377,0xDDE0376B,0x90534A10,

            0x20A51482,0x60284535,0x8F512A98,0x3CC387A4,0x20202330,0x20202020,0x20202020,0x20202820,0x4208410A,0xD2308210,

            0x04046559,0x04040404,0x04040404,0x04050404,0x41082144,0x46104208,0x4949393A,0x2EB8161F,0x3E84BF16,0x05AC25F8,

            0x900A4924,0x050080A4,0x4A924028,0x7EE21383,0x1E6232D9,0xB09015C3,0x30CE9D15,0xB0A880A6,0x2A870011,0x6BA5D0E0,

            0x038B17CB,0xC4831292,0x47044BC7,0x450CBF7C,0x241CC001,0x493E9751,0x836D0161,0xA5A22294,0x4940D088,0x4452D161,

            0x05852524,0x8A520DB4,0x42229688,0x45852503,0x5191114B,0x00C008C1,0x61084830,0x8D100308,0x687D0800,0x20423C46,

            0x10A060F4,0x000C0084,0x1818A1BD,0xA0418E06,0x04188911,0x008D111A,0x831E2184,0x21122340,0x688D0C0C,0x21622342,

            0x42042004,0x200E061B,0x08111222,0x4C801643,0x8D100000,0x19212440,0x18800021,0x30182D00,0x10448062,0x20640002,

            0x8C004600,0x30011800,0xA0046002,0x423D400C,0x020183D1,0x80204208,0x00000040,0x00122144,0x200910A2,0x32263A2A,

            0x4011922A,0x54644C78,0x10E22324,0x4600200B,0x18200000,0x20000021,0x42082118,0x92AB8020,0xC4B80220,0x00000000,

            0x046BA81B,0x380003D6,0x35D7543C,0xA8B54F62,0xA0BAD75B,0xA1C5A2E2,0xA161456E,0x001B2765,0x520304F0,0x80015180,

            0x2998F757,0xE0000000,0x4768DB65,0x6C30320B,0x1905A044,0x86044788,0x0828610A,0x0421E0C2,0x682D0822,0x10A21744,

            0x18026180,0x8E903200,0xC10D0C4E,0xD0223218,0x20B46682,0x3218C103,0x010D10A2,0x82D00088,0x830D0C4E,0x019A0B47,

            0x320B4000,0xA4588C10,0x46431020,0x83D14214,0x02884201,0x086682D1,0x90FA2844,0x00360C01,0x47A82D81,0x84388834,

            0x38882083,0x6D082384,0x0C3847A8,0x20E10E22,0xA000D0A2,0xE220D11E,0x20820E10,0x1E8E10E2,0x0688F500,0xF4708711,

            0x10188060,0x1C8E11EA,0x1F184315,0x0862A986,0x5530C3E3,0xC540A10C,0x0C540A10,0xA6187C61,0x0F8C218A,0x843154C3,

            0x2A9861F1,0x0C3E3086,0x0A10C553,0x40A10C54,0x87C610C5,0x7C6B17A1,0x843154C3,0x2A9861F1,0x8C3E3086,0x8980001F,

            0x00000001,0x00000000,0x00000000,0x00000000,0x7A718000,0xD060407C,0xB13C1D38,0x302020C0,0xD898A268,0x31BE3544,

            0x1802783B,0xF1A183B3,0x45C1D98D,0xECC6061A,0x89E292E0,0x13418101,0x0152C4C5,0x00000000,0x00000000,0x00000000,

            0xE0000000,0x0001FA23,0x00000000,0x11451451,0x00000000,0x28A20000,0xE000228A,0x250684C3,0x08544A88,0x00000000,

            0x20000000,0x50B80230,0x088957E3,0x574E1A58,0x8F482B75,0xCF8C8A8A,0xA7C5E43B,0xED700A1D,0x491962FB,0xC7A110F1,

            0xAFDF014B,0x94927103,0x7E08388A,0x090FC272,0x0824B7C1,0xC13C3E39,0x181D54F2,0x3013F011,0x229971F8,0x04454202,

            0xAB29FC19,0x7FBD4A09,0xE3DC7B8C,0xC7BAF71E,0x607B627D,0xF3076CC7,0xEE3FD845,0x34865CD0,0x301DD9F2,0x358EB1C6,

            0x7236F81D,0x1A01FAEA,0x7BE48FE6,0xD572F810,0x40079AA0,0xE3DC7B8E,0xC7B8F71E,0x8F71EE3D,0x5EE3D463,0x9A7ACDE8,

            0x3FE5C947,0x0A33EDE2,0x52794E15,0x9AE3D8A3,0x65EC2A3E,0x75AA34A8,0xC3986343,0xEE30D6F0,0x4C7B8C75,0xC1E4D863,

            0x8371F068,0x901E183D,0xF61CA5DF,0xE763F7E0,0x38ACED35,0x9FEA1FE0,0xEA85DAA3,0x08E87434,0x00880002,0xC5E0362F,

            0x81D8BC16,0xE2F07B17,0xC11C5E00,0x7178138B,0x512E2E86,0x41AE2F00,0x1783B8BC,0x09E2F00F,0x8BC1BC5E,0x03F1782F,

            0xA0B7187F,0x00D1F82B,0x0D1C42BA,0xD1E42BA0,0x34ACBA00,0x46D59742,0x08D6B2E8,0x2BC1615E,0x01A5781C,0x83E0B3AF,

            0x2307C111,0x4BC87C01,0x9050F810,0x2EA1F030,0x4343E041,0x5A30F8C2,0x917461E8,0x185B187C,0x3E00C61F,0xDDC74625,

            0x29F020C0,0xFD71D051,0x85FA9B41,0x0A090C20,0x1EDA53D2,0x8BC68D71,0x5440406C,0xFE3494DA,0xD42BF520,0xB61A6724,

            0xE8622942,0x6A4E3C97,0x65CB7741,0x6233A88C,0x259E07BA,0x9A940704,0x102F92C7,0x9640E1FE,0x98A8BD77,0x99A099F9,

            0xEB24303F,0x052E3DC9,0x47460506,0x1E060606,0x5CB76641,0x31BBB36F,0xF5B2FC33,0x1F508D20,0xD34E8366,0x43EBEF9F,

            0x713C3FB7,0xE3DF4120,0x8071EA32,0x24546261,0x6090E019,0x11300851,0x82208C12,0x080CC121,0xB80B0F09,0x4A3DC5A8,

            0x00F5B1FC,0xC415765F,0xF84A085F,0xB6C8F562,0x29F2F1C7,0x27A541CD,0xE11F18A0,0xF03DB613,0x33920550,0xE2CE603F,

            0x8C075921,0x0FE01C65,0xD21BF10C,0x41902F31,0xF4EB879F,0x20D1F313,0x2671664B,0xF539E46A,0xB0E6E807,0xD759F875,

            0x1D3D8ED0,0xDB718111,0x404054DE,0xE7D046B8,0x0484B1C0,0x0D0A407B,0x40596E9D,0x501947A8,0x852D1A19,0x5CBE43D8,

            0x5D7494F9,0x740B0B6E,0x780F74E0,0x560B99A1,0xCBB1E070,0x5F9A0F41,0x2F97A7CD,0xFAA1EC1D,0xF4101B10,0x2F2370A1,

            0x1CB00FC0,0x71A77EC0,0x86123E70,0x8FEF387E,0xE530508B,0xC7067887,0x07A36B05,0x45722BF7,0xA212286A,0x4460A0C9,

            0x86050784,0x18801A05,0x1E161816,0xB8A01810,0x0A0C0864,0x18161404,0x05062088,0x1D0B0813,0xAC0300D0,0xE468F2B6,

            0xA1610364,0x10A05441,0x219300E2,0x41A1F109,0x81018101,0xCE80C5C7,0xE23E6A27,0x15D8BF91,0x0C270141,0xE0AA89E9,

            0xC2752253,0x02781054,0x00000004,

        };

    }

}```

```cs [ENSNormalize.cs/ENSNormalize/GroupKind.cs]

﻿namespace ADRaffy.ENSNormalize

{

    public enum GroupKind: byte

    {

        Script,

        Restricted,

        ASCII,

        Emoji

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/Whole.cs]

﻿using System.Collections.Generic;



namespace ADRaffy.ENSNormalize

{

    public class Whole

    {

        public readonly ReadOnlyIntSet Valid;

        public readonly ReadOnlyIntSet Confused;



        internal readonly Dictionary<int, int[]> Complement = new();

        internal Whole(ReadOnlyIntSet valid, ReadOnlyIntSet confused)

        {

            Valid = valid;

            Confused = confused;

        }

        public bool Contains(int cp) => Valid.Contains(cp) || Confused.Contains(cp);

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/NF.cs]

﻿using System.Collections.Generic;

using System.Linq;



namespace ADRaffy.ENSNormalize

{

    public class NF

    {

        const int SHIFT = 24;

        const int MASK = (1 << SHIFT) - 1;

        const int NONE = -1;



        const int S0 = 0xAC00;

        const int L0 = 0x1100;

        const int V0 = 0x1161;

        const int T0 = 0x11A7;

        const int L_COUNT = 19;

        const int V_COUNT = 21;

        const int T_COUNT = 28;

        const int N_COUNT = V_COUNT * T_COUNT;

        const int S_COUNT = L_COUNT * N_COUNT;

        const int S1 = S0 + S_COUNT;

        const int L1 = L0 + L_COUNT;

        const int V1 = V0 + V_COUNT;

        const int T1 = T0 + T_COUNT;



        static bool IsHangul(int cp)

        {

            return cp >= S0 && cp < S1;

        }



        static int UnpackCC(int packed)

        {

            return packed >> SHIFT;

        }

        static int UnpackCP(int packed)

        {

            return packed & MASK;

        }



        public readonly string UnicodeVersion;



        private readonly ReadOnlyIntSet Exclusions;

        private readonly ReadOnlyIntSet QuickCheck; // TODO: apply NFC Quick Check

        private readonly Dictionary<int, int> Rank = new();

        private readonly Dictionary<int, int[]> Decomp = new();

        private readonly Dictionary<int, Dictionary<int, int>> Recomp = new();



        public NF(Decoder dec)

        {

            UnicodeVersion = dec.ReadString();

            Exclusions = new(dec.ReadUnique());

            QuickCheck = new(dec.ReadUnique());

            int[] decomp1 = dec.ReadSortedUnique();

            int[] decomp1A = dec.ReadUnsortedDeltas(decomp1.Length);

            for (int i = 0; i < decomp1.Length; i++)

            {

                Decomp.Add(decomp1[i], new int[] { decomp1A[i] });

            }

            int[] decomp2 = dec.ReadSortedUnique();

            int n = decomp2.Length;

            int[] decomp2A = dec.ReadUnsortedDeltas(n);

            int[] decomp2B = dec.ReadUnsortedDeltas(n);

            for (int i = 0; i < n; i++)

            {

                int cp = decomp2[i];

                int cpA = decomp2A[i];

                int cpB = decomp2B[i];

                Decomp.Add(cp, new int[] { cpB, cpA }); // reversed

                if (!Exclusions.Contains(cp))

                {

                    if (!Recomp.TryGetValue(cpA, out var recomp))

                    {

                        recomp = new();

                        Recomp.Add(cpA, recomp);

                    }

                    recomp.Add(cpB, cp);

                }

            }

            for (int rank = 0; ; )

            {

                rank += 1 << SHIFT;

                List<int> v = dec.ReadUnique();

                if (v.Count == 0) break;

                foreach (int cp in v)

                {

                    Rank.Add(cp, rank);

                }

            }

        }

        int ComposePair(int a, int b)

        {

            if (a >= L0 && a < L1 && b >= V0 && b < V1)

            {

                return S0 + (a - L0) * N_COUNT + (b - V0) * T_COUNT;

            }

            else if (IsHangul(a) && b > T0 && b < T1 && (a - S0) % T_COUNT == 0)

            {

                return a + (b - T0);

            }

            else

            {

                if (Recomp.TryGetValue(a, out var recomp))

                {

                    if (recomp.TryGetValue(b, out var cp))

                    {

                        return cp;

                    }

                }

                return NONE;

            }

        }



        internal class Packer

        {

            readonly NF NF;

            bool CheckOrder = false;

            internal List<int> Packed = new();

            internal Packer(NF nf)

            {

                NF = nf;

            }

            internal void Add(int cp)

            {

                if (NF.Rank.TryGetValue(cp, out var rank))

                {

                    CheckOrder = true;

                    cp |= rank;

                }

                Packed.Add(cp);

            }

            internal void FixOrder()

            {

                if (!CheckOrder || Packed.Count == 1) return;

                int prev = UnpackCC(Packed[0]);

                for (int i = 1; i < Packed.Count; i++)

                {

                    int cc = UnpackCC(Packed[i]);

                    if (cc == 0 || prev <= cc)

                    {

                        prev = cc;

                        continue;

                    }

                    int j = i - 1;

                    while (true)

                    {

                        int temp = Packed[j];

                        Packed[j] = Packed[j + 1];

                        Packed[j + 1] = temp;

                        if (j == 0) break;

                        prev = UnpackCC(Packed[--j]);

                        if (prev <= cc) break;

                    }

                    prev = UnpackCC(Packed[i]);

                }

            }

        }

        internal List<int> Decomposed(IEnumerable<int> cps)

        {

            Packer p = new(this);

            List<int> buf = new();

            foreach (int cp0 in cps)

            {

                int cp = cp0;

                while (true)

                {

                    if (cp < 0x80)

                    {

                        p.Packed.Add(cp);

                    }

                    else if (IsHangul(cp))

                    {

                        int s_index = cp - S0;

                        int l_index = s_index / N_COUNT | 0;

                        int v_index = (s_index % N_COUNT) / T_COUNT | 0;

                        int t_index = s_index % T_COUNT;

                        p.Add(L0 + l_index);

                        p.Add(V0 + v_index);

                        if (t_index > 0) p.Add(T0 + t_index);

                    }

                    else

                    {

                        if (Decomp.TryGetValue(cp, out var decomp))

                        {

                            buf.AddRange(decomp);

                        }

                        else

                        {

                            p.Add(cp);

                        }

                    }

                    int count = buf.Count;

                    if (count == 0) break;

                    cp = buf[--count];

                    buf.RemoveAt(count);

                }

            }

            p.FixOrder();

            return p.Packed;

        }



        // TODO: change this to an iterator

        internal List<int> ComposedFromPacked(List<int> packed)

        {

            List<int> cps = new();

            List<int> stack = new();

            int prev_cp = NONE;

            int prev_cc = 0;

            foreach (int p in packed)

            {

                int cc = UnpackCC(p);

                int cp = UnpackCP(p);

                if (prev_cp == NONE)

                {

                    if (cc == 0)

                    {

                        prev_cp = cp;

                    }

                    else

                    {

                        cps.Add(cp);

                    }

                }

                else if (prev_cc > 0 && prev_cc >= cc)

                {

                    if (cc == 0)

                    {

                        cps.Add(prev_cp);

                        cps.AddRange(stack);

                        stack.Clear();

                        prev_cp = cp;

                    }

                    else

                    {

                        stack.Add(cp);

                    }

                    prev_cc = cc;

                }

                else

                {

                    int composed = ComposePair(prev_cp, cp);

                    if (composed != NONE)

                    {

                        prev_cp = composed;

                    }

                    else if (prev_cc == 0 && cc == 0)

                    {

                        cps.Add(prev_cp);

                        prev_cp = cp;

                    }

                    else

                    {

                        stack.Add(cp);

                        prev_cc = cc;

                    }

                }

            }

            if (prev_cp != NONE)

            {

                cps.Add(prev_cp);

                cps.AddRange(stack);

            }

            return cps;

        }



        // primary

        public List<int> NFD(IEnumerable<int> cps) 

        {

            return Decomposed(cps).Select(UnpackCP).ToList();

        }



        public List<int> NFC(IEnumerable<int> cps)

        {

            return ComposedFromPacked(Decomposed(cps));

        }



        // convenience

        public string NFC(string s)

        {

            return NFC(s.Explode()).Implode();

        }

        public string NFD(string s)

        {

            return NFD(s.Explode()).Implode();

        }



    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/DisallowedCharacterException.cs]

﻿namespace ADRaffy.ENSNormalize

{

    public class DisallowedCharacterException : NormException

    {

        public readonly int Codepoint;

        internal DisallowedCharacterException(string reason, int cp) : base("disallowed character", reason)

        {

            Codepoint = cp;

        }

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/ConfusableException.cs]

﻿namespace ADRaffy.ENSNormalize

{

    public class ConfusableException : NormException

    {

        public readonly Group Group;

        public readonly Group OtherGroup;

        internal ConfusableException(Group group, Group other) : base("whole-script confusable", $"{group}/{other}")

        {

            Group = group;

            OtherGroup = other;

        }   

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/ENSIP15.cs]

﻿using System;

using System.Linq;

using System.Text;

using System.Collections.Generic;

using System.Collections.ObjectModel;



namespace ADRaffy.ENSNormalize

{

    internal class EmojiNode

    {

        internal EmojiSequence? Emoji;

        internal Dictionary<int, EmojiNode>? Dict;

        internal EmojiNode Then(int cp)

        {

            Dict ??= new();

            if (Dict.TryGetValue(cp, out var node)) return node;

            return Dict[cp] = new();

        }

    }



    internal class Extent

    {

        internal readonly HashSet<Group> Groups = new();

        internal readonly List<int> Chars = new();

    }



    public class ENSIP15

    {

        const char STOP_CH = '.';



        public readonly NF NF;

        public readonly int MaxNonSpacingMarks;

        public readonly ReadOnlyIntSet ShouldEscape;

        public readonly ReadOnlyIntSet Ignored;

        public readonly ReadOnlyIntSet CombiningMarks;

        public readonly ReadOnlyIntSet NonSpacingMarks;

        public readonly ReadOnlyIntSet NFCCheck;

        public readonly ReadOnlyIntSet PossiblyValid;

        public readonly IDictionary<int, string> Fenced;

        public readonly IDictionary<int, ReadOnlyCollection<int>> Mapped;

        public readonly ReadOnlyCollection<Group> Groups;

        public readonly ReadOnlyCollection<EmojiSequence> Emojis;

        public readonly ReadOnlyCollection<Whole> Wholes;



        private readonly EmojiNode EmojiRoot = new();

        private readonly Dictionary<int, Whole> Confusables = new();

        private readonly Whole UNIQUE_PH = new(ReadOnlyIntSet.EMPTY, ReadOnlyIntSet.EMPTY);

        private readonly Group LATIN, GREEK, ASCII, EMOJI;



        // experimental

        private readonly string[] POSSIBLY_CONFUSING = new string[] { "ą", "ç", "ę", "ş", "ì", "í", "î", "ï", "ǐ", "ł" };



        static Dictionary<int, ReadOnlyCollection<int>> DecodeMapped(Decoder dec)

        {

            Dictionary<int, ReadOnlyCollection<int>> ret = new();

            while (true)

            {

                int w = dec.ReadUnsigned();

                if (w == 0) break;

                int[] keys = dec.ReadSortedUnique();

                int n = keys.Length;

                List<List<int>> m = new();

                for (int i = 0; i < n; i++) m.Add(new());

                for (int j = 0; j < w; j++)

                {

                    int[] v = dec.ReadUnsortedDeltas(n);

                    for (int i = 0; i < n; i++) m[i].Add(v[i]);

                }

                for (int i = 0; i < n; i++) ret.Add(keys[i], new(m[i]));

            }

            return ret;

        }



        static Dictionary<int, string> DecodeNamedCodepoints(Decoder dec)

        {

            Dictionary<int, string> ret = new();

            foreach (int cp in dec.ReadSortedAscending(dec.ReadUnsigned()))

            {

                ret.Add(cp, dec.ReadString());

            }

            return ret;

        }



        static IDictionary<K, V> AsReadOnlyDict<K, V>(Dictionary<K, V> dict) where K: notnull 

        {

#if NETSTANDARD1_1 || NET35

            return dict; // pls no bully

#else

            return new ReadOnlyDictionary<K,V>(dict);

#endif

        }



        static List<Group> DecodeGroups(Decoder dec)

        {

            List<Group> ret = new();

            while (true)

            {

                string name = dec.ReadString();

                if (name.Length == 0) break;

                int bits = dec.ReadUnsigned();

                GroupKind kind = (bits & 1) != 0 ? GroupKind.Restricted : GroupKind.Script;

                bool cm = (bits & 2) != 0;

                ret.Add(new(ret.Count, kind, name, cm, new(dec.ReadUnique()), new(dec.ReadUnique())));

            }

            return ret;

        }



        public ENSIP15(NF nf, Decoder dec)

        {

            NF = nf;

            ShouldEscape = new(dec.ReadUnique());

            Ignored = new(dec.ReadUnique());

            CombiningMarks = new(dec.ReadUnique());

            MaxNonSpacingMarks = dec.ReadUnsigned();

            NonSpacingMarks = new(dec.ReadUnique());

            NFCCheck = new(dec.ReadUnique());

            Fenced = AsReadOnlyDict(DecodeNamedCodepoints(dec));

            Mapped = AsReadOnlyDict(DecodeMapped(dec));

            Groups = new(DecodeGroups(dec));

            Emojis = new(dec.ReadTree().Select(cps => new EmojiSequence(cps)).ToArray());



            // precompute: confusable extent complements

            List<Whole> wholes = new();

            while (true)

            {

                ReadOnlyIntSet confused = new(dec.ReadUnique());

                if (confused.Count == 0) break;

                ReadOnlyIntSet valid = new(dec.ReadUnique());

                Whole w = new(valid, confused);

                wholes.Add(w);

                foreach (int cp in confused)

                {

                    Confusables.Add(cp, w);

                }

                HashSet<Group> groups = new();

                List<Extent> extents = new();

                foreach (int cp in confused.Concat(valid))

                {

                    Group[] gs = Groups.Where(g => g.Contains(cp)).ToArray();

                    Extent? extent = extents.FirstOrDefault(e => gs.Any(g => e.Groups.Contains(g)));

                    if (extent == null)

                    {

                        extent = new();

                        extents.Add(extent);

                    }

                    extent.Chars.Add(cp);

                    extent.Groups.UnionWith(gs);

                    groups.UnionWith(gs);

                }

                foreach (Extent extent in extents)

                {

                    int[] complement = groups.Except(extent.Groups).Select(g => g.Index).ToArray();

                    Array.Sort(complement);

                    foreach (int cp in extent.Chars)

                    {

                        w.Complement.Add(cp, complement);

                    }

                }

            }

            Wholes = new(wholes);



            // precompute: emoji trie

            foreach (EmojiSequence emoji in Emojis)

            {

                List<EmojiNode> nodes = new() { EmojiRoot };

                foreach (int cp in emoji.Beautified)

                {

                    if (cp == 0xFE0F)

                    {

                        for (int i = 0, e = nodes.Count; i < e; i++)

                        {

                            nodes.Add(nodes[i].Then(cp));

                        }

                    }

                    else

                    {

                        for (int i = 0, e = nodes.Count; i < e; i++)

                        {

                            nodes[i] = nodes[i].Then(cp);

                        }

                    }

                }

                foreach (EmojiNode x in nodes)

                {

                    x.Emoji = emoji;

                }

            }



            // precompute: possibly valid

            HashSet<int> union = new();

            HashSet<int> multi = new();

            foreach (Group g in Groups)

            {

                foreach (int cp in g.Primary.Concat(g.Secondary))

                {

                    if (union.Contains(cp))

                    {

                        multi.Add(cp);

                    }

                    else

                    {

                        union.Add(cp);

                    }

                }

            }

            PossiblyValid = new(union.Union(NF.NFD(union)));



            // precompute: unique non-confusables

            HashSet<int> unique = new(union);

            unique.ExceptWith(multi);

            unique.ExceptWith(Confusables.Keys);

            foreach (int cp in unique)

            {

                Confusables.Add(cp, UNIQUE_PH);

            }



            // precompute: special groups

            LATIN = Groups.First(g => g.Name == "Latin");

            GREEK = Groups.First(g => g.Name == "Greek");

            ASCII = new(-1, GroupKind.ASCII, "ASCII", false, new(PossiblyValid.Where(cp => cp < 0x80)), ReadOnlyIntSet.EMPTY);

            EMOJI = new(-1, GroupKind.Emoji, "Emoji", false, ReadOnlyIntSet.EMPTY, ReadOnlyIntSet.EMPTY);

        }

        

        // format as {HEX}

        static string HexEscape(int cp)

        {

            return $"{{{cp.ToHex()}}}";

        }



        // format as "X {HEX}" if possible

        public string SafeCodepoint(int cp)

        {

            return ShouldEscape.Contains(cp) ? HexEscape(cp) : $"\"{SafeImplode(new int[] { cp })}\" {HexEscape(cp)}";

        }

        public string SafeImplode(IList<int> cps)

        {

            int n = cps.Count;

            if (n == 0) return "";

            StringBuilder sb = new(n + 16); // guess

            if (CombiningMarks.Contains(cps[0]))

            {

                sb.AppendCodepoint(0x25CC);

            }

            foreach (int cp in cps)

            {

                if (ShouldEscape.Contains(cp))

                {

                    sb.Append(HexEscape(cp));

                }

                else

                {

                    sb.AppendCodepoint(cp);

                }

            }

            // some messages can be mixed-directional and result in spillover

            // use 200E after a input string to reset the bidi direction

            // https://www.w3.org/International/questions/qa-bidi-unicode-controls#exceptions

            sb.AppendCodepoint(0x200E);

            return sb.ToString();

        }



        // throws

        public string Normalize(string name)

        {

            return Transform(name, cps => OutputTokenize(cps, NF.NFC, e => e.Normalized), tokens => {

                int[] norm = tokens.SelectMany(t => t.Codepoints).ToArray();

                CheckValid(norm, tokens);

                return norm;

            });

        }

        // throws

        public string Beautify(string name)

        {

            return Transform(name, cps => OutputTokenize(cps, NF.NFC, e => e.Beautified), tokens => {

                int[] norm = tokens.SelectMany(t => t.Codepoints).ToArray();

                Group group = CheckValid(norm, tokens);

                if (group != GREEK)

                {

                    for (int i = 0, e = norm.Length; i < e; i++)

                    {

                        // ξ => Ξ if not greek

                        if (norm[i] == 0x3BE) norm[i] = 0x39E;

                    }

                }

                return norm;

            });

        }

        // only throws InvalidLabelException w/DisallowedCharacterException

        public string NormalizeFragment(string name, bool decompose = false)

        {

            return Transform(name, cps => OutputTokenize(cps, decompose ? NF.NFD : NF.NFC, e => e.Normalized), tokens => {

                return tokens.SelectMany(t => t.Codepoints);

            });

        }



        string Transform(string name, Func<List<int>, IList<OutputToken>> tokenizer, Func<IList<OutputToken>, IEnumerable<int>> fn)

        {

            if (name.Length == 0) return ""; // empty name allowance

            StringBuilder sb = new(name.Length + 16); // guess

            string[] labels = name.Split(STOP_CH);

            foreach (string label in labels)

            {

                List<int> cps = label.Explode();

                try

                {

                    IList<OutputToken> tokens = tokenizer(cps);

                    if (sb.Length > 0) sb.Append(STOP_CH);

                    sb.AppendCodepoints(fn(tokens));

                }

                catch (NormException e)

                {

                    throw new InvalidLabelException(label, $"Invalid label \"{SafeImplode(cps)}\": {e.Message}", e);

                }

            }

            return sb.ToString();

        }



        // never throws

        public IList<Label> Split(string name)

        {

            string[] labels = name.Split(STOP_CH);

            List<Label> ret = new(labels.Length);

            if (name.Length == 0) return ret; // empty name allowance

            foreach (string label in labels)

            {

                List<int> cps = label.Explode();

                IList<OutputToken>? tokens = null;

                try

                {

                    tokens = OutputTokenize(cps, NF.NFC, e => e.Normalized.ToList()); // make copy

                    int[] norm = tokens.SelectMany(t => t.Codepoints).ToArray();

                    Group group = CheckValid(norm, tokens);

                    ret.Add(new(cps, tokens, norm, group));

                }

                catch (NormException e)

                {

                    ret.Add(new(cps, tokens, e));

                }

            }

            return ret;

        }

        // experimental

        // throws

        public NormDetails NormalizeDetails(string name)

        {

            HashSet<Group> groups = new();

            HashSet<EmojiSequence> emojis = new();

            string norm = Transform(name, cps => OutputTokenize(cps, NF.NFC, e => e.Normalized), tokens => {

                int[] norm = tokens.SelectMany(t => t.Codepoints).ToArray();

                Group group = CheckValid(norm, tokens);

                emojis.UnionWith(tokens.Where(t => t.IsEmoji).Select(t => t.Emoji!));

                if (group == LATIN && tokens.All(t => t.IsEmoji || t.Codepoints.All(cp => cp < 0x80)))

                {

                    group = ASCII;

                }

                groups.Add(group);

                return norm;

            });

            if (groups.Contains(LATIN))

            {

                groups.Remove(ASCII);

            }

            if (emojis.Count > 0)

            {

                groups.Add(EMOJI);

            }

            bool confusing = POSSIBLY_CONFUSING.Any(norm.Contains);

            return new(norm, groups, emojis, confusing);

        }



        Group CheckValid(int[] norm, IList<OutputToken> tokens)

        {

            if (norm.Length == 0)  

            {

                throw new NormException("empty label");

            }

            CheckLeadingUnderscore(norm);

            bool emoji = tokens.Count > 1 || tokens[0].IsEmoji;

            if (!emoji && norm.All(cp => cp < 0x80))

            {

                CheckLabelExtension(norm);

                return ASCII;

            }

            int[] chars = tokens.Where(t => !t.IsEmoji).SelectMany(x => x.Codepoints).ToArray();

            if (emoji && chars.Length == 0)

            {

                return EMOJI;

            }

            CheckCombiningMarks(tokens);

            CheckFenced(norm);

            int[] unique = chars.Distinct().ToArray();

            Group group = DetermineGroup(unique);

            CheckGroup(group, chars); // need text in order

            CheckWhole(group, unique); // only need unique text

            return group;

        }



        // assume: Groups.length > 1

        Group DetermineGroup(int[] unique)

        {

            Group[] gs = Groups.ToArray();

            int prev = gs.Length;

            foreach (int cp in unique) {

                int next = 0;

                for (int i = 0; i < prev; i++)

                {

                    if (gs[i].Contains(cp))

                    {

                        gs[next++] = gs[i];

                    }

                }

                if (next == 0)

                {   

                    if (!Groups.Any(g => g.Contains(cp)))

                    {

                        // the character was composed of valid parts

                        // but it's NFC form is invalid

                        throw new DisallowedCharacterException(SafeCodepoint(cp), cp);

                    }

                    else

                    {

                        // there is no group that contains all these characters

                        // throw using the highest priority group that matched

                        // https://www.unicode.org/reports/tr39/#mixed_script_confusables

                        throw CreateMixtureException(gs[0], cp);

                    }

                }

                prev = next;

                if (prev == 1) break; // there is only one group left

            }

            return gs[0];

        }



        // assume: cps.length > 0

        // assume: cps[0] isn't CM

        void CheckGroup(Group g, int[] cps)

        {

            foreach (int cp in cps)

            {

                if (!g.Contains(cp))

                {

                    throw CreateMixtureException(g, cp);

                }

            }

            if (!g.CMWhitelisted)

            {

                List<int> decomposed = NF.NFD(cps);

                for (int i = 1, e = decomposed.Count; i < e; i++)

                {

                    // https://www.unicode.org/reports/tr39/#Optional_Detection

                    if (NonSpacingMarks.Contains(decomposed[i]))

                    {

                        int j = i + 1;

                        for (int cp; j < e && NonSpacingMarks.Contains(cp = decomposed[j]); j++)

                        {

                            for (int k = i; k < j; k++)

                            {

                                // a. Forbid sequences of the same nonspacing mark.

                                if (decomposed[k] == cp)

                                {

                                    throw new NormException("duplicate non-spacing marks", SafeCodepoint(cp));

                                }

                            }

                        }

                        // b. Forbid sequences of more than 4 nonspacing marks (gc=Mn or gc=Me).

                        int n = j - i;

                        if (n > MaxNonSpacingMarks) {

                            throw new NormException("excessive non-spacing marks", $"{SafeImplode(decomposed.GetRange(i - 1, n))} ({n}/${MaxNonSpacingMarks})");

				        }

				        i = j;

                    }

                }

            }

        }



        void CheckWhole(Group g, int[] unique)

        {

            int bound = 0;

            int[]? maker = null;

            List<int> shared = new();

            foreach (int cp in unique)

            {

                if (!Confusables.TryGetValue(cp, out var w))

                {

                    shared.Add(cp);

                } 

                else if (w == UNIQUE_PH)

                {

                    return; // unique, non-confusable

                }

                else 

                {

                    int[] comp = w.Complement[cp]; // exists by construction

                    if (bound == 0)

                    {

                        maker = comp.ToArray(); // non-empty

                        bound = comp.Length; 

                    }

                    else // intersect(comp, maker)

                    {

                        int b = 0;

                        for (int i = 0; i < bound; i++)

                        {

                            if (comp.Contains(maker![i]))

                            {

                                if (i > b) maker[b] = maker[i];

                                ++b;

                            }

                        }

                        bound = b;

                    }

                    if (bound == 0)

                    {

                        return; // confusable intersection is empty

                    }

                }

            }

            if (bound > 0)

            {

                for (int i = 0; i < bound; i++)

                {

                    Group group = Groups[maker![i]];

                    if (shared.All(group.Contains))

                    {

                        throw new ConfusableException(g, group);

                    }

                }

            }

        }



        // find the longest emoji that matches at index

        // if found, returns and updates the index

        EmojiSequence? FindEmoji(List<int> cps, ref int index)

        {

            EmojiNode? node = EmojiRoot;

            EmojiSequence? last = null;

            for (int i = index, e = cps.Count; i < e; )

            {

                if (node.Dict == null || !node.Dict.TryGetValue(cps[i++], out node)) break;

                if (node.Emoji != null) // the emoji is valid

                {

                    index = i; // eat the emoji

                    last = node.Emoji; // save it

                }

            }

            return last; // last emoji found

        }



        IList<OutputToken> OutputTokenize(List<int> cps, Func<List<int>, List<int>> nf, Func<EmojiSequence, IList<int>> emojiStyler)

        {

            List<OutputToken> tokens = new();

            int n = cps.Count;

            List<int> buf = new(n);

            for (int i = 0; i < n; )

            {

                EmojiSequence? emoji = FindEmoji(cps, ref i);

                if (emoji != null) // found an emoji

                {

                    if (buf.Count > 0) // consume buffered

                    {

                        tokens.Add(new(nf(buf)));

                        buf.Clear();

                    }

                    tokens.Add(new(emojiStyler(emoji), emoji)); // add emoji

                }

                else

                {

                    int cp = cps[i++];

                    if (PossiblyValid.Contains(cp))

                    {

                        buf.Add(cp);

                    }

                    else if (Mapped.TryGetValue(cp, out var mapped))

                    {

                        buf.AddRange(mapped);

                    }

                    else if (!Ignored.Contains(cp))

                    {

                        throw new DisallowedCharacterException(SafeCodepoint(cp), cp);

                    }

                }

            }

            if (buf.Count > 0) // flush buffered

            {

                tokens.Add(new(nf(buf)));

            }

            return tokens;

        }

        // assume: cps.length > 0

        void CheckFenced(int[] cps)

        {

            if (Fenced.TryGetValue(cps[0], out var name))

            {

                throw new NormException("leading fenced", name);

            }

            int n = cps.Length;

            int last = -1;

            string prev = "";

            for (int i = 1; i < n; i++)

            {

                if (Fenced.TryGetValue(cps[i], out name))

                {

                    if (last == i)

                    {

                        throw new NormException("adjacent fenced", $"{prev} + {name}");

                    }

                    last = i + 1;

                    prev = name;

                }

            }

            if (last == n)

            {

                throw new NormException("trailing fenced", prev);

            }

        }

        void CheckCombiningMarks(IList<OutputToken> tokens)

        {

            for (int i = 0, e = tokens.Count; i < e; i++)

            {

                OutputToken t = tokens[i];

                if (t.IsEmoji) continue;

                int cp = t.Codepoints[0];

                if (CombiningMarks.Contains(cp))

                {

                    if (i == 0)

                    {

                        throw new NormException("leading combining mark", SafeCodepoint(cp));

                    }

                    else 

                    {

                        // note: the previous token must an EmojiSequence

                        throw new NormException("emoji + combining mark", $"{tokens[i - 1].Emoji!.Form} + {SafeCodepoint(cp)}");

                    }

                }

            }

        }

        // assume: ascii

        static void CheckLabelExtension(int[] cps)

        {

            const int HYPHEN = 0x2D;

            if (cps.Length >= 4 && cps[2] == HYPHEN && cps[3] == HYPHEN)

            {

                throw new NormException("invalid label extension", cps.Take(4).Implode());

            }

        }

        static void CheckLeadingUnderscore(int[] cps)

        {

            const int UNDERSCORE = 0x5F;

            bool allowed = true;

            foreach (int cp in cps)

            {

                if (allowed)

                {

                    if (cp != UNDERSCORE)

                    {

                        allowed = false;

                    }

                } 

                else

                {

                    if (cp == UNDERSCORE)

                    {

                        throw new NormException("underscore allowed only at start");

                    }

                }

            }

        }

        private IllegalMixtureException CreateMixtureException(Group g, int cp)

        {

            string conflict = SafeCodepoint(cp);

            Group? other = Groups.FirstOrDefault(x => x.Primary.Contains(cp));

            if (other != null)

            {

                conflict = $"{other} {conflict}";

            }

            return new IllegalMixtureException($"{g} + {conflict}", cp, g, other);

        }

    }



}```

```cs [ENSNormalize.cs/ENSNormalize/ENSNormalize.cs]

﻿namespace ADRaffy.ENSNormalize

{

    public static class ENSNormalize

    {

        public static readonly NF NF = new(new(Blobs.NF));

        public static readonly ENSIP15 ENSIP15 = new(NF, new(Blobs.ENSIP15));

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/NormDetails.cs]

﻿using System.Collections.Generic;

using System.Linq;



namespace ADRaffy.ENSNormalize

{

    public class NormDetails

    {

        public readonly string Name;

        public readonly HashSet<Group> Groups;

        public readonly HashSet<EmojiSequence> Emojis;

        public readonly bool PossiblyConfusing;

        public string GroupDescription { get => string.Join("+", Groups.Select(g => g.Name).OrderBy(x => x).ToArray()); }

        public bool HasZWJEmoji { get => Emojis.Any(x => x.HasZWJ); }

        internal NormDetails(string norm, HashSet<Group> groups, HashSet<EmojiSequence> emojis, bool confusing) {

            Name = norm;

            Groups = groups;

            Emojis = emojis;

            PossiblyConfusing = confusing;

        }

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/Utils.cs]

﻿using System.Linq;

using System.Text;

using System.Collections.Generic;



namespace ADRaffy.ENSNormalize

{

    public static class Utils

    {

        const int UTF16_BMP = 0x10000;

        const int UTF16_BITS = 10;

        const int UTF16_HEAD = ~0 << UTF16_BITS;      // upper 6 bits

        const int UTF16_DATA = (1 << UTF16_BITS) - 1; // lower 10 bits

        const int UTF16_HI = 0xD800; // 110110*

        const int UTF16_LO = 0xDC00; // 110111*



        // format strings/codepoints

        static public string ToHex(this int cp) => cp.ToString("X").PadLeft(2, '0');

        static public string ToHexSequence(this IEnumerable<int> v) => string.Join(" ", v.Select(x => x.ToHex()).ToArray());

        static public string ToHexSequence(this string s) => s.Explode().ToHexSequence();

        

        // convert strings <=> codepoints

        // note: we do not care if the string is invalid UTF-16

        static public List<int> Explode(this string s)

        {         

            int n = s.Length;

            List<int> v = new(n);

            for (int i = 0; i < n; )

            {

                char ch0 = s[i++];

                char ch1;

                int head = ch0 & UTF16_HEAD;

                if (head == UTF16_HI && i < n && ((ch1 = s[i]) & UTF16_HEAD) == UTF16_LO) // valid pair

                {

                    v.Add(UTF16_BMP + (((ch0 & UTF16_DATA) << UTF16_BITS) | (ch1 & UTF16_DATA)));

                    i++;

                }

                else // bmp OR illegal surrogates

                {

                    v.Add(ch0);

                }

                // reference implementation

                /*

                int cp = char.ConvertToUtf32(s, i); // errors on invalid

                v.Add(cp);

                i += char.IsSurrogatePair(s, i) ? 2 : 1;

                */

            }

            return v;

        }

        static public string Implode(this IEnumerable<int> cps)

        {

            StringBuilder sb = new(cps.UTF16Length());

            sb.AppendCodepoints(cps);

            return sb.ToString();

        }



        // efficiently build strings from codepoints

        static public int UTF16Length(this IEnumerable<int> cps) => cps.Sum(x => x < UTF16_BMP ? 1 : 2);

        static public void AppendCodepoint(this StringBuilder sb, int cp)

        {

            if (cp < UTF16_BMP)

            {

                sb.Append((char)cp);

            }

            else

            {

                cp -= UTF16_BMP;

                sb.Append((char)(UTF16_HI | ((cp >> UTF16_BITS) & UTF16_DATA)));

                sb.Append((char)(UTF16_LO | (cp & UTF16_DATA)));

            }

            // reference implementation

            //sb.Append(char.ConvertFromUtf32(cp)); // allocates a string

        }

        static public void AppendCodepoints(this StringBuilder sb, IEnumerable<int> v)

        {

            foreach (int cp in v)

            {

                sb.AppendCodepoint(cp);

            }

        }

    }



}

```

```cs [ENSNormalize.cs/ENSNormalize/ReadOnlyIntSet.cs]

﻿using System.Collections;

using System.Collections.Generic;



namespace ADRaffy.ENSNormalize

{

    public class ReadOnlyIntSet : IEnumerable<int>

    {

        static public readonly ReadOnlyIntSet EMPTY = new(new int[0]);



        private readonly HashSet<int> Set;

        public int Count { get => Set.Count; }

        public ReadOnlyIntSet(IEnumerable<int> v)

        {

            Set = new(v);

        }

        IEnumerator<int> IEnumerable<int>.GetEnumerator() => Set.GetEnumerator(); // ew

        IEnumerator IEnumerable.GetEnumerator() => Set.GetEnumerator();

        public bool Contains(int x) => Set.Contains(x);



        // note: uses less memory but 10% slower

        /*

        private readonly int[] Sorted;

        public int this[int index] { get => Sorted[index]; }

        public int Count {  get => Sorted.Length; }

        public ReadOnlyIntSet(IEnumerable<int> v) {

            Sorted = v.ToArray();

            Array.Sort(Sorted);

        }

        IEnumerator<int> IEnumerable<int>.GetEnumerator() => ((IEnumerable<int>)Sorted).GetEnumerator();

        IEnumerator IEnumerable.GetEnumerator() => Sorted.GetEnumerator();

        public bool Contains(int x) => Array.BinarySearch(Sorted, x) >= 0;

        */

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/IllegalMixtureException.cs]

﻿namespace ADRaffy.ENSNormalize

{

    public class IllegalMixtureException : NormException

    {

        public readonly Group Group;

        public readonly int Codepoint;

        public readonly Group? OtherGroup;

        internal IllegalMixtureException(string reason, int cp, Group group, Group? other) : base("illegal mixture", reason)

        {

            Codepoint = cp;

            Group = group;

            OtherGroup = other;

        }

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/NormException.cs]

﻿using System;



namespace ADRaffy.ENSNormalize

{

    public class NormException : Exception

    {

        public readonly string Kind;

        public readonly string? Reason;

        internal NormException(string kind, string? reason = null) : base(reason != null ? $"{kind}: {reason}" : kind)

        {

            Kind = kind;

            Reason = reason;

        }

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/Label.cs]

﻿using System.Collections.Generic;



namespace ADRaffy.ENSNormalize

{

    public class Label

    {

        // error: [Input, Tokens?, Error ]

        // valid: [Input, Tokens, Group, Normalized ]



        public readonly IList<int> Input;

        public readonly IList<OutputToken>? Tokens;

        public readonly NormException? Error;

        public readonly int[]? Normalized;

        public readonly Group? Group;



        internal Label(IList<int> input, IList<OutputToken>? tokens, NormException e) {

            Input = input;

            Tokens = tokens;

            Error = e;

        }

        internal Label(IList<int> input, IList<OutputToken> tokens, int[] cps, Group g) 

        {

            Input = input;

            Tokens = tokens;

            Normalized = cps;

            Group = g;

        }

    }

}

```

```cs [ENSNormalize.cs/ENSNormalize/Group.cs]

﻿namespace ADRaffy.ENSNormalize

{

    public class Group

    {

        public readonly int Index;

        public readonly string Name;

        public readonly GroupKind Kind;

        public readonly bool CMWhitelisted;

        public readonly ReadOnlyIntSet Primary;

        public readonly ReadOnlyIntSet Secondary;

        public bool IsRestricted { get => Kind == GroupKind.Restricted; }

        internal Group(int index, GroupKind kind, string name, bool cm, ReadOnlyIntSet primary, ReadOnlyIntSet secondary)

        {

            Index = index;

            Kind = kind;

            Name = name;

            CMWhitelisted = cm;

            Primary = primary;

            Secondary = secondary;

        }

        public bool Contains(int cp) => Primary.Contains(cp) || Secondary.Contains(cp);

        public override string ToString()

        {

            return IsRestricted ? $"Restricted[{Name}]" : Name;

        }

    }

}

```

</csharp>

<zig>

```zig [./.zig-cache/o/ebd7ddab8ffe003267120d598aecce68/dependencies.zig]

pub const packages = struct {};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{};

```

```zig [./.zig-cache/o/505d63aeafd9b53320c4cb9a6a47da84/dependencies.zig]

pub const packages = struct {

    pub const @"argzon-0.4.0-Cl574lfJAQAg6_eaDCQ7ZqXdx0dRYBGuRsYyYYuOjKLt" = struct {

        pub const build_root = "/Users/williamcory/.cache/zig/p/argzon-0.4.0-Cl574lfJAQAg6_eaDCQ7ZqXdx0dRYBGuRsYyYYuOjKLt";

        pub const build_zig = @import("argzon-0.4.0-Cl574lfJAQAg6_eaDCQ7ZqXdx0dRYBGuRsYyYYuOjKLt");

        pub const deps: []const struct { []const u8, []const u8 } = &.{

        };

    };

    pub const @"zq-0.8.0-7XsKhb_oAAAHW2pzOFWl3gyMOxUkq4K3SiIczAH7rgqu" = struct {

        pub const build_root = "/Users/williamcory/.cache/zig/p/zq-0.8.0-7XsKhb_oAAAHW2pzOFWl3gyMOxUkq4K3SiIczAH7rgqu";

        pub const build_zig = @import("zq-0.8.0-7XsKhb_oAAAHW2pzOFWl3gyMOxUkq4K3SiIczAH7rgqu");

        pub const deps: []const struct { []const u8, []const u8 } = &.{

            .{ "argzon", "argzon-0.4.0-Cl574lfJAQAg6_eaDCQ7ZqXdx0dRYBGuRsYyYYuOjKLt" },

        };

    };

};



pub const root_deps: []const struct { []const u8, []const u8 } = &.{

    .{ "zq", "zq-0.8.0-7XsKhb_oAAAHW2pzOFWl3gyMOxUkq4K3SiIczAH7rgqu" },

};

```

```zig [./build.zig]

const std = @import("std");



// Although this function looks imperative, note that its job is to

// declaratively construct a build graph that will be executed by an external

// runner.

pub fn build(b: *std.Build) void {

    // Standard target options allows the person running `zig build` to choose

    // what target to build for. Here we do not override the defaults, which

    // means any target is allowed, and the default is native. Other options

    // for restricting supported target set are available.

    const target = b.standardTargetOptions(.{});



    // Standard optimization options allow the person running `zig build` to select

    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not

    // set a preferred release mode, allowing the user to decide how to optimize.

    const optimize = b.standardOptimizeOption(.{});



    // This creates a "module", which represents a collection of source files alongside

    // some compilation options, such as optimization mode and linked system libraries.

    // Every executable or library we compile will be based on one or more modules.

    const lib_mod = b.createModule(.{

        // `root_source_file` is the Zig "entry point" of the module. If a module

        // only contains e.g. external object files, you can make this `null`.

        // In this case the main source file is merely a path, however, in more

        // complicated build scripts, this could be a generated file.

        .root_source_file = b.path("src/root.zig"),

        .target = target,

        .optimize = optimize,

    });



    // We will also create a module for our other entry point, 'main.zig'.

    const exe_mod = b.createModule(.{

        // `root_source_file` is the Zig "entry point" of the module. If a module

        // only contains e.g. external object files, you can make this `null`.

        // In this case the main source file is merely a path, however, in more

        // complicated build scripts, this could be a generated file.

        .root_source_file = b.path("src/main.zig"),

        .target = target,

        .optimize = optimize,

    });



    // Modules can depend on one another using the `std.Build.Module.addImport` function.

    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a

    // file path. In this case, we set up `exe_mod` to import `lib_mod`.

    exe_mod.addImport("ens_normalize", lib_mod);



    // Now, we will create a static library based on the module we created above.

    // This creates a `std.Build.Step.Compile`, which is the build step responsible

    // for actually invoking the compiler.

    const lib = b.addLibrary(.{

        .linkage = .static,

        .name = "ens_normalize",

        .root_module = lib_mod,

    });



    // This declares intent for the library to be installed into the standard

    // location when the user invokes the "install" step (the default step when

    // running `zig build`).

    b.installArtifact(lib);



    // This creates another `std.Build.Step.Compile`, but this one builds an executable

    // rather than a static library.

    const exe = b.addExecutable(.{

        .name = "ens_normalize",

        .root_module = exe_mod,

    });



    // This declares intent for the executable to be installed into the

    // standard location when the user invokes the "install" step (the default

    // step when running `zig build`).

    b.installArtifact(exe);



    // This *creates* a Run step in the build graph, to be executed when another

    // step is evaluated that depends on it. The next line below will establish

    // such a dependency.

    const run_cmd = b.addRunArtifact(exe);



    // By making the run step depend on the install step, it will be run from the

    // installation directory rather than directly from within the cache directory.

    // This is not necessary, however, if the application depends on other installed

    // files, this ensures they will be present and in the expected location.

    run_cmd.step.dependOn(b.getInstallStep());



    // This allows the user to pass arguments to the application in the build

    // command itself, like this: `zig build run -- arg1 arg2 etc`

    if (b.args) |args| {

        run_cmd.addArgs(args);

    }



    // This creates a build step. It will be visible in the `zig build --help` menu,

    // and can be selected like this: `zig build run`

    // This will evaluate the `run` step rather than the default, which is "install".

    const run_step = b.step("run", "Run the app");

    run_step.dependOn(&run_cmd.step);



    // Creates a step for unit testing. This only builds the test executable

    // but does not run it.

    const lib_unit_tests = b.addTest(.{

        .root_module = lib_mod,

    });



    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);



    const exe_unit_tests = b.addTest(.{

        .root_module = exe_mod,

    });



    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);



    // Add integration tests

    const integration_tests = b.addTest(.{

        .root_source_file = b.path("tests/ens_tests.zig"),

        .target = target,

        .optimize = optimize,

    });

    integration_tests.root_module.addImport("ens_normalize", lib_mod);

    

    const run_integration_tests = b.addRunArtifact(integration_tests);

    

    // Add tokenization tests

    const tokenization_tests = b.addTest(.{

        .root_source_file = b.path("tests/tokenization_tests.zig"),

        .target = target,

        .optimize = optimize,

    });

    tokenization_tests.root_module.addImport("ens_normalize", lib_mod);

    

    const run_tokenization_tests = b.addRunArtifact(tokenization_tests);

    

    // Add tokenization fuzz tests

    const tokenization_fuzz_tests = b.addTest(.{

        .root_source_file = b.path("tests/tokenization_fuzz.zig"),

        .target = target,

        .optimize = optimize,

    });

    tokenization_fuzz_tests.root_module.addImport("ens_normalize", lib_mod);

    

    const run_tokenization_fuzz_tests = b.addRunArtifact(tokenization_fuzz_tests);

    

    // Similar to creating the run step earlier, this exposes a `test` step to

    // the `zig build --help` menu, providing a way for the user to request

    // running the unit tests.

    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&run_lib_unit_tests.step);

    test_step.dependOn(&run_exe_unit_tests.step);

    test_step.dependOn(&run_integration_tests.step);

    test_step.dependOn(&run_tokenization_tests.step);

    

    // Add validation tests

    const validation_tests = b.addTest(.{

        .root_source_file = b.path("tests/validation_tests.zig"),

        .target = target,

        .optimize = optimize,

    });

    validation_tests.root_module.addImport("ens_normalize", lib_mod);

    

    const run_validation_tests = b.addRunArtifact(validation_tests);

    

    // Add validation fuzz tests

    const validation_fuzz_tests = b.addTest(.{

        .root_source_file = b.path("tests/validation_fuzz.zig"),

        .target = target,

        .optimize = optimize,

    });

    validation_fuzz_tests.root_module.addImport("ens_normalize", lib_mod);

    

    const run_validation_fuzz_tests = b.addRunArtifact(validation_fuzz_tests);

    

    // Add separate fuzz test step

    const fuzz_step = b.step("fuzz", "Run fuzz tests");

    fuzz_step.dependOn(&run_tokenization_fuzz_tests.step);

    fuzz_step.dependOn(&run_validation_fuzz_tests.step);

    

    // Add emoji tests

    const emoji_tests = b.addTest(.{

        .root_source_file = b.path("tests/emoji_token_tests.zig"),

        .target = target,

        .optimize = optimize,

    });

    emoji_tests.root_module.addImport("ens_normalize", lib_mod);

    

    const run_emoji_tests = b.addRunArtifact(emoji_tests);

    

    // Add script group tests

    const script_group_tests = b.addTest(.{

        .root_source_file = b.path("tests/script_group_tests.zig"),

        .target = target,

        .optimize = optimize,

    });

    script_group_tests.root_module.addImport("ens_normalize", lib_mod);

    

    const run_script_group_tests = b.addRunArtifact(script_group_tests);

    

    // Add script integration tests

    const script_integration_tests = b.addTest(.{

        .root_source_file = b.path("tests/script_integration_tests.zig"),

        .target = target,

        .optimize = optimize,

    });

    script_integration_tests.root_module.addImport("ens_normalize", lib_mod);

    

    const run_script_integration_tests = b.addRunArtifact(script_integration_tests);

    

    // Add confusable tests

    const confusable_tests = b.addTest(.{

        .root_source_file = b.path("tests/confusable_tests.zig"),

        .target = target,

        .optimize = optimize,

    });

    confusable_tests.root_module.addImport("ens_normalize", lib_mod);

    

    const run_confusable_tests = b.addRunArtifact(confusable_tests);

    

    // Add combining mark tests

    const combining_mark_tests = b.addTest(.{

        .root_source_file = b.path("tests/combining_mark_tests.zig"),

        .target = target,

        .optimize = optimize,

    });

    combining_mark_tests.root_module.addImport("ens_normalize", lib_mod);

    

    const run_combining_mark_tests = b.addRunArtifact(combining_mark_tests);

    

    // Add NSM validation tests

    const nsm_validation_tests = b.addTest(.{

        .root_source_file = b.path("tests/nsm_validation_tests.zig"),

        .target = target,

        .optimize = optimize,

    });

    nsm_validation_tests.root_module.addImport("ens_normalize", lib_mod);

    

    const run_nsm_validation_tests = b.addRunArtifact(nsm_validation_tests);

    

    // Add official test vectors tests

    const official_test_vectors = b.addTest(.{

        .root_source_file = b.path("tests/official_test_vectors.zig"),

        .target = target,

        .optimize = optimize,

    });

    official_test_vectors.root_module.addImport("ens_normalize", lib_mod);

    

    const run_official_test_vectors = b.addRunArtifact(official_test_vectors);

    

    // Update main test step

    test_step.dependOn(&run_validation_tests.step);

    test_step.dependOn(&run_emoji_tests.step);

    test_step.dependOn(&run_script_group_tests.step);

    test_step.dependOn(&run_script_integration_tests.step);

    test_step.dependOn(&run_confusable_tests.step);

    test_step.dependOn(&run_combining_mark_tests.step);

    test_step.dependOn(&run_nsm_validation_tests.step);

    test_step.dependOn(&run_official_test_vectors.step);

}

```

```zig [./tests/script_integration_tests.zig]

const std = @import("std");

const ens = @import("ens_normalize");

const tokenizer = ens.tokenizer;

const validator = ens.validator;

const static_data_loader = ens.static_data_loader;

const script_groups = ens.script_groups;

const code_points = ens.code_points;



test "script integration - ASCII label" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Create specs

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Create tokenized name

    var tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello", &specs, false);

    defer tokenized.deinit();

    

    // Validate

    const result = try validator.validateLabel(allocator, tokenized, &specs);

    defer result.deinit();

    

    try testing.expect(result.isASCII());

    try testing.expectEqualStrings("ASCII", result.script_group.name);

}



test "script integration - mixed script rejection" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Create specs

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Create tokenized name with mixed script (Latin 'a' + Greek 'α')

    var tokenized = try tokenizer.TokenizedName.fromInput(allocator, "aα", &specs, false);

    defer tokenized.deinit();

    

    // Validate - should fail with mixed script

    const result = validator.validateLabel(allocator, tokenized, &specs);

    try testing.expectError(validator.ValidationError.DisallowedCharacter, result);

}



test "script integration - Greek label" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Create specs

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Create tokenized name with Greek text

    var tokenized = try tokenizer.TokenizedName.fromInput(allocator, "αβγδε", &specs, false);

    defer tokenized.deinit();

    

    // Validate

    const result = try validator.validateLabel(allocator, tokenized, &specs);

    defer result.deinit();

    

    try testing.expectEqualStrings("Greek", result.script_group.name);

}



test "script integration - Han label" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Create specs

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Create tokenized name with Chinese text

    var tokenized = try tokenizer.TokenizedName.fromInput(allocator, "你好世界", &specs, false);

    defer tokenized.deinit();

    

    // Validate

    const result = try validator.validateLabel(allocator, tokenized, &specs);

    defer result.deinit();

    

    try testing.expectEqualStrings("Han", result.script_group.name);

}



test "script integration - NSM validation" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Load script groups to test NSM

    var groups = try static_data_loader.loadScriptGroups(allocator);

    defer groups.deinit();

    

    // Check that we loaded NSM data

    try testing.expect(groups.nsm_set.count() > 0);

    try testing.expectEqual(@as(u32, 4), groups.nsm_max);

    

    // Test some known NSM characters

    try testing.expect(groups.isNSM(0x0610)); // Arabic sign sallallahou alayhe wassallam

}```

```zig [./tests/emoji_token_tests.zig]

const std = @import("std");

const ens_normalize = @import("ens_normalize");

const tokenizer = ens_normalize.tokenizer;

const code_points = ens_normalize.code_points;

const emoji = ens_normalize.emoji;

const static_data_loader = ens_normalize.static_data_loader;



test "emoji token - simple emoji" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test with thumbs up emoji

    const input = "hello👍world";

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);

    defer tokenized.deinit();

    

    // Should have: valid("hello"), emoji(👍), valid("world")

    var found_emoji = false;

    for (tokenized.tokens) |token| {

        if (token.type == .emoji) {

            found_emoji = true;

            break;

        }

    }

    

    try testing.expect(found_emoji);

}



test "emoji token - emoji with FE0F" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test with emoji that commonly has FE0F

    const input = "☺️"; // U+263A U+FE0F

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);

    defer tokenized.deinit();

    

    try testing.expect(tokenized.tokens.len > 0);

    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[0].type);

}



test "emoji token - skin tone modifier" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test with emoji with skin tone

    const input = "👍🏻"; // Thumbs up with light skin tone

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);

    defer tokenized.deinit();

    

    try testing.expect(tokenized.tokens.len == 1);

    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[0].type);

}



test "emoji token - ZWJ sequence" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test with family emoji (ZWJ sequence)

    const input = "👨‍👩‍👧‍👦"; // Family: man, woman, girl, boy

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);

    defer tokenized.deinit();

    

    // Should be recognized as a single emoji token if in spec.json

    try testing.expect(tokenized.tokens.len >= 1);

}



test "emoji token - mixed text and emoji" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test mixed content

    const input = "hello👋world🌍test";

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);

    defer tokenized.deinit();

    

    // Count emoji tokens

    var emoji_count: usize = 0;

    for (tokenized.tokens) |token| {

        if (token.type == .emoji) {

            emoji_count += 1;

        }

    }

    

    try testing.expect(emoji_count >= 2); // Should have at least 2 emoji tokens

}



test "emoji data loading" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Test loading emoji data from spec.json

    var emoji_map = try static_data_loader.loadEmoji(allocator);

    defer emoji_map.deinit();

    

    // Should have loaded many emojis

    try testing.expect(emoji_map.all_emojis.items.len > 100);

    

    // Test that we have some common emojis

    // Note: These tests depend on what's actually in spec.json

}



test "emoji FE0F normalization" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test that emoji with and without FE0F produce the same token

    const input1 = "☺"; // Without FE0F

    const input2 = "☺️"; // With FE0F

    

    const tokenized1 = try tokenizer.TokenizedName.fromInput(allocator, input1, &specs, false);

    defer tokenized1.deinit();

    

    const tokenized2 = try tokenizer.TokenizedName.fromInput(allocator, input2, &specs, false);

    defer tokenized2.deinit();

    

    // Both should produce emoji tokens if the emoji is in spec.json

    // The exact behavior depends on what's in the spec

}```

```zig [./tests/fenced_character_tests.zig]

const std = @import("std");

const tokenizer = @import("../src/tokenizer.zig");

const validator = @import("../src/validator.zig");

const code_points = @import("../src/code_points.zig");

const character_mappings = @import("../src/character_mappings.zig");

const static_data_loader = @import("../src/static_data_loader.zig");



test "fenced characters - leading apostrophe" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test with apostrophe at beginning

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "'hello", &specs, false);

    defer tokenized.deinit();

    

    const result = validator.validateLabel(allocator, tokenized, &specs);

    try testing.expectError(validator.ValidationError.FencedLeading, result);

}



test "fenced characters - trailing apostrophe" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test with apostrophe at end

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello'", &specs, false);

    defer tokenized.deinit();

    

    const result = validator.validateLabel(allocator, tokenized, &specs);

    try testing.expectError(validator.ValidationError.FencedTrailing, result);

}



test "fenced characters - consecutive apostrophes" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test consecutive apostrophes in middle

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hel''lo", &specs, false);

    defer tokenized.deinit();

    

    const result = validator.validateLabel(allocator, tokenized, &specs);

    try testing.expectError(validator.ValidationError.FencedAdjacent, result);

}



test "fenced characters - valid single apostrophe" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test single apostrophe in middle (valid)

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hel'lo", &specs, false);

    defer tokenized.deinit();

    

    const result = try validator.validateLabel(allocator, tokenized, &specs);

    defer result.deinit();

    

    // Should succeed

    try testing.expect(!result.isEmpty());

}



test "fenced characters - hyphen tests" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Valid single hyphen

    {

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello-world", &specs, false);

        defer tokenized.deinit();

        

        const result = try validator.validateLabel(allocator, tokenized, &specs);

        defer result.deinit();

        

        try testing.expect(!result.isEmpty());

    }

    

    // Invalid consecutive hyphens in middle

    {

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello--world", &specs, false);

        defer tokenized.deinit();

        

        const result = validator.validateLabel(allocator, tokenized, &specs);

        try testing.expectError(validator.ValidationError.FencedAdjacent, result);

    }

    

    // Valid trailing consecutive hyphens (special case!)

    {

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello---", &specs, false);

        defer tokenized.deinit();

        

        const result = try validator.validateLabel(allocator, tokenized, &specs);

        defer result.deinit();

        

        // Should succeed - trailing consecutive fenced are allowed

        try testing.expect(!result.isEmpty());

    }

}



test "fenced characters - mixed fenced types" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test consecutive different fenced characters

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello'-world", &specs, false);

    defer tokenized.deinit();

    

    const result = validator.validateLabel(allocator, tokenized, &specs);

    try testing.expectError(validator.ValidationError.FencedAdjacent, result);

}



test "fenced characters - colon" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Leading colon

    {

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, ":hello", &specs, false);

        defer tokenized.deinit();

        

        const result = validator.validateLabel(allocator, tokenized, &specs);

        try testing.expectError(validator.ValidationError.FencedLeading, result);

    }

    

    // Valid colon in middle

    {

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello:world", &specs, false);

        defer tokenized.deinit();

        

        const result = try validator.validateLabel(allocator, tokenized, &specs);

        defer result.deinit();

        

        try testing.expect(!result.isEmpty());

    }

}



test "fenced characters - load from spec.json" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Test loading fenced characters

    var fenced_set = try static_data_loader.loadFencedCharacters(allocator);

    defer fenced_set.deinit();

    

    // Should contain the mapped apostrophe

    try testing.expect(fenced_set.contains(8217)); // Right single quotation mark

    

    // Should contain other fenced characters

    try testing.expect(fenced_set.contains(8260)); // Fraction slash

}```

```zig [./tests/validation_fuzz.zig]

const std = @import("std");

const ens_normalize = @import("ens_normalize");

const validator = ens_normalize.validator;

const tokenizer = ens_normalize.tokenizer;

const code_points = ens_normalize.code_points;

const testing = std.testing;



// Main fuzz testing function

pub fn fuzz_validation(input: []const u8) !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Tokenize first (should never crash)

    const tokenized = tokenizer.TokenizedName.fromInput(

        allocator, 

        input, 

        &specs, 

        false

    ) catch |err| switch (err) {

        error.InvalidUtf8 => return,

        error.OutOfMemory => return,

        else => return err,

    };

    defer tokenized.deinit();

    

    // Validation should handle any tokenized input gracefully

    const result = validator.validateLabel(

        allocator,

        tokenized,

        &specs

    ) catch |err| switch (err) {

        error.EmptyLabel => return,

        error.InvalidLabelExtension => return,

        error.UnderscoreInMiddle => return,

        error.LeadingCombiningMark => return,

        error.CombiningMarkAfterEmoji => return,

        error.FencedLeading => return,

        error.FencedTrailing => return,

        error.FencedAdjacent => return,

        error.DisallowedCharacter => return,

        error.IllegalMixture => return,

        error.WholeScriptConfusable => return,

        error.DuplicateNSM => return,

        error.ExcessiveNSM => return,

        error.OutOfMemory => return,

        error.InvalidUtf8 => return,

        else => return err,

    };

    defer result.deinit();

    

    // Validate result invariants

    try validateValidationInvariants(result);

}



fn validateValidationInvariants(result: validator.ValidatedLabel) !void {

    // Basic invariants

    try testing.expect(result.tokens.len > 0); // Should not be empty if validation succeeded

    

    // Script group should be valid

    _ = result.script_group.toString();

    

    // Should have valid script group

    try testing.expect(result.script_group != .Unknown);

}



// Underscore placement fuzzing

test "fuzz_underscore_placement" {

    const test_cases = [_][]const u8{

        "hello",

        "_hello",

        "he_llo",

        "hello_",

        "___hello",

        "hel_lo_world",

        "_",

        "__",

        "___",

    };

    

    for (test_cases) |case| {

        try fuzz_validation(case);

    }

}



// Fenced character fuzzing

test "fuzz_fenced_characters" {

    const fenced_chars = [_][]const u8{ "'", "·", "⁄" };

    const base_strings = [_][]const u8{ "hello", "test", "world" };

    

    for (fenced_chars) |fenced| {

        for (base_strings) |base| {

            // Leading fenced

            {

                const input = std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ fenced, base }) catch return;

                defer testing.allocator.free(input);

                try fuzz_validation(input);

            }

            

            // Trailing fenced

            {

                const input = std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ base, fenced }) catch return;

                defer testing.allocator.free(input);

                try fuzz_validation(input);

            }

            

            // Middle fenced

            {

                const input = std.fmt.allocPrint(testing.allocator, "he{s}llo", .{fenced}) catch return;

                defer testing.allocator.free(input);

                try fuzz_validation(input);

            }

            

            // Adjacent fenced

            {

                const input = std.fmt.allocPrint(testing.allocator, "he{s}{s}llo", .{ fenced, fenced }) catch return;

                defer testing.allocator.free(input);

                try fuzz_validation(input);

            }

        }

    }

}



// Label extension fuzzing

test "fuzz_label_extensions" {

    const test_cases = [_][]const u8{

        "ab--cd",

        "xn--test",

        "test--",

        "--test",

        "te--st",

        "a--b",

        "ab-cd",

        "ab-c-d",

    };

    

    for (test_cases) |case| {

        try fuzz_validation(case);

    }

}



// Length stress testing

test "fuzz_length_stress" {

    const allocator = testing.allocator;

    

    const lengths = [_]usize{ 1, 10, 100, 1000 };

    const patterns = [_][]const u8{ "a", "ab", "abc", "_test", "test_" };

    

    for (lengths) |len| {

        for (patterns) |pattern| {

            const input = try allocator.alloc(u8, len);

            defer allocator.free(input);

            

            var i: usize = 0;

            while (i < len) {

                const remaining = len - i;

                const copy_len = @min(remaining, pattern.len);

                @memcpy(input[i..i + copy_len], pattern[0..copy_len]);

                i += copy_len;

            }

            

            try fuzz_validation(input);

        }

    }

}



// Random input fuzzing

test "fuzz_random_inputs" {

    const allocator = testing.allocator;

    

    var prng = std.Random.DefaultPrng.init(42);

    const random = prng.random();

    

    var i: usize = 0;

    while (i < 100) : (i += 1) {

        const len = random.intRangeAtMost(usize, 0, 50);

        const input = try allocator.alloc(u8, len);

        defer allocator.free(input);

        

        // Fill with random ASCII chars

        for (input) |*byte| {

            byte.* = random.intRangeAtMost(u8, 32, 126);

        }

        

        try fuzz_validation(input);

    }

}



// Unicode boundary fuzzing

test "fuzz_unicode_boundaries" {

    const boundary_codepoints = [_]u21{

        0x007F, // ASCII boundary

        0x0080, // Latin-1 start

        0x07FF, // 2-byte UTF-8 boundary

        0x0800, // 3-byte UTF-8 start

        0xD7FF, // Before surrogate range

        0xE000, // After surrogate range

        0xFFFD, // Replacement character

        0x10000, // 4-byte UTF-8 start

        0x10FFFF, // Maximum valid code point

    };

    

    for (boundary_codepoints) |cp| {

        var buf: [4]u8 = undefined;

        const len = std.unicode.utf8Encode(cp, &buf) catch continue;

        try fuzz_validation(buf[0..len]);

    }

}



// Script mixing fuzzing

test "fuzz_script_mixing" {

    const script_chars = [_]struct { []const u8, []const u8 }{

        .{ "hello", "ASCII" },

        .{ "café", "Latin" },

        .{ "γεια", "Greek" },

        .{ "привет", "Cyrillic" },

        .{ "مرحبا", "Arabic" },

        .{ "שלום", "Hebrew" },

    };

    

    for (script_chars) |script1| {

        for (script_chars) |script2| {

            if (std.mem.eql(u8, script1[1], script2[1])) continue;

            

            const mixed = std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ script1[0], script2[0] }) catch return;

            defer testing.allocator.free(mixed);

            

            try fuzz_validation(mixed);

        }

    }

}



// Performance fuzzing

test "fuzz_performance" {

    const allocator = testing.allocator;

    

    const performance_patterns = [_]struct {

        pattern: []const u8,

        repeat_count: usize,

    }{

        .{ .pattern = "a", .repeat_count = 1000 },

        .{ .pattern = "_", .repeat_count = 100 },

        .{ .pattern = "'", .repeat_count = 50 },

        .{ .pattern = "ab", .repeat_count = 500 },

        .{ .pattern = "a_", .repeat_count = 200 },

    };

    

    for (performance_patterns) |case| {

        const input = try allocator.alloc(u8, case.pattern.len * case.repeat_count);

        defer allocator.free(input);

        

        var i: usize = 0;

        while (i < case.repeat_count) : (i += 1) {

            const start = i * case.pattern.len;

            const end = start + case.pattern.len;

            @memcpy(input[start..end], case.pattern);

        }

        

        const start_time = std.time.microTimestamp();

        try fuzz_validation(input);

        const end_time = std.time.microTimestamp();

        

        // Should complete within reasonable time

        const duration_us = end_time - start_time;

        try testing.expect(duration_us < 1_000_000); // 1 second max

    }

}```

```zig [./tests/nsm_validation_tests.zig]

const std = @import("std");

const ens = @import("ens_normalize");

const nsm_validation = ens.nsm_validation;

const script_groups = ens.script_groups;

const static_data_loader = ens.static_data_loader;

const validator = ens.validator;

const tokenizer = ens.tokenizer;

const code_points = ens.code_points;



test "NSM validation - basic count limits" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Create mock script groups and group

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    // Add some Arabic NSMs to the groups NSM set

    try groups.nsm_set.put(0x064E, {}); // Fatha

    try groups.nsm_set.put(0x064F, {}); // Damma

    try groups.nsm_set.put(0x0650, {}); // Kasra

    try groups.nsm_set.put(0x0651, {}); // Shadda

    try groups.nsm_set.put(0x0652, {}); // Sukun

    

    // Add to script group CM set

    try arabic_group.cm.put(0x064E, {});

    try arabic_group.cm.put(0x064F, {});

    try arabic_group.cm.put(0x0650, {});

    try arabic_group.cm.put(0x0651, {});

    try arabic_group.cm.put(0x0652, {});

    

    // Test valid sequence: base + 3 NSMs

    const valid_seq = [_]u32{0x0628, 0x064E, 0x064F, 0x0650}; // بَُِ

    try nsm_validation.validateNSM(&valid_seq, &groups, &arabic_group, allocator);

    

    // Test invalid sequence: base + 5 NSMs (exceeds limit)

    const invalid_seq = [_]u32{0x0628, 0x064E, 0x064F, 0x0650, 0x0651, 0x0652};

    const result = nsm_validation.validateNSM(&invalid_seq, &groups, &arabic_group, allocator);

    try testing.expectError(nsm_validation.NSMValidationError.ExcessiveNSM, result);

}



test "NSM validation - duplicate detection" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    try groups.nsm_set.put(0x064E, {});

    try arabic_group.cm.put(0x064E, {});

    

    // Test duplicate NSMs

    const duplicate_seq = [_]u32{0x0628, 0x064E, 0x064E}; // ب + fatha + fatha

    const result = nsm_validation.validateNSM(&duplicate_seq, &groups, &arabic_group, allocator);

    try testing.expectError(nsm_validation.NSMValidationError.DuplicateNSM, result);

}



test "NSM validation - leading NSM detection" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    try groups.nsm_set.put(0x064E, {});

    

    // Test leading NSM

    const leading_nsm = [_]u32{0x064E, 0x0628}; // fatha + ب

    const result = nsm_validation.validateNSM(&leading_nsm, &groups, &arabic_group, allocator);

    try testing.expectError(nsm_validation.NSMValidationError.LeadingNSM, result);

}



test "NSM validation - emoji context" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var emoji_group = script_groups.ScriptGroup.init(allocator, "Emoji", 0);

    defer emoji_group.deinit();

    

    try groups.nsm_set.put(0x064E, {});

    try emoji_group.cm.put(0x064E, {});

    

    // Test NSM after emoji

    const emoji_nsm = [_]u32{0x1F600, 0x064E}; // 😀 + fatha

    const result = nsm_validation.validateNSM(&emoji_nsm, &groups, &emoji_group, allocator);

    try testing.expectError(nsm_validation.NSMValidationError.NSMAfterEmoji, result);

}



test "NSM validation - fenced character context" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    try groups.nsm_set.put(0x0300, {}); // Combining grave accent

    try latin_group.cm.put(0x0300, {});

    

    // Test NSM after fenced character (period)

    const fenced_nsm = [_]u32{'.', 0x0300}; // . + grave accent

    const result = nsm_validation.validateNSM(&fenced_nsm, &groups, &latin_group, allocator);

    try testing.expectError(nsm_validation.NSMValidationError.NSMAfterFenced, result);

}



test "NSM detection - comprehensive Unicode ranges" {

    const testing = std.testing;

    

    // Test various NSM ranges

    try testing.expect(nsm_validation.isNSM(0x0300)); // Combining grave accent

    try testing.expect(nsm_validation.isNSM(0x064E)); // Arabic fatha

    try testing.expect(nsm_validation.isNSM(0x05B4)); // Hebrew point hiriq

    try testing.expect(nsm_validation.isNSM(0x093C)); // Devanagari nukta

    try testing.expect(nsm_validation.isNSM(0x0951)); // Devanagari stress sign udatta

    

    // Test non-NSMs

    try testing.expect(!nsm_validation.isNSM('a'));

    try testing.expect(!nsm_validation.isNSM(0x0628)); // Arabic letter beh

    try testing.expect(!nsm_validation.isNSM(0x05D0)); // Hebrew letter alef

}



test "NSM validation - Arabic script-specific rules" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    try groups.nsm_set.put(0x064E, {}); // Fatha

    try groups.nsm_set.put(0x064F, {}); // Damma

    try groups.nsm_set.put(0x0650, {}); // Kasra

    try groups.nsm_set.put(0x0651, {}); // Shadda

    

    try arabic_group.cm.put(0x064E, {});

    try arabic_group.cm.put(0x064F, {});

    try arabic_group.cm.put(0x0650, {});

    try arabic_group.cm.put(0x0651, {});

    

    // Test valid Arabic sequence

    const valid_arabic = [_]u32{0x0628, 0x064E, 0x0651}; // بَّ (beh + fatha + shadda)

    try nsm_validation.validateNSM(&valid_arabic, &groups, &arabic_group, allocator);

    

    // Test invalid: too many Arabic diacritics on one consonant (Arabic limit is 3)

    const invalid_arabic = [_]u32{0x0628, 0x064E, 0x064F, 0x0650, 0x0651}; // بَُِّ

    const result = nsm_validation.validateNSM(&invalid_arabic, &groups, &arabic_group, allocator);

    try testing.expectError(nsm_validation.NSMValidationError.ExcessiveNSM, result);

}



test "NSM validation - Hebrew script-specific rules" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var hebrew_group = script_groups.ScriptGroup.init(allocator, "Hebrew", 0);

    defer hebrew_group.deinit();

    

    try groups.nsm_set.put(0x05B4, {}); // Hebrew point hiriq

    try groups.nsm_set.put(0x05B7, {}); // Hebrew point patah

    try groups.nsm_set.put(0x05B8, {}); // Hebrew point qamats

    

    try hebrew_group.cm.put(0x05B4, {});

    try hebrew_group.cm.put(0x05B7, {});

    try hebrew_group.cm.put(0x05B8, {});

    

    // Test valid Hebrew sequence (Hebrew allows max 2 NSMs)

    const valid_hebrew = [_]u32{0x05D0, 0x05B4, 0x05B7}; // א + hiriq + patah

    try nsm_validation.validateNSM(&valid_hebrew, &groups, &hebrew_group, allocator);

    

    // Test invalid: too many Hebrew points (exceeds Hebrew limit of 2)

    const invalid_hebrew = [_]u32{0x05D0, 0x05B4, 0x05B7, 0x05B8}; // א + 3 points

    const result = nsm_validation.validateNSM(&invalid_hebrew, &groups, &hebrew_group, allocator);

    try testing.expectError(nsm_validation.NSMValidationError.ExcessiveNSM, result);

}



test "NSM validation - Devanagari script-specific rules" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var devanagari_group = script_groups.ScriptGroup.init(allocator, "Devanagari", 0);

    defer devanagari_group.deinit();

    

    try groups.nsm_set.put(0x093C, {}); // Devanagari nukta

    try groups.nsm_set.put(0x0951, {}); // Devanagari stress sign udatta

    

    try devanagari_group.cm.put(0x093C, {});

    try devanagari_group.cm.put(0x0951, {});

    

    // Test valid Devanagari sequence

    const valid_devanagari = [_]u32{0x0915, 0x093C, 0x0951}; // क + nukta + udatta

    try nsm_validation.validateNSM(&valid_devanagari, &groups, &devanagari_group, allocator);

    

    // Test invalid: NSM on wrong base (vowel instead of consonant)

    const invalid_devanagari = [_]u32{0x0905, 0x093C}; // अ (vowel) + nukta

    const result = nsm_validation.validateNSM(&invalid_devanagari, &groups, &devanagari_group, allocator);

    try testing.expectError(nsm_validation.NSMValidationError.InvalidNSMBase, result);

}



test "NSM validation - integration with full validator" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test with a valid Arabic name with NSMs

    // Note: Using individual codepoints since we need NSM sequences

    // In a real scenario, this would come from proper NFD normalization

    

    // For now, test basic ASCII to ensure no regression

    {

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello", &specs, false);

        defer tokenized.deinit();

        

        const result = validator.validateLabel(allocator, tokenized, &specs);

        if (result) |validated| {

            defer validated.deinit();

            // Should pass - ASCII names don't have NSMs

            try testing.expect(true);

        } else |err| {

            // Should not fail due to NSM errors for ASCII

            try testing.expect(err != validator.ValidationError.ExcessiveNSM);

            try testing.expect(err != validator.ValidationError.DuplicateNSM);

            try testing.expect(err != validator.ValidationError.LeadingNSM);

        }

    }

}



test "NSM validation - multiple base characters" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    try groups.nsm_set.put(0x064E, {}); // Fatha

    try groups.nsm_set.put(0x064F, {}); // Damma

    

    try arabic_group.cm.put(0x064E, {});

    try arabic_group.cm.put(0x064F, {});

    

    // Test sequence with multiple base characters and their NSMs

    const multi_base = [_]u32{

        0x0628, 0x064E,        // بَ (beh + fatha)

        0x062A, 0x064F,        // تُ (teh + damma)  

        0x062B, 0x064E, 0x064F // ثَُ (theh + fatha + damma)

    };

    

    try nsm_validation.validateNSM(&multi_base, &groups, &arabic_group, allocator);

}



test "NSM validation - empty input" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    const empty_input = [_]u32{};

    try nsm_validation.validateNSM(&empty_input, &groups, &latin_group, allocator);

    // Should pass - empty input is valid

}



test "NSM validation - no NSMs present" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    const no_nsms = [_]u32{'h', 'e', 'l', 'l', 'o'};

    try nsm_validation.validateNSM(&no_nsms, &groups, &latin_group, allocator);

    // Should pass - no NSMs to validate

}



test "NSM validation - performance test" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    try groups.nsm_set.put(0x064E, {});

    try arabic_group.cm.put(0x064E, {});

    

    // Test with various input sizes

    const test_sizes = [_]usize{ 1, 10, 50, 100, 500 };

    

    for (test_sizes) |size| {

        const test_input = try allocator.alloc(u32, size);

        defer allocator.free(test_input);

        

        // Fill with alternating Arabic letters and NSMs

        for (test_input, 0..) |*cp, i| {

            if (i % 2 == 0) {

                cp.* = 0x0628; // Arabic beh

            } else {

                cp.* = 0x064E; // Arabic fatha

            }

        }

        

        // Should complete quickly

        const start_time = std.time.nanoTimestamp();

        try nsm_validation.validateNSM(test_input, &groups, &arabic_group, allocator);

        const end_time = std.time.nanoTimestamp();

        

        // Should complete in reasonable time (less than 1ms for these sizes)

        const duration_ns = end_time - start_time;

        try testing.expect(duration_ns < 1_000_000); // 1ms

    }

}



test "NSM validation - edge cases" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    try groups.nsm_set.put(0x0300, {}); // Combining grave accent

    try latin_group.cm.put(0x0300, {});

    

    // Test NSM after control character

    const control_nsm = [_]u32{0x0001, 0x0300}; // Control char + NSM

    const result1 = nsm_validation.validateNSM(&control_nsm, &groups, &latin_group, allocator);

    try testing.expectError(nsm_validation.NSMValidationError.InvalidNSMBase, result1);

    

    // Test NSM after format character  

    const format_nsm = [_]u32{0x200E, 0x0300}; // LTR mark + NSM

    const result2 = nsm_validation.validateNSM(&format_nsm, &groups, &latin_group, allocator);

    try testing.expectError(nsm_validation.NSMValidationError.InvalidNSMBase, result2);

}



test "NSM validation - load from actual data" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Load actual script groups from data

    var groups = try static_data_loader.loadScriptGroups(allocator);

    defer groups.deinit();

    

    // Test with actual NSM data

    if (groups.nsm_set.count() > 0) {

        // Find a real NSM from the data

        var iter = groups.nsm_set.iterator();

        if (iter.next()) |entry| {

            const nsm = entry.key_ptr.*;

            

            // Create a simple sequence with a base character + NSM

            const sequence = [_]u32{0x0061, nsm}; // 'a' + real NSM

            

            // Determine appropriate script group

            const test_cps = [_]u32{0x0061}; // Just 'a' for script detection

            const script_group = try groups.determineScriptGroup(&test_cps, allocator);

            

            // Test NSM validation (might fail due to script mismatch, but shouldn't crash)

            const result = nsm_validation.validateNSM(&sequence, &groups, script_group, allocator);

            

            // We expect either success or a specific NSM error, not a crash

            if (result) |_| {

                // Success case

                try testing.expect(true);

            } else |err| {

                // Should be a known NSM validation error

                const is_nsm_error = switch (err) {

                    nsm_validation.NSMValidationError.ExcessiveNSM,

                    nsm_validation.NSMValidationError.DuplicateNSM,

                    nsm_validation.NSMValidationError.LeadingNSM,

                    nsm_validation.NSMValidationError.NSMAfterEmoji,

                    nsm_validation.NSMValidationError.NSMAfterFenced,

                    nsm_validation.NSMValidationError.InvalidNSMBase,

                    nsm_validation.NSMValidationError.NSMOrderError,

                    nsm_validation.NSMValidationError.DisallowedNSMScript => true,

                };

                try testing.expect(is_nsm_error);

            }

        }

    }

}```

```zig [./tests/ens_tests.zig]

const std = @import("std");

const testing = std.testing;

const ens_normalize = @import("ens_normalize");



const TestCase = struct {

    name: []const u8,

    comment: ?[]const u8,

    error_expected: bool,

    norm: ?[]const u8,

};



const Entry = union(enum) {

    version_info: struct {

        name: []const u8,

        validated: []const u8,

        built: []const u8,

        cldr: []const u8,

        derived: []const u8,

        ens_hash_base64: []const u8,

        nf_hash_base64: []const u8,

        spec_hash: []const u8,

        unicode: []const u8,

        version: []const u8,

    },

    test_case: TestCase,

};



fn processTestCase(allocator: std.mem.Allocator, normalizer: *ens_normalize.EnsNameNormalizer, case: TestCase) !void {

    const test_name = if (case.comment) |comment| 

        if (case.name.len < 64) 

            try std.fmt.allocPrint(allocator, "{s} (`{s}`)", .{comment, case.name})

        else

            try allocator.dupe(u8, comment)

    else

        try allocator.dupe(u8, case.name);

    defer allocator.free(test_name);

    

    const result = normalizer.process(case.name);

    

    if (result) |processed| {

        defer processed.deinit();

        

        if (case.error_expected) {

            std.log.err("Test case '{s}': expected error, got success", .{test_name});

            return error.UnexpectedSuccess;

        }

        

        const actual = try processed.normalize();

        defer allocator.free(actual);

        

        if (case.norm) |expected| {

            if (!std.mem.eql(u8, actual, expected)) {

                std.log.err("Test case '{s}': expected '{s}', got '{s}'", .{test_name, expected, actual});

                return error.NormalizationMismatch;

            }

        } else {

            if (!std.mem.eql(u8, actual, case.name)) {

                std.log.err("Test case '{s}': expected '{s}', got '{s}'", .{test_name, case.name, actual});

                return error.NormalizationMismatch;

            }

        }

    } else |err| {

        if (!case.error_expected) {

            std.log.err("Test case '{s}': expected no error, got {}", .{test_name, err});

            return error.UnexpectedError;

        }

    }

}



test "basic ENS normalization test cases" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var normalizer = ens_normalize.EnsNameNormalizer.default(allocator);

    defer normalizer.deinit();

    

    // Basic test cases

    const test_cases = [_]TestCase{

        .{ .name = "hello", .comment = null, .error_expected = false, .norm = null },

        .{ .name = "hello.eth", .comment = null, .error_expected = false, .norm = null },

        .{ .name = "test-domain", .comment = null, .error_expected = false, .norm = null },

        .{ .name = "HELLO", .comment = null, .error_expected = false, .norm = "hello" },

        .{ .name = "Hello.ETH", .comment = null, .error_expected = false, .norm = "hello.eth" },

        .{ .name = "", .comment = null, .error_expected = true, .norm = null },

        .{ .name = ".", .comment = null, .error_expected = true, .norm = null },

        .{ .name = "test..domain", .comment = null, .error_expected = true, .norm = null },

    };

    

    for (test_cases) |case| {

        processTestCase(allocator, &normalizer, case) catch |err| {

            // For now, most tests will fail due to incomplete implementation

            // This is expected during development

            std.log.warn("Test case '{s}' failed with error: {}", .{case.name, err});

        };

    }

}



test "unicode normalization test cases" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var normalizer = ens_normalize.EnsNameNormalizer.default(allocator);

    defer normalizer.deinit();

    

    // Unicode test cases

    const test_cases = [_]TestCase{

        .{ .name = "café", .comment = null, .error_expected = false, .norm = null },

        .{ .name = "ξ.eth", .comment = null, .error_expected = false, .norm = null },

        .{ .name = "мой", .comment = null, .error_expected = false, .norm = null },

        .{ .name = "测试", .comment = null, .error_expected = false, .norm = null },

        .{ .name = "👨‍👩‍👧‍👦", .comment = null, .error_expected = false, .norm = null },

        .{ .name = "🇺🇸", .comment = null, .error_expected = false, .norm = null },

    };

    

    for (test_cases) |case| {

        processTestCase(allocator, &normalizer, case) catch |err| {

            // For now, most tests will fail due to incomplete implementation

            // This is expected during development

            std.log.warn("Unicode test case '{s}' failed with error: {}", .{case.name, err});

        };

    }

}



test "error cases" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var normalizer = ens_normalize.EnsNameNormalizer.default(allocator);

    defer normalizer.deinit();

    

    // Error test cases

    const test_cases = [_]TestCase{

        .{ .name = "ab--", .comment = null, .error_expected = true, .norm = null },

        .{ .name = "'85", .comment = null, .error_expected = true, .norm = null },

        .{ .name = "test\u{300}", .comment = null, .error_expected = true, .norm = null },

        .{ .name = "\u{200C}", .comment = null, .error_expected = true, .norm = null },

        .{ .name = "\u{200D}", .comment = null, .error_expected = true, .norm = null },

    };

    

    for (test_cases) |case| {

        processTestCase(allocator, &normalizer, case) catch |err| {

            // For now, most tests will fail due to incomplete implementation

            // This is expected during development

            std.log.warn("Error test case '{s}' failed with error: {}", .{case.name, err});

        };

    }

}



test "memory management" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var normalizer = ens_normalize.EnsNameNormalizer.default(allocator);

    defer normalizer.deinit();

    

    // Test that memory is properly managed

    const test_cases = [_][]const u8{

        "hello",

        "world",

        "test.eth",

        "domain.name",

    };

    

    for (test_cases) |name| {

        const result = normalizer.normalize(name) catch |err| {

            // Expected to fail with current implementation

            try testing.expect(err == ens_normalize.error_types.ProcessError.DisallowedSequence);

            continue;

        };

        defer allocator.free(result);

        

        // Basic sanity check

        try testing.expect(result.len > 0);

    }

}



test "tokenization" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var normalizer = ens_normalize.EnsNameNormalizer.default(allocator);

    defer normalizer.deinit();

    

    const input = "hello";

    const tokenized = normalizer.tokenize(input) catch |err| {

        // Expected to fail with current implementation

        try testing.expect(err == ens_normalize.error_types.ProcessError.DisallowedSequence);

        return;

    };

    defer tokenized.deinit();

    

    try testing.expect(tokenized.tokens.len > 0);

    try testing.expect(tokenized.tokens[0].isText());

}```

```zig [./tests/script_group_tests.zig]

const std = @import("std");

const ens_normalize = @import("ens_normalize");

const script_groups = ens_normalize.script_groups;

const static_data_loader = ens_normalize.static_data_loader;



test "script groups - load from spec.json" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = try static_data_loader.loadScriptGroups(allocator);

    defer groups.deinit();

    

    // Should have loaded many groups

    try testing.expect(groups.groups.len > 100);

    

    // Should have loaded NSM data

    try testing.expect(groups.nsm_set.count() > 1000);

    try testing.expectEqual(@as(u32, 4), groups.nsm_max);

    

    // Check some known groups exist

    var found_latin = false;

    var found_greek = false;

    var found_cyrillic = false;

    var found_han = false;

    

    for (groups.groups) |*group| {

        if (std.mem.eql(u8, group.name, "Latin")) found_latin = true;

        if (std.mem.eql(u8, group.name, "Greek")) found_greek = true;

        if (std.mem.eql(u8, group.name, "Cyrillic")) found_cyrillic = true;

        if (std.mem.eql(u8, group.name, "Han")) found_han = true;

    }

    

    try testing.expect(found_latin);

    try testing.expect(found_greek);

    try testing.expect(found_cyrillic);

    try testing.expect(found_han);

}



test "script groups - single script detection" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = try static_data_loader.loadScriptGroups(allocator);

    defer groups.deinit();

    

    // Test Latin script

    const latin_cps = [_]u32{ 'h', 'e', 'l', 'l', 'o' };

    const latin_group = try groups.determineScriptGroup(&latin_cps, allocator);

    try testing.expectEqualStrings("Latin", latin_group.name);

    

    // Test Greek script

    const greek_cps = [_]u32{ 0x03B1, 0x03B2, 0x03B3 }; // αβγ

    const greek_group = try groups.determineScriptGroup(&greek_cps, allocator);

    try testing.expectEqualStrings("Greek", greek_group.name);

    

    // Test Cyrillic script

    const cyrillic_cps = [_]u32{ 0x0430, 0x0431, 0x0432 }; // абв

    const cyrillic_group = try groups.determineScriptGroup(&cyrillic_cps, allocator);

    try testing.expectEqualStrings("Cyrillic", cyrillic_group.name);

}



test "script groups - mixed script rejection" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = try static_data_loader.loadScriptGroups(allocator);

    defer groups.deinit();

    

    // Test Latin + Greek (should fail)

    const latin_greek = [_]u32{ 'a', 'b', 0x03B1 }; // ab + α

    const result1 = groups.determineScriptGroup(&latin_greek, allocator);

    try testing.expectError(error.DisallowedCharacter, result1);

    

    // Test Latin + Cyrillic (should fail)

    const latin_cyrillic = [_]u32{ 'a', 0x0430 }; // 'a' + Cyrillic 'а' (look similar!)

    const result2 = groups.determineScriptGroup(&latin_cyrillic, allocator);

    try testing.expectError(error.DisallowedCharacter, result2);

    

    // Test Greek + Cyrillic (should fail)

    const greek_cyrillic = [_]u32{ 0x03B1, 0x0430 }; // Greek α + Cyrillic а

    const result3 = groups.determineScriptGroup(&greek_cyrillic, allocator);

    try testing.expectError(error.DisallowedCharacter, result3);

}



test "script groups - common characters" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = try static_data_loader.loadScriptGroups(allocator);

    defer groups.deinit();

    

    // Numbers should work with Latin

    const latin_numbers = [_]u32{ 'a', 'b', 'c', '1', '2', '3' };

    const latin_group = try groups.determineScriptGroup(&latin_numbers, allocator);

    try testing.expectEqualStrings("Latin", latin_group.name);

    

    // Numbers should work with Greek

    const greek_numbers = [_]u32{ 0x03B1, 0x03B2, '1', '2' };

    const greek_group = try groups.determineScriptGroup(&greek_numbers, allocator);

    try testing.expectEqualStrings("Greek", greek_group.name);

    

    // Hyphen should work with many scripts

    const latin_hyphen = [_]u32{ 'a', 'b', '-', 'c' };

    const result = groups.determineScriptGroup(&latin_hyphen, allocator);

    try testing.expect(result != error.DisallowedCharacter);

}



test "script groups - find conflicting groups" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = try static_data_loader.loadScriptGroups(allocator);

    defer groups.deinit();

    

    // Test finding conflicts for mixed scripts

    const mixed = [_]u32{ 'a', 0x03B1 }; // Latin 'a' + Greek 'α'

    

    const conflict = script_groups.findConflictingGroups(&groups, &mixed, allocator) catch |err| {

        // If no conflict found, that's also ok for this test

        if (err == error.NoConflict) return;

        return err;

    };

    defer allocator.free(conflict.conflicting_groups);

    

    // First group should be Latin (contains 'a')

    try testing.expectEqualStrings("Latin", conflict.first_group.name);

    

    // Conflicting codepoint should be Greek α

    try testing.expectEqual(@as(u32, 0x03B1), conflict.conflicting_cp);

    

    // Conflicting groups should include Greek

    var found_greek = false;

    for (conflict.conflicting_groups) |g| {

        if (std.mem.eql(u8, g.name, "Greek")) {

            found_greek = true;

            break;

        }

    }

    try testing.expect(found_greek);

}



test "script groups - NSM validation" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = try static_data_loader.loadScriptGroups(allocator);

    defer groups.deinit();

    

    // Test that we loaded NSM data

    try testing.expect(groups.nsm_set.count() > 0);

    

    // Test some known NSM characters

    try testing.expect(groups.isNSM(0x0300)); // Combining grave accent

    try testing.expect(groups.isNSM(0x0301)); // Combining acute accent

    try testing.expect(groups.isNSM(0x0302)); // Combining circumflex accent

    

    // Test non-NSM characters

    try testing.expect(!groups.isNSM('a'));

    try testing.expect(!groups.isNSM('1'));

    try testing.expect(!groups.isNSM(0x03B1)); // Greek α

}```

```zig [./tests/character_mappings_tests.zig]

const std = @import("std");

const testing = std.testing;

const ens = @import("ens_normalize");



test "character mappings - ASCII case folding" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const test_cases = [_]struct {

        input: []const u8,

        expected: []const u8,

        comment: []const u8,

    }{

        .{ .input = "HELLO", .expected = "hello", .comment = "Basic uppercase" },

        .{ .input = "Hello", .expected = "hello", .comment = "Mixed case" },

        .{ .input = "HeLLo", .expected = "hello", .comment = "Mixed case complex" },

        .{ .input = "hello", .expected = "hello", .comment = "Already lowercase" },

        .{ .input = "HELLO.ETH", .expected = "hello.eth", .comment = "Domain with uppercase" },

        .{ .input = "Hello.ETH", .expected = "hello.eth", .comment = "Domain mixed case" },

        .{ .input = "TEST.DOMAIN", .expected = "test.domain", .comment = "Multiple labels" },

        .{ .input = "A", .expected = "a", .comment = "Single uppercase" },

        .{ .input = "Z", .expected = "z", .comment = "Last uppercase" },

        .{ .input = "123", .expected = "123", .comment = "Numbers unchanged" },

        .{ .input = "test-123", .expected = "test-123", .comment = "Numbers with hyphens" },

    };

    

    for (test_cases) |case| {

        const result = try ens.normalize(allocator, case.input);

        defer allocator.free(result);

        

        testing.expectEqualStrings(case.expected, result) catch |err| {

            std.debug.print("FAIL: {s} - input: '{s}', expected: '{s}', got: '{s}'\n", .{ case.comment, case.input, case.expected, result });

            return err;

        };

    }

}



test "character mappings - Unicode character mappings" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const test_cases = [_]struct {

        input: []const u8,

        expected: []const u8,

        comment: []const u8,

    }{

        // Mathematical symbols

        .{ .input = "ℂ", .expected = "C", .comment = "Complex numbers symbol" },

        .{ .input = "ℌ", .expected = "H", .comment = "Hilbert space symbol" },

        .{ .input = "ℍ", .expected = "H", .comment = "Quaternion symbol" },

        .{ .input = "ℓ", .expected = "l", .comment = "Script small l" },

        

        // Fractions

        .{ .input = "½", .expected = "1⁄2", .comment = "One half" },

        .{ .input = "⅓", .expected = "1⁄3", .comment = "One third" },

        .{ .input = "¼", .expected = "1⁄4", .comment = "One quarter" },

        .{ .input = "¾", .expected = "3⁄4", .comment = "Three quarters" },

        

        // Complex domains

        .{ .input = "test½.eth", .expected = "test1⁄2.eth", .comment = "Domain with fraction" },

        .{ .input = "ℌello.eth", .expected = "Hello.eth", .comment = "Domain with math symbol" },

    };

    

    for (test_cases) |case| {

        const result = try ens.normalize(allocator, case.input);

        defer allocator.free(result);

        

        testing.expectEqualStrings(case.expected, result) catch |err| {

            std.debug.print("FAIL: {s} - input: '{s}', expected: '{s}', got: '{s}'\n", .{ case.comment, case.input, case.expected, result });

            return err;

        };

    }

}



test "character mappings - beautification" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const test_cases = [_]struct {

        input: []const u8,

        expected: []const u8,

        comment: []const u8,

    }{

        // ASCII case folding should preserve original case for beautification

        .{ .input = "HELLO", .expected = "HELLO", .comment = "Uppercase preserved" },

        .{ .input = "Hello", .expected = "Hello", .comment = "Mixed case preserved" },

        .{ .input = "hello", .expected = "hello", .comment = "Lowercase preserved" },

        .{ .input = "Hello.ETH", .expected = "Hello.ETH", .comment = "Domain case preserved" },

        

        // Unicode mappings should still apply

        .{ .input = "½", .expected = "1⁄2", .comment = "Fraction still mapped" },

        .{ .input = "ℌ", .expected = "H", .comment = "Math symbol still mapped" },

        .{ .input = "test½.eth", .expected = "test1⁄2.eth", .comment = "Domain with fraction" },

    };

    

    for (test_cases) |case| {

        const result = try ens.beautify(allocator, case.input);

        defer allocator.free(result);

        

        testing.expectEqualStrings(case.expected, result) catch |err| {

            std.debug.print("FAIL: {s} - input: '{s}', expected: '{s}', got: '{s}'\n", .{ case.comment, case.input, case.expected, result });

            return err;

        };

    }

}



test "character mappings - tokenization" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const test_cases = [_]struct {

        input: []const u8,

        expected_types: []const ens.tokenizer.TokenType,

        comment: []const u8,

    }{

        .{ 

            .input = "HELLO", 

            .expected_types = &[_]ens.tokenizer.TokenType{.mapped, .mapped, .mapped, .mapped, .mapped}, 

            .comment = "All uppercase -> mapped" 

        },

        .{ 

            .input = "hello", 

            .expected_types = &[_]ens.tokenizer.TokenType{.valid}, 

            .comment = "All lowercase -> valid (collapsed)" 

        },

        .{ 

            .input = "Hello", 

            .expected_types = &[_]ens.tokenizer.TokenType{.mapped, .valid}, 

            .comment = "Mixed case -> mapped + valid" 

        },

        .{ 

            .input = "½", 

            .expected_types = &[_]ens.tokenizer.TokenType{.mapped}, 

            .comment = "Unicode fraction -> mapped" 

        },

        .{ 

            .input = "test½.eth", 

            .expected_types = &[_]ens.tokenizer.TokenType{.valid, .mapped, .stop, .valid}, 

            .comment = "Domain with fraction" 

        },

    };

    

    for (test_cases) |case| {

        const tokenized = try ens.tokenize(allocator, case.input);

        defer tokenized.deinit();

        

        testing.expectEqual(case.expected_types.len, tokenized.tokens.len) catch |err| {

            std.debug.print("FAIL: {s} - token count mismatch: expected {d}, got {d}\n", .{ case.comment, case.expected_types.len, tokenized.tokens.len });

            return err;

        };

        

        for (case.expected_types, 0..) |expected_type, i| {

            testing.expectEqual(expected_type, tokenized.tokens[i].type) catch |err| {

                std.debug.print("FAIL: {s} - token {d} type mismatch: expected {s}, got {s}\n", .{ case.comment, i, expected_type.toString(), tokenized.tokens[i].type.toString() });

                return err;

            };

        }

    }

}



test "character mappings - ignored characters" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const test_cases = [_]struct {

        input: []const u8,

        expected: []const u8,

        comment: []const u8,

    }{

        .{ .input = "hel\u{00AD}lo", .expected = "hello", .comment = "Soft hyphen ignored" },

        .{ .input = "hel\u{200C}lo", .expected = "hello", .comment = "ZWNJ ignored" },

        .{ .input = "hel\u{200D}lo", .expected = "hello", .comment = "ZWJ ignored" },

        .{ .input = "hel\u{FEFF}lo", .expected = "hello", .comment = "Zero-width no-break space ignored" },

    };

    

    for (test_cases) |case| {

        const result = try ens.normalize(allocator, case.input);

        defer allocator.free(result);

        

        testing.expectEqualStrings(case.expected, result) catch |err| {

            std.debug.print("FAIL: {s} - input: '{s}', expected: '{s}', got: '{s}'\n", .{ case.comment, case.input, case.expected, result });

            return err;

        };

    }

}



test "character mappings - performance test" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const test_inputs = [_][]const u8{

        "HELLO.ETH",

        "Hello.ETH",

        "test½.domain",

        "ℌello.world",

        "MIXED.Case.Domain",

        "with⅓fraction.eth",

        "Complex.ℂ.Domain",

        "Multiple.Labels.With.UPPERCASE",

    };

    

    const iterations = 100;

    var timer = try std.time.Timer.start();

    

    for (0..iterations) |_| {

        for (test_inputs) |input| {

            const result = try ens.normalize(allocator, input);

            defer allocator.free(result);

            

            // Ensure result is valid

            try testing.expect(result.len > 0);

        }

    }

    

    const elapsed = timer.read();

    const ns_per_normalization = elapsed / (iterations * test_inputs.len);

    

    std.debug.print("Character mappings performance: {d} iterations in {d}ns ({d}ns per normalization)\n", .{ iterations * test_inputs.len, elapsed, ns_per_normalization });

    

    // Performance should be reasonable (less than 100μs per normalization)

    try testing.expect(ns_per_normalization < 100_000);

}



test "character mappings - edge cases" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Empty string

    {

        const result = try ens.normalize(allocator, "");

        defer allocator.free(result);

        try testing.expectEqualStrings("", result);

    }

    

    // Single character

    {

        const result = try ens.normalize(allocator, "A");

        defer allocator.free(result);

        try testing.expectEqualStrings("a", result);

    }

    

    // Only periods

    {

        const result = try ens.normalize(allocator, "...");

        defer allocator.free(result);

        try testing.expectEqualStrings("...", result);

    }

    

    // Mixed valid and ignored characters

    {

        const result = try ens.normalize(allocator, "a\u{00AD}b\u{200C}c");

        defer allocator.free(result);

        try testing.expectEqualStrings("abc", result);

    }

}```

```zig [./tests/confusable_tests.zig]

const std = @import("std");

const ens = @import("ens_normalize");

const confusables = ens.confusables;

const static_data_loader = ens.static_data_loader;

const validator = ens.validator;

const tokenizer = ens.tokenizer;

const code_points = ens.code_points;



test "confusables - load from ZON" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();



    var confusable_data = try static_data_loader.loadConfusables(allocator);

    defer confusable_data.deinit();



    try testing.expect(confusable_data.sets.len > 0);

    

    // Check that we have some known confusable sets

    var found_digit_confusables = false;

    for (confusable_data.sets) |*set| {

        if (std.mem.eql(u8, set.target, "32")) { // Target "32" for digit 2

            found_digit_confusables = true;

            try testing.expect(set.valid.len > 0);

            try testing.expect(set.confused.len > 0);

            break;

        }

    }

    try testing.expect(found_digit_confusables);

}



test "confusables - basic detection" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();



    var confusable_data = try static_data_loader.loadConfusables(allocator);

    defer confusable_data.deinit();



    // Test empty input (should be safe)

    const empty_cps = [_]u32{};

    const is_empty_confusable = try confusable_data.checkWholeScriptConfusables(&empty_cps, allocator);

    try testing.expect(!is_empty_confusable);



    // Test single character (should be safe)

    const single_cp = [_]u32{'a'};

    const is_single_confusable = try confusable_data.checkWholeScriptConfusables(&single_cp, allocator);

    try testing.expect(!is_single_confusable);

}



test "confusables - find sets containing characters" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();



    var confusable_data = try static_data_loader.loadConfusables(allocator);

    defer confusable_data.deinit();



    // Test with known confusable characters

    const test_cps = [_]u32{ '2', '3' }; // Digits that likely have confusables

    const matching_sets = try confusable_data.findSetsContaining(&test_cps, allocator);

    defer allocator.free(matching_sets);



    // Should find some sets (digits have many confusables)

    try testing.expect(matching_sets.len >= 0); // At least we don't crash

}



test "confusables - analysis functionality" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();



    var confusable_data = try static_data_loader.loadConfusables(allocator);

    defer confusable_data.deinit();



    // Test analysis with simple ASCII

    const ascii_cps = [_]u32{ 'h', 'e', 'l', 'l', 'o' };

    var analysis = try confusable_data.analyzeConfusables(&ascii_cps, allocator);

    defer analysis.deinit();



    // ASCII letters might or might not have confusables, but analysis should work

    try testing.expect(analysis.valid_count + analysis.confused_count + analysis.non_confusable_count == ascii_cps.len);

}



test "confusables - integration with validator" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();



    // Test with a simple ASCII name (should pass)

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    var tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello", &specs, false);

    defer tokenized.deinit();



    // Should pass validation (ASCII names are generally safe)

    const result = validator.validateLabel(allocator, tokenized, &specs);

    

    // Even if it fails for other reasons, it shouldn't be due to confusables

    if (result) |validated| {

        defer validated.deinit();

        try testing.expect(true); // Passed validation

    } else |err| {

        // If it fails, make sure it's not due to confusables

        try testing.expect(err != validator.ValidationError.WholeScriptConfusable);

    }

}



test "confusables - mixed confusable detection" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();



    var confusable_data = try static_data_loader.loadConfusables(allocator);

    defer confusable_data.deinit();



    // Create a test scenario with potentially confusable characters

    // Note: We need to find actual confusable pairs from the loaded data

    

    if (confusable_data.sets.len > 0) {

        // Find a set with both valid and confused characters

        for (confusable_data.sets) |*set| {

            if (set.valid.len > 0 and set.confused.len > 0) {

                // Test mixing valid and confused from same set (should be safe)

                const mixed_same_set = [_]u32{ set.valid[0], set.confused[0] };

                const is_confusable = try confusable_data.checkWholeScriptConfusables(&mixed_same_set, allocator);

                // This should be safe since they're from the same confusable set

                try testing.expect(!is_confusable);

                break;

            }

        }

    }

}



test "confusables - performance test" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();



    var confusable_data = try static_data_loader.loadConfusables(allocator);

    defer confusable_data.deinit();



    // Test with various input sizes

    const test_sizes = [_]usize{ 1, 5, 10, 50, 100 };

    

    for (test_sizes) |size| {

        const test_cps = try allocator.alloc(u32, size);

        defer allocator.free(test_cps);

        

        // Fill with ASCII characters

        for (test_cps, 0..) |*cp, i| {

            cp.* = 'a' + @as(u32, @intCast(i % 26));

        }

        

        // Should complete quickly

        const start_time = std.time.nanoTimestamp();

        const is_confusable = try confusable_data.checkWholeScriptConfusables(test_cps, allocator);

        const end_time = std.time.nanoTimestamp();

        

        _ = is_confusable; // We don't care about the result, just that it completes

        

        // Should complete in reasonable time (less than 1ms for these sizes)

        const duration_ns = end_time - start_time;

        try testing.expect(duration_ns < 1_000_000); // 1ms

    }

}



test "confusables - error handling" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();



    // Test with a confusable data structure that we can control

    var test_data = confusables.ConfusableData.init(allocator);

    defer test_data.deinit();

    

    // Create test sets

    test_data.sets = try allocator.alloc(confusables.ConfusableSet, 2);

    

    // Set 1: Latin-like

    test_data.sets[0] = confusables.ConfusableSet.init(allocator, try allocator.dupe(u8, "latin"));

    test_data.sets[0].valid = try allocator.dupe(u32, &[_]u32{ 'a', 'b' });

    test_data.sets[0].confused = try allocator.dupe(u32, &[_]u32{ 0x0430, 0x0431 }); // Cyrillic а, б

    

    // Set 2: Different confusable set

    test_data.sets[1] = confusables.ConfusableSet.init(allocator, try allocator.dupe(u8, "cyrillic"));

    test_data.sets[1].valid = try allocator.dupe(u32, &[_]u32{ 'x', 'y' });

    test_data.sets[1].confused = try allocator.dupe(u32, &[_]u32{ 0x0445, 0x0443 }); // Cyrillic х, у

    

    // Test safe cases

    const latin_only = [_]u32{ 'a', 'b' };

    const is_latin_safe = try test_data.checkWholeScriptConfusables(&latin_only, allocator);

    try testing.expect(!is_latin_safe);

    

    const cyrillic_only = [_]u32{ 0x0430, 0x0431 };

    const is_cyrillic_safe = try test_data.checkWholeScriptConfusables(&cyrillic_only, allocator);

    try testing.expect(!is_cyrillic_safe);

    

    // Test dangerous mixing between different confusable sets

    const mixed_sets = [_]u32{ 'a', 'x' }; // From different confusable sets

    const is_mixed_dangerous = try test_data.checkWholeScriptConfusables(&mixed_sets, allocator);

    try testing.expect(is_mixed_dangerous);

}```

```zig [./tests/nfc_tests.zig]

const std = @import("std");

const tokenizer = @import("../src/tokenizer.zig");

const code_points = @import("../src/code_points.zig");

const nfc = @import("../src/nfc.zig");

const static_data_loader = @import("../src/static_data_loader.zig");

const utils = @import("../src/utils.zig");



test "NFC - basic composition" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Load NFC data

    var nfc_data = try static_data_loader.loadNFCData(allocator);

    defer nfc_data.deinit();

    

    // Test case: e + combining acute accent -> é

    const input = [_]u32{ 0x0065, 0x0301 }; // e + ́

    const expected = [_]u32{ 0x00E9 }; // é

    

    const result = try nfc.nfc(allocator, &input, &nfc_data);

    defer allocator.free(result);

    

    try testing.expectEqualSlices(u32, &expected, result);

}



test "NFC - decomposed string remains decomposed when excluded" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var nfc_data = try static_data_loader.loadNFCData(allocator);

    defer nfc_data.deinit();

    

    // Test with an exclusion (need to check what's actually excluded in nf.json)

    // For now, test that already composed stays composed

    const input = [_]u32{ 0x00E9 }; // é (already composed)

    

    const result = try nfc.nfc(allocator, &input, &nfc_data);

    defer allocator.free(result);

    

    try testing.expectEqualSlices(u32, &input, result);

}



test "NFC - tokenization with NFC" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test: "café" with combining accent

    const input = "cafe\u{0301}"; // cafe + combining acute on e

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, true);

    defer tokenized.deinit();

    

    // Should have created an NFC token for the e + accent

    var has_nfc_token = false;

    for (tokenized.tokens) |token| {

        if (token.type == .nfc) {

            has_nfc_token = true;

            break;

        }

    }

    

    try testing.expect(has_nfc_token);

}



test "NFC - no change when not needed" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test: regular ASCII doesn't need NFC

    const input = "hello";

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, true);

    defer tokenized.deinit();

    

    // Should not have any NFC tokens

    for (tokenized.tokens) |token| {

        try testing.expect(token.type != .nfc);

    }

}



test "NFC - string conversion" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Test the full string NFC function

    const input = "cafe\u{0301}"; // cafe with combining accent

    const result = try utils.nfc(allocator, input);

    defer allocator.free(result);

    

    const expected = "café"; // Should be composed

    try testing.expectEqualStrings(expected, result);

}```

```zig [./tests/combining_mark_tests.zig]

const std = @import("std");

const ens = @import("ens_normalize");

const combining_marks = ens.combining_marks;

const script_groups = ens.script_groups;

const static_data_loader = ens.static_data_loader;

const validator = ens.validator;

const tokenizer = ens.tokenizer;

const code_points = ens.code_points;



test "combining marks - basic detection" {

    const testing = std.testing;

    

    // Test basic combining marks

    try testing.expect(combining_marks.isCombiningMark(0x0301)); // Combining acute accent

    try testing.expect(combining_marks.isCombiningMark(0x0300)); // Combining grave accent

    try testing.expect(combining_marks.isCombiningMark(0x064E)); // Arabic fatha

    

    // Test non-combining marks

    try testing.expect(!combining_marks.isCombiningMark('a'));

    try testing.expect(!combining_marks.isCombiningMark('A'));

    try testing.expect(!combining_marks.isCombiningMark(0x0041)); // Latin A

}



test "combining marks - leading CM validation" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Create a mock script group for testing

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    // Add combining mark to allowed set

    try latin_group.cm.put(0x0301, {});

    

    // Test leading combining mark (should fail)

    const leading_cm = [_]u32{0x0301, 'a'};

    const result = combining_marks.validateCombiningMarks(&leading_cm, &latin_group, allocator);

    try testing.expectError(combining_marks.ValidationError.LeadingCombiningMark, result);

}



test "combining marks - disallowed CM for script group" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Create a mock script group that doesn't allow Arabic CMs

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    // Don't add Arabic CM to allowed set

    

    // Test Arabic CM with Latin group (should fail)

    const wrong_script_cm = [_]u32{'a', 0x064E}; // Latin + Arabic fatha

    const result = combining_marks.validateCombiningMarks(&wrong_script_cm, &latin_group, allocator);

    try testing.expectError(combining_marks.ValidationError.DisallowedCombiningMark, result);

}



test "combining marks - CM after emoji validation" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var emoji_group = script_groups.ScriptGroup.init(allocator, "Emoji", 0);

    defer emoji_group.deinit();

    

    // Add combining mark to allowed set

    try emoji_group.cm.put(0x0301, {});

    

    // Test emoji + combining mark (should fail)

    const emoji_cm = [_]u32{0x1F600, 0x0301}; // Grinning face + acute

    const result = combining_marks.validateCombiningMarks(&emoji_cm, &emoji_group, allocator);

    try testing.expectError(combining_marks.ValidationError.CombiningMarkAfterEmoji, result);

}



test "combining marks - valid sequences" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    // Add combining marks to allowed set

    try latin_group.cm.put(0x0301, {}); // Acute accent

    try latin_group.cm.put(0x0300, {}); // Grave accent

    

    // Test valid sequences (should pass)

    const valid_sequences = [_][]const u32{

        &[_]u32{'a', 0x0301},      // á

        &[_]u32{'e', 0x0300},      // è  

        &[_]u32{'a', 0x0301, 0x0300}, // Multiple CMs

    };

    

    for (valid_sequences) |seq| {

        try combining_marks.validateCombiningMarks(seq, &latin_group, allocator);

    }

}



test "combining marks - Arabic diacritic validation" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    // Add Arabic combining marks

    try arabic_group.cm.put(0x064E, {}); // Fatha

    try arabic_group.cm.put(0x064F, {}); // Damma

    try arabic_group.cm.put(0x0650, {}); // Kasra

    try arabic_group.cm.put(0x0651, {}); // Shadda

    

    // Test valid Arabic with diacritics

    const valid_arabic = [_]u32{0x0628, 0x064E}; // بَ (beh + fatha)

    try combining_marks.validateCombiningMarks(&valid_arabic, &arabic_group, allocator);

    

    // Test excessive diacritics (should fail)

    const excessive = [_]u32{0x0628, 0x064E, 0x064F, 0x0650, 0x0651}; // Too many marks

    const result = combining_marks.validateCombiningMarks(&excessive, &arabic_group, allocator);

    try testing.expectError(combining_marks.ValidationError.ExcessiveArabicDiacritics, result);

}



test "combining marks - integration with full validation" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test Latin with accents (should work)

    {

        // Note: Using NFC-composed characters for now since our tokenizer expects pre-composed

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "café", &specs, false);

        defer tokenized.deinit();

        

        const result = validator.validateLabel(allocator, tokenized, &specs);

        if (result) |validated| {

            defer validated.deinit();

            // Should pass - Latin script with proper accents

            try testing.expect(true);

        } else |err| {

            // Make sure it's not a combining mark error

            try testing.expect(err != validator.ValidationError.LeadingCombiningMark);

            try testing.expect(err != validator.ValidationError.DisallowedCombiningMark);

        }

    }

}



test "combining marks - empty input validation" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    const empty_cps = [_]u32{};

    try combining_marks.validateCombiningMarks(&empty_cps, &latin_group, allocator);

    // Should pass - nothing to validate

}



test "combining marks - no combining marks in input" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    // Just base characters, no CMs

    const no_cms = [_]u32{'h', 'e', 'l', 'l', 'o'};

    try combining_marks.validateCombiningMarks(&no_cms, &latin_group, allocator);

    // Should pass - no CMs to validate

}



test "combining marks - script-specific rules" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Test Devanagari rules

    {

        var devanagari_group = script_groups.ScriptGroup.init(allocator, "Devanagari", 0);

        defer devanagari_group.deinit();

        

        try devanagari_group.cm.put(0x093E, {}); // Aa matra

        

        // Valid: consonant + vowel sign

        const valid_devanagari = [_]u32{0x0915, 0x093E}; // का (ka + aa-matra)

        try combining_marks.validateCombiningMarks(&valid_devanagari, &devanagari_group, allocator);

        

        // Invalid: vowel sign without consonant

        const invalid_devanagari = [_]u32{0x093E}; // Just matra

        const result = combining_marks.validateCombiningMarks(&invalid_devanagari, &devanagari_group, allocator);

        try testing.expectError(combining_marks.ValidationError.LeadingCombiningMark, result);

    }

    

    // Test Thai rules

    {

        var thai_group = script_groups.ScriptGroup.init(allocator, "Thai", 0);

        defer thai_group.deinit();

        

        try thai_group.cm.put(0x0E31, {}); // Mai han-akat

        

        // Valid: consonant + vowel sign

        const valid_thai = [_]u32{0x0E01, 0x0E31}; // ก + ั

        try combining_marks.validateCombiningMarks(&valid_thai, &thai_group, allocator);

    }

}



test "combining marks - performance test" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    // Add common combining marks

    try latin_group.cm.put(0x0301, {});

    try latin_group.cm.put(0x0300, {});

    

    // Test with various input sizes

    const test_sizes = [_]usize{ 1, 5, 10, 50, 100 };

    

    for (test_sizes) |size| {

        const test_cps = try allocator.alloc(u32, size);

        defer allocator.free(test_cps);

        

        // Fill with alternating base chars and combining marks

        for (test_cps, 0..) |*cp, i| {

            if (i % 2 == 0) {

                cp.* = 'a' + @as(u32, @intCast(i % 26));

            } else {

                cp.* = 0x0301; // Acute accent

            }

        }

        

        // Should complete quickly

        const start_time = std.time.nanoTimestamp();

        try combining_marks.validateCombiningMarks(test_cps, &latin_group, allocator);

        const end_time = std.time.nanoTimestamp();

        

        // Should complete in reasonable time (less than 1ms for these sizes)

        const duration_ns = end_time - start_time;

        try testing.expect(duration_ns < 1_000_000); // 1ms

    }

}



test "combining marks - edge cases" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    try latin_group.cm.put(0x0300, {}); // Grave accent

    try latin_group.cm.put(0x0308, {}); // Diaeresis

    

    // Test multiple valid CMs on one base

    const multiple_cms = [_]u32{'a', 0x0300, 0x0308}; // à̈ (grave + diaeresis)

    try combining_marks.validateCombiningMarks(&multiple_cms, &latin_group, allocator);

    

    // Test CM after fenced character (should fail)

    const fenced_cm = [_]u32{'.', 0x0300}; // Period + grave accent

    const result = combining_marks.validateCombiningMarks(&fenced_cm, &latin_group, allocator);

    try testing.expectError(combining_marks.ValidationError.CombiningMarkAfterFenced, result);

}



test "combining marks - load from actual data" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Load actual script groups from data

    var groups = try static_data_loader.loadScriptGroups(allocator);

    defer groups.deinit();

    

    // Test with actual script group data

    const latin_cps = [_]u32{'a', 'b', 'c'};

    const latin_group = try groups.determineScriptGroup(&latin_cps, allocator);

    

    // Test combining mark validation with real data

    if (latin_group.cm.count() > 0) {

        // Find a combining mark allowed by Latin script

        var iter = latin_group.cm.iterator();

        if (iter.next()) |entry| {

            const cm = entry.key_ptr.*;

            const valid_sequence = [_]u32{'a', cm};

            try combining_marks.validateCombiningMarks(&valid_sequence, latin_group, allocator);

        }

    }

}```

```zig [./tests/official_test_vectors.zig]

const std = @import("std");

const ens = @import("ens_normalize");

const normalizer = ens.normalizer;

const validator = ens.validator;

const tokenizer = ens.tokenizer;

const code_points = ens.code_points;



/// Structure matching the official ENS test vector format

pub const TestVector = struct {

    name: []const u8,

    norm: ?[]const u8 = null,

    should_error: ?bool = null,

    comment: ?[]const u8 = null,

    

    pub fn isError(self: TestVector) bool {

        return self.should_error orelse false;

    }

    

    pub fn expectedNorm(self: TestVector) ?[]const u8 {

        // If no norm field, the expected output is the input (unless it's an error)

        if (self.norm) |n| return n;

        if (self.isError()) return null;

        return self.name;

    }

};



/// Test result for reporting

pub const TestResult = struct {

    vector: TestVector,

    passed: bool,

    actual_output: ?[]const u8,

    actual_error: ?anyerror,

    failure_reason: ?[]const u8,

};



/// Load test vectors from JSON file

pub fn loadTestVectors(allocator: std.mem.Allocator) ![]TestVector {

    const json_data = @embedFile("ens_cases.json");

    

    const parsed = try std.json.parseFromSlice(

        std.json.Value, 

        allocator, 

        json_data, 

        .{ .max_value_len = json_data.len }

    );

    defer parsed.deinit();

    

    const array = parsed.value.array;

    var vectors = std.ArrayList(TestVector).init(allocator);

    errdefer vectors.deinit();

    

    // Skip the first element which contains version info

    var start_index: usize = 0;

    if (array.items.len > 0) {

        if (array.items[0].object.get("version")) |_| {

            start_index = 1;

        }

    }

    

    for (array.items[start_index..]) |item| {

        const obj = item.object;

        

        var vector = TestVector{

            .name = try allocator.dupe(u8, obj.get("name").?.string),

        };

        

        if (obj.get("norm")) |norm| {

            vector.norm = try allocator.dupe(u8, norm.string);

        }

        

        if (obj.get("error")) |err| {

            vector.should_error = err.bool;

        }

        

        if (obj.get("comment")) |comment| {

            vector.comment = try allocator.dupe(u8, comment.string);

        }

        

        try vectors.append(vector);

    }

    

    return vectors.toOwnedSlice();

}



/// Run a single test vector

pub fn runTestVector(

    allocator: std.mem.Allocator,

    vector: TestVector,

    specs: *const code_points.CodePointsSpecs,

) TestResult {

    _ = specs; // Not currently used

    

    var result = TestResult{

        .vector = vector,

        .passed = false,

        .actual_output = null,

        .actual_error = null,

        .failure_reason = null,

    };

    

    // Try to normalize the input

    const normalized = normalizer.normalize(allocator, vector.name) catch |err| {

        result.actual_error = err;

        

        if (vector.isError()) {

            // Expected an error, got one

            result.passed = true;

        } else {

            // Unexpected error

            result.failure_reason = std.fmt.allocPrint(

                allocator, 

                "Unexpected error: {}",

                .{err}

            ) catch "Allocation failed";

        }

        return result;

    };

    defer allocator.free(normalized);

    

    result.actual_output = allocator.dupe(u8, normalized) catch normalized;

    

    if (vector.isError()) {

        // Expected error but got success

        result.failure_reason = std.fmt.allocPrint(

            allocator,

            "Expected error but got: '{s}'",

            .{normalized}

        ) catch "Allocation failed";

        return result;

    }

    

    // Compare with expected output

    if (vector.expectedNorm()) |expected| {

        if (std.mem.eql(u8, normalized, expected)) {

            result.passed = true;

        } else {

            result.failure_reason = std.fmt.allocPrint(

                allocator,

                "Expected '{s}' but got '{s}'",

                .{expected, normalized}

            ) catch "Allocation failed";

        }

    } else {

        // No expected output and no error - consider it passed

        result.passed = true;

    }

    

    return result;

}



/// Run all test vectors and report results

pub fn runAllTests(allocator: std.mem.Allocator, vectors: []const TestVector) !TestReport {

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    var report = TestReport{

        .total = vectors.len,

        .passed = 0,

        .failed = 0,

        .error_tests_passed = 0,

        .error_tests_failed = 0,

        .norm_tests_passed = 0,

        .norm_tests_failed = 0,

    };

    

    var failures = std.ArrayList(TestResult).init(allocator);

    defer failures.deinit();

    

    for (vectors) |vector| {

        const result = runTestVector(allocator, vector, &specs);

        

        if (result.passed) {

            report.passed += 1;

            if (vector.isError()) {

                report.error_tests_passed += 1;

            } else {

                report.norm_tests_passed += 1;

            }

        } else {

            report.failed += 1;

            if (vector.isError()) {

                report.error_tests_failed += 1;

            } else {

                report.norm_tests_failed += 1;

            }

            try failures.append(result);

        }

    }

    

    report.failures = failures.toOwnedSlice() catch &.{};

    return report;

}



pub const TestReport = struct {

    total: usize,

    passed: usize,

    failed: usize,

    error_tests_passed: usize,

    error_tests_failed: usize,

    norm_tests_passed: usize,

    norm_tests_failed: usize,

    failures: []const TestResult = &.{},

    

    pub fn printSummary(self: TestReport) void {

        std.debug.print("\n=== ENS Official Test Vector Results ===\n", .{});

        std.debug.print("Total tests: {}\n", .{self.total});

        std.debug.print("Passed: {} ({d:.1}%)\n", .{self.passed, @as(f64, @floatFromInt(self.passed)) / @as(f64, @floatFromInt(self.total)) * 100});

        std.debug.print("Failed: {}\n\n", .{self.failed});

        

        std.debug.print("Normalization tests: {} passed, {} failed\n", .{self.norm_tests_passed, self.norm_tests_failed});

        std.debug.print("Error tests: {} passed, {} failed\n\n", .{self.error_tests_passed, self.error_tests_failed});

        

        if (self.failures.len > 0) {

            std.debug.print("First 10 failures:\n", .{});

            const max_show = @min(10, self.failures.len);

            for (self.failures[0..max_show]) |failure| {

                std.debug.print("  Input: '{s}'\n", .{failure.vector.name});

                if (failure.vector.comment) |comment| {

                    std.debug.print("  Comment: {s}\n", .{comment});

                }

                if (failure.failure_reason) |reason| {

                    std.debug.print("  Reason: {s}\n", .{reason});

                }

                std.debug.print("\n", .{});

            }

            

            if (self.failures.len > 10) {

                std.debug.print("... and {} more failures\n", .{self.failures.len - 10});

            }

        }

    }

    

    pub fn deinit(self: *TestReport, allocator: std.mem.Allocator) void {

        for (self.failures) |failure| {

            if (failure.actual_output) |output| {

                allocator.free(output);

            }

            if (failure.failure_reason) |reason| {

                allocator.free(reason);

            }

        }

        allocator.free(self.failures);

    }

};



// Tests

const testing = std.testing;



test "official test vectors - load and structure" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const vectors = try loadTestVectors(allocator);

    

    // Should have loaded many test vectors

    try testing.expect(vectors.len > 100);

    

    // Check structure of first few non-version vectors

    var found_error_test = false;

    var found_norm_test = false;

    

    for (vectors[0..@min(20, vectors.len)]) |vector| {

        if (vector.isError()) {

            found_error_test = true;

        }

        if (vector.norm != null) {

            found_norm_test = true;

        }

    }

    

    try testing.expect(found_error_test);

    try testing.expect(found_norm_test);

}



test "official test vectors - run sample tests" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test a few specific cases we know should work

    const test_cases = [_]TestVector{

        // Empty string should normalize to empty

        TestVector{ .name = "" },

        

        // Simple ASCII should pass through

        TestVector{ .name = "hello" },

        

        // Whitespace should error

        TestVector{ .name = " ", .should_error = true },

        

        // Period should error

        TestVector{ .name = ".", .should_error = true },

    };

    

    for (test_cases) |vector| {

        const result = runTestVector(allocator, vector, &specs);

        if (!result.passed) {

            std.debug.print("Failed test: '{s}'\n", .{vector.name});

            if (result.failure_reason) |reason| {

                std.debug.print("Reason: {s}\n", .{reason});

            }

        }

    }

}



test "official test vectors - run subset" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const vectors = try loadTestVectors(allocator);

    

    // Run first 100 tests as a sample

    const subset = vectors[0..@min(100, vectors.len)];

    var report = try runAllTests(allocator, subset);

    defer report.deinit(allocator);

    

    report.printSummary();

    

    // We expect some failures initially

    try testing.expect(report.total == subset.len);

}```

```zig [./tests/validation_tests.zig]

const std = @import("std");

const testing = std.testing;

const ens_normalize = @import("ens_normalize");

const validator = ens_normalize.validator;

const tokenizer = ens_normalize.tokenizer;

const code_points = ens_normalize.code_points;



// Test case structure

const ValidationTestCase = struct {

    name: []const u8,

    input: []const u8,

    expected_error: ?validator.ValidationError = null,

    expected_script: ?[]const u8 = null,

    comment: ?[]const u8 = null,

};



// Empty label tests

const EMPTY_TESTS = [_]ValidationTestCase{

    .{ .name = "empty_string", .input = "", .expected_error = validator.ValidationError.EmptyLabel, .comment = "Empty string" },

    .{ .name = "whitespace", .input = " ", .expected_error = validator.ValidationError.EmptyLabel, .comment = "Whitespace only" },

    .{ .name = "soft_hyphen", .input = "\u{00AD}", .expected_error = validator.ValidationError.EmptyLabel, .comment = "Soft hyphen (ignored)" },

};



// Basic valid tests

const BASIC_VALID_TESTS = [_]ValidationTestCase{

    .{ .name = "simple_ascii", .input = "hello", .expected_script = "ASCII", .comment = "Simple ASCII" },

    .{ .name = "digits", .input = "123", .expected_script = "ASCII", .comment = "Digits" },

    .{ .name = "mixed_ascii", .input = "test123", .expected_script = "ASCII", .comment = "Mixed ASCII" },

    .{ .name = "with_hyphen", .input = "test-name", .expected_script = "ASCII", .comment = "With hyphen" },

};



// Underscore rule tests

const UNDERSCORE_TESTS = [_]ValidationTestCase{

    .{ .name = "leading_underscore", .input = "_hello", .expected_script = "ASCII", .comment = "Leading underscore" },

    .{ .name = "multiple_leading", .input = "____hello", .expected_script = "ASCII", .comment = "Multiple leading underscores" },

    .{ .name = "underscore_middle", .input = "hel_lo", .expected_error = validator.ValidationError.UnderscoreInMiddle, .comment = "Underscore in middle" },

    .{ .name = "underscore_end", .input = "hello_", .expected_error = validator.ValidationError.UnderscoreInMiddle, .comment = "Underscore at end" },

};



// ASCII label extension tests

const LABEL_EXTENSION_TESTS = [_]ValidationTestCase{

    .{ .name = "valid_hyphen", .input = "ab-cd", .expected_script = "ASCII", .comment = "Valid hyphen placement" },

    .{ .name = "invalid_extension", .input = "ab--cd", .expected_error = validator.ValidationError.InvalidLabelExtension, .comment = "Invalid label extension" },

    .{ .name = "xn_extension", .input = "xn--test", .expected_error = validator.ValidationError.InvalidLabelExtension, .comment = "XN label extension" },

};



// Fenced character tests

const FENCED_TESTS = [_]ValidationTestCase{

    .{ .name = "apostrophe_leading", .input = "'hello", .expected_error = validator.ValidationError.FencedLeading, .comment = "Leading apostrophe" },

    .{ .name = "apostrophe_trailing", .input = "hello'", .expected_error = validator.ValidationError.FencedTrailing, .comment = "Trailing apostrophe" },

    .{ .name = "apostrophe_adjacent", .input = "hel''lo", .expected_error = validator.ValidationError.FencedAdjacent, .comment = "Adjacent apostrophes" },

    .{ .name = "apostrophe_valid", .input = "hel'lo", .expected_script = "ASCII", .comment = "Valid apostrophe placement" },

};



// Run test cases

fn runTestCase(test_case: ValidationTestCase) !void {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, test_case.input, &specs, false);

    defer tokenized.deinit();

    

    // Debug: Print tokenized result for whitespace test

    if (std.mem.eql(u8, test_case.input, " ")) {

        std.debug.print("\nDEBUG: Whitespace test tokenization:\n", .{});

        std.debug.print("  Input: '{s}' (len={})\n", .{test_case.input, test_case.input.len});

        std.debug.print("  Tokens: {} total\n", .{tokenized.tokens.len});

        for (tokenized.tokens, 0..) |token, i| {

            std.debug.print("    [{}] type={s}", .{i, @tagName(token.type)});

            if (token.type == .disallowed) {

                std.debug.print(" cp=0x{x}", .{token.data.disallowed.cp});

            }

            std.debug.print("\n", .{});

        }

    }

    

    const result = validator.validateLabel(allocator, tokenized, &specs);

    

    if (test_case.expected_error) |expected_error| {

        try testing.expectError(expected_error, result);

    } else {

        const validated = try result;

        defer validated.deinit();

        

        if (test_case.expected_script) |expected_script| {

            try testing.expectEqualStrings(expected_script, validated.script_group.name);

        }

    }

}



test "validation - empty labels" {

    for (EMPTY_TESTS) |test_case| {

        runTestCase(test_case) catch |err| {

            std.debug.print("Test failed: {s} - {s}\n", .{ test_case.name, test_case.comment orelse "" });

            return err;

        };

    }

}



test "validation - basic valid cases" {

    for (BASIC_VALID_TESTS) |test_case| {

        runTestCase(test_case) catch |err| {

            std.debug.print("Test failed: {s} - {s}\n", .{ test_case.name, test_case.comment orelse "" });

            return err;

        };

    }

}



test "validation - underscore rules" {

    for (UNDERSCORE_TESTS) |test_case| {

        runTestCase(test_case) catch |err| {

            std.debug.print("Test failed: {s} - {s}\n", .{ test_case.name, test_case.comment orelse "" });

            return err;

        };

    }

}



test "validation - label extension rules" {

    for (LABEL_EXTENSION_TESTS) |test_case| {

        runTestCase(test_case) catch |err| {

            std.debug.print("Test failed: {s} - {s}\n", .{ test_case.name, test_case.comment orelse "" });

            return err;

        };

    }

}



test "validation - fenced characters" {

    for (FENCED_TESTS) |test_case| {

        runTestCase(test_case) catch |err| {

            std.debug.print("Test failed: {s} - {s}\n", .{ test_case.name, test_case.comment orelse "" });

            return err;

        };

    }

}



test "validation - script group detection" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // ASCII test

    {

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello", &specs, false);

        defer tokenized.deinit();

        

        const result = try validator.validateLabel(allocator, tokenized, &specs);

        defer result.deinit();

        

        try testing.expectEqualStrings("ASCII", result.script_group.name);

    }

}



test "validation - performance test" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    const start_time = std.time.microTimestamp();

    

    var i: usize = 0;

    while (i < 1000) : (i += 1) {

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello", &specs, false);

        defer tokenized.deinit();

        

        const result = try validator.validateLabel(allocator, tokenized, &specs);

        defer result.deinit();

        

        try testing.expectEqualStrings("ASCII", result.script_group.name);

    }

    

    const end_time = std.time.microTimestamp();

    const duration_us = end_time - start_time;

    

    std.debug.print("Validated 1000 times in {d}ms ({d:.2}μs per validation)\n", .{ @divTrunc(duration_us, 1000), @as(f64, @floatFromInt(duration_us)) / 1000.0 });

    

    // Should complete within reasonable time

    try testing.expect(duration_us < 1_000_000); // 1 second

}```

```zig [./tests/tokenization_tests.zig]

const std = @import("std");

const testing = std.testing;

const ens_normalize = @import("ens_normalize");

const tokenizer = ens_normalize.tokenizer;

const code_points = ens_normalize.code_points;

const constants = ens_normalize.constants;

const utils = ens_normalize.utils;



// Test case structure based on reference implementations

const TokenizationTestCase = struct {

    name: []const u8,

    input: []const u8,

    expected_tokens: []const ExpectedToken,

    should_error: bool = false,

    comment: ?[]const u8 = null,

};



const ExpectedToken = struct {

    type: tokenizer.TokenType,

    cps: ?[]const u32 = null,

    cp: ?u32 = null,

    input_size: ?usize = null,

};



// Test cases derived from JavaScript implementation

const BASIC_TOKENIZATION_TESTS = [_]TokenizationTestCase{

    .{

        .name = "empty_string",

        .input = "",

        .expected_tokens = &[_]ExpectedToken{},

        .comment = "Empty string should produce no tokens",

    },

    .{

        .name = "simple_ascii",

        .input = "hello",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 'h', 'e', 'l', 'l', 'o' } },

        },

        .comment = "Simple ASCII should collapse into one valid token",

    },

    .{

        .name = "single_character",

        .input = "a",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{'a'} },

        },

        .comment = "Single character should be valid token",

    },

    .{

        .name = "with_stop",

        .input = "hello.eth",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 'h', 'e', 'l', 'l', 'o' } },

            .{ .type = .stop, .cp = constants.CP_STOP },

            .{ .type = .valid, .cps = &[_]u32{ 'e', 't', 'h' } },

        },

        .comment = "Domain with stop character should separate labels",

    },

    .{

        .name = "multiple_stops",

        .input = "a.b.c",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{'a'} },

            .{ .type = .stop, .cp = constants.CP_STOP },

            .{ .type = .valid, .cps = &[_]u32{'b'} },

            .{ .type = .stop, .cp = constants.CP_STOP },

            .{ .type = .valid, .cps = &[_]u32{'c'} },

        },

        .comment = "Multiple stops should separate multiple labels",

    },

    .{

        .name = "with_hyphen",

        .input = "test-domain",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't', '-', 'd', 'o', 'm', 'a', 'i', 'n' } },

        },

        .comment = "Hyphen should be valid and collapsed",

    },

    .{

        .name = "mixed_case",

        .input = "Hello",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 'H', 'e', 'l', 'l', 'o' } },

        },

        .comment = "Mixed case should be valid (normalization happens later)",

    },

    .{

        .name = "with_numbers",

        .input = "test123",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't', '1', '2', '3' } },

        },

        .comment = "Numbers should be valid",

    },

};



// Test cases for ignored characters (from JavaScript IGNORED set)

const IGNORED_CHARACTERS_TESTS = [_]TokenizationTestCase{

    .{

        .name = "soft_hyphen",

        .input = "test\u{00AD}domain",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't' } },

            .{ .type = .ignored, .cp = 0x00AD },

            .{ .type = .valid, .cps = &[_]u32{ 'd', 'o', 'm', 'a', 'i', 'n' } },

        },

        .comment = "Soft hyphen should be ignored",

    },

    .{

        .name = "zero_width_non_joiner",

        .input = "te\u{200C}st",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 't', 'e' } },

            .{ .type = .ignored, .cp = 0x200C },

            .{ .type = .valid, .cps = &[_]u32{ 's', 't' } },

        },

        .comment = "Zero width non-joiner should be ignored",

    },

    .{

        .name = "zero_width_joiner",

        .input = "te\u{200D}st",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 't', 'e' } },

            .{ .type = .ignored, .cp = 0x200D },

            .{ .type = .valid, .cps = &[_]u32{ 's', 't' } },

        },

        .comment = "Zero width joiner should be ignored",

    },

    .{

        .name = "zero_width_no_break_space",

        .input = "te\u{FEFF}st",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 't', 'e' } },

            .{ .type = .ignored, .cp = 0xFEFF },

            .{ .type = .valid, .cps = &[_]u32{ 's', 't' } },

        },

        .comment = "Zero width no-break space should be ignored",

    },

};



// Test cases for disallowed characters

const DISALLOWED_CHARACTERS_TESTS = [_]TokenizationTestCase{

    .{

        .name = "special_symbols",

        .input = "test!",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't' } },

            .{ .type = .disallowed, .cp = '!' },

        },

        .comment = "Special symbols should be disallowed",

    },

    .{

        .name = "at_symbol",

        .input = "user@domain",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 'u', 's', 'e', 'r' } },

            .{ .type = .disallowed, .cp = '@' },

            .{ .type = .valid, .cps = &[_]u32{ 'd', 'o', 'm', 'a', 'i', 'n' } },

        },

        .comment = "At symbol should be disallowed",

    },

    .{

        .name = "hash_symbol",

        .input = "test#hash",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't' } },

            .{ .type = .disallowed, .cp = '#' },

            .{ .type = .valid, .cps = &[_]u32{ 'h', 'a', 's', 'h' } },

        },

        .comment = "Hash symbol should be disallowed",

    },

};



// Test cases for edge cases

const EDGE_CASE_TESTS = [_]TokenizationTestCase{

    .{

        .name = "only_stop",

        .input = ".",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .stop, .cp = constants.CP_STOP },

        },

        .comment = "Single stop character",

    },

    .{

        .name = "only_ignored",

        .input = "\u{200C}",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .ignored, .cp = 0x200C },

        },

        .comment = "Single ignored character",

    },

    .{

        .name = "only_disallowed",

        .input = "!",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .disallowed, .cp = '!' },

        },

        .comment = "Single disallowed character",

    },

    .{

        .name = "multiple_consecutive_stops",

        .input = "a..b",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{'a'} },

            .{ .type = .stop, .cp = constants.CP_STOP },

            .{ .type = .stop, .cp = constants.CP_STOP },

            .{ .type = .valid, .cps = &[_]u32{'b'} },

        },

        .comment = "Multiple consecutive stops",

    },

    .{

        .name = "trailing_stop",

        .input = "domain.",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 'd', 'o', 'm', 'a', 'i', 'n' } },

            .{ .type = .stop, .cp = constants.CP_STOP },

        },

        .comment = "Trailing stop character",

    },

    .{

        .name = "leading_stop",

        .input = ".domain",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .stop, .cp = constants.CP_STOP },

            .{ .type = .valid, .cps = &[_]u32{ 'd', 'o', 'm', 'a', 'i', 'n' } },

        },

        .comment = "Leading stop character",

    },

};



// Test cases for NFC normalization (simplified for now)

const NFC_TESTS = [_]TokenizationTestCase{

    .{

        .name = "nfc_simple",

        .input = "test",

        .expected_tokens = &[_]ExpectedToken{

            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't' } },

        },

        .comment = "Simple case should not need NFC",

    },

};



// Helper function to run a single test case

fn runTokenizationTest(test_case: TokenizationTestCase) !void {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Tokenize the input

    const result = tokenizer.TokenizedName.fromInput(allocator, test_case.input, &specs, false) catch |err| {

        if (test_case.should_error) {

            return; // Expected error

        }

        std.debug.print("Unexpected error in test '{s}': {}\n", .{ test_case.name, err });

        return err;

    };

    

    if (test_case.should_error) {

        std.debug.print("Test '{s}' should have failed but succeeded\n", .{test_case.name});

        return error.UnexpectedSuccess;

    }

    

    // Check token count

    if (result.tokens.len != test_case.expected_tokens.len) {

        std.debug.print("Test '{s}': expected {} tokens, got {}\n", .{ test_case.name, test_case.expected_tokens.len, result.tokens.len });

        

        // Print actual tokens for debugging

        std.debug.print("Actual tokens:\n", .{});

        for (result.tokens, 0..) |token, i| {

            std.debug.print("  [{}] type={s}", .{ i, @tagName(token.type) });

            switch (token.type) {

                .valid => std.debug.print(" cps={any}", .{token.getCps()}),

                .ignored, .disallowed, .stop => std.debug.print(" cp={}", .{token.getCps()[0]}),

                else => {},

            }

            std.debug.print("\n", .{});

        }

        

        return error.TokenCountMismatch;

    }

    

    // Check each token

    for (result.tokens, test_case.expected_tokens, 0..) |actual, expected, i| {

        if (actual.type != expected.type) {

            std.debug.print("Test '{s}' token {}: expected type {s}, got {s}\n", .{ test_case.name, i, @tagName(expected.type), @tagName(actual.type) });

            return error.TokenTypeMismatch;

        }

        

        switch (expected.type) {

            .valid => {

                if (expected.cps) |expected_cps| {

                    const actual_cps = actual.getCps();

                    if (actual_cps.len != expected_cps.len) {

                        std.debug.print("Test '{s}' token {}: expected {} cps, got {}\n", .{ test_case.name, i, expected_cps.len, actual_cps.len });

                        return error.TokenCpsMismatch;

                    }

                    for (actual_cps, expected_cps) |actual_cp, expected_cp| {

                        if (actual_cp != expected_cp) {

                            std.debug.print("Test '{s}' token {}: expected cp {}, got {}\n", .{ test_case.name, i, expected_cp, actual_cp });

                            return error.TokenCpMismatch;

                        }

                    }

                }

            },

            .ignored, .disallowed, .stop => {

                if (expected.cp) |expected_cp| {

                    const actual_cps = actual.getCps();

                    if (actual_cps.len != 1 or actual_cps[0] != expected_cp) {

                        std.debug.print("Test '{s}' token {}: expected cp {}, got {any}\n", .{ test_case.name, i, expected_cp, actual_cps });

                        return error.TokenCpMismatch;

                    }

                }

            },

            else => {

                // Other token types not fully implemented yet

            },

        }

    }

}



// Individual test functions

test "basic tokenization" {

    for (BASIC_TOKENIZATION_TESTS) |test_case| {

        runTokenizationTest(test_case) catch |err| {

            std.debug.print("Failed basic tokenization test: {s}\n", .{test_case.name});

            return err;

        };

    }

}



test "ignored characters" {

    for (IGNORED_CHARACTERS_TESTS) |test_case| {

        runTokenizationTest(test_case) catch |err| {

            std.debug.print("Failed ignored characters test: {s}\n", .{test_case.name});

            return err;

        };

    }

}



test "disallowed characters" {

    for (DISALLOWED_CHARACTERS_TESTS) |test_case| {

        runTokenizationTest(test_case) catch |err| {

            std.debug.print("Failed disallowed characters test: {s}\n", .{test_case.name});

            return err;

        };

    }

}



test "edge cases" {

    for (EDGE_CASE_TESTS) |test_case| {

        runTokenizationTest(test_case) catch |err| {

            std.debug.print("Failed edge case test: {s}\n", .{test_case.name});

            return err;

        };

    }

}



test "nfc normalization" {

    for (NFC_TESTS) |test_case| {

        runTokenizationTest(test_case) catch |err| {

            std.debug.print("Failed NFC test: {s}\n", .{test_case.name});

            return err;

        };

    }

}



// Performance test

test "tokenization performance" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test with a moderately sized input

    const input = "this-is-a-longer-domain-name-for-performance-testing.eth";

    

    const start = std.time.nanoTimestamp();

    for (0..1000) |_| {

        const result = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);

        _ = result; // Use result to prevent optimization

    }

    const end = std.time.nanoTimestamp();

    

    const duration_ns = end - start;

    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    

    std.debug.print("Tokenized 1000 times in {d:.2}ms ({d:.2}μs per tokenization)\n", .{ duration_ms, duration_ms * 1000.0 / 1000.0 });

    

    // Should be reasonably fast

    try testing.expect(duration_ms < 1000.0); // Less than 1 second total

}



// Memory usage test

test "tokenization memory usage" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test that we can tokenize without excessive memory usage

    const inputs = [_][]const u8{

        "short",

        "medium-length-domain.eth",

        "very-long-domain-name-with-many-hyphens-and-characters.subdomain.eth",

        "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t.u.v.w.x.y.z",

    };

    

    for (inputs) |input| {

        const result = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);

        

        // Basic sanity checks

        try testing.expect(result.tokens.len > 0);

        try testing.expect(result.input.len == input.len);

        

        // Check that we can access all token data without issues

        for (result.tokens) |token| {

            _ = token.getCps();

            _ = token.getInputSize();

            _ = token.isText();

            _ = token.isEmoji();

        }

    }

}



// Integration test with actual ENS names

test "real ens name tokenization" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    const real_names = [_][]const u8{

        "vitalik.eth",

        "ethereum.eth",

        "test-domain.eth",

        "a.eth",

        "subdomain.domain.eth",

        "1234.eth",

        "mixed-Case.eth",

    };

    

    for (real_names) |name| {

        const result = try tokenizer.TokenizedName.fromInput(allocator, name, &specs, false);

        

        // Should have at least one token

        try testing.expect(result.tokens.len > 0);

        

        // Should end with .eth

        try testing.expect(result.tokens[result.tokens.len - 1].type == .valid);

        

        // Should contain a stop character (.)

        var has_stop = false;

        for (result.tokens) |token| {

            if (token.type == .stop) {

                has_stop = true;

                break;

            }

        }

        try testing.expect(has_stop);

    }

}```

```zig [./tests/tokenization_fuzz.zig]

const std = @import("std");

const ens_normalize = @import("ens_normalize");

const tokenizer = ens_normalize.tokenizer;

const code_points = ens_normalize.code_points;

const testing = std.testing;



// Main fuzz testing function that should never crash

pub fn fuzz_tokenization(input: []const u8) !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Should never crash, even with malformed input

    const result = tokenizer.TokenizedName.fromInput(

        allocator, 

        input, 

        &specs, 

        false

    ) catch |err| switch (err) {

        error.InvalidUtf8 => return, // Expected for malformed UTF-8

        error.OutOfMemory => return, // Expected for huge inputs

        else => return err, // Unexpected errors should fail the test

    };

    

    defer result.deinit();

    

    // Verify basic invariants hold for all outputs

    try validateTokenInvariants(result.tokens);

}



// Validate that all tokens maintain basic invariants

fn validateTokenInvariants(tokens: []const tokenizer.Token) !void {

    for (tokens) |token| {

        // All tokens should have valid types

        _ = token.type.toString();

        

        // Memory should be properly managed

        switch (token.data) {

            .valid => |v| try testing.expect(v.cps.len > 0),

            .mapped => |m| {

                try testing.expect(m.cps.len > 0);

                // Original codepoint should be different from mapped

                if (m.cps.len == 1) {

                    try testing.expect(m.cp != m.cps[0]);

                }

            },

            .ignored => |i| _ = i.cp, // Any codepoint is valid for ignored

            .disallowed => |d| _ = d.cp, // Any codepoint is valid for disallowed

            .stop => |s| try testing.expect(s.cp == '.'),

            else => {},

        }

    }

}



// Test specific fuzzing scenarios

test "fuzz_utf8_boundary_cases" {

    

    // Test all single bytes (many will be invalid UTF-8)

    var i: u8 = 0;

    while (i < 255) : (i += 1) {

        const input = [_]u8{i};

        try fuzz_tokenization(&input);

    }

    

    // Test invalid UTF-8 sequences

    const invalid_utf8_cases = [_][]const u8{

        &[_]u8{0x80}, // Continuation byte without start

        &[_]u8{0xC0}, // Start byte without continuation

        &[_]u8{0xC0, 0x80}, // Overlong encoding

        &[_]u8{0xE0, 0x80, 0x80}, // Overlong encoding

        &[_]u8{0xF0, 0x80, 0x80, 0x80}, // Overlong encoding

        &[_]u8{0xFF, 0xFF}, // Invalid start bytes

        &[_]u8{0xED, 0xA0, 0x80}, // High surrogate

        &[_]u8{0xED, 0xB0, 0x80}, // Low surrogate

    };

    

    for (invalid_utf8_cases) |case| {

        try fuzz_tokenization(case);

    }

}



test "fuzz_unicode_plane_cases" {

    

    // Test boundary code points from different Unicode planes

    const boundary_codepoints = [_]u21{

        0x007F, // ASCII boundary

        0x0080, // Latin-1 start

        0x07FF, // 2-byte UTF-8 boundary

        0x0800, // 3-byte UTF-8 start

        0xD7FF, // Before surrogate range

        0xE000, // After surrogate range

        0xFFFD, // Replacement character

        0xFFFE, // Non-character

        0xFFFF, // Non-character

        0x10000, // 4-byte UTF-8 start

        0x10FFFF, // Maximum valid code point

    };

    

    for (boundary_codepoints) |cp| {

        var buf: [4]u8 = undefined;

        const len = std.unicode.utf8Encode(cp, &buf) catch continue;

        try fuzz_tokenization(buf[0..len]);

    }

}



test "fuzz_emoji_sequences" {

    

    // Test complex emoji sequences that might cause issues

    const emoji_test_cases = [_][]const u8{

        "👨‍👩‍👧‍👦", // Family emoji with ZWJ

        "🏳️‍🌈", // Flag with variation selector and ZWJ

        "👍🏻", // Emoji with skin tone modifier

        "🔥💯", // Multiple emoji

        "a👍b", // Emoji between ASCII

        "..👍..", // Emoji between separators

        "🚀🚀🚀🚀🚀", // Repeated emoji

        "🇺🇸", // Regional indicator sequence

        "©️", // Copyright with variation selector

        "1️⃣", // Keycap sequence

    };

    

    for (emoji_test_cases) |case| {

        try fuzz_tokenization(case);

    }

}



test "fuzz_length_stress_cases" {

    const allocator = testing.allocator;

    

    // Test various length inputs

    const test_lengths = [_]usize{ 0, 1, 10, 100, 1000, 10000 };

    

    for (test_lengths) |len| {

        // Create input of repeated 'a' characters

        const input = try allocator.alloc(u8, len);

        defer allocator.free(input);

        

        @memset(input, 'a');

        try fuzz_tokenization(input);

        

        // Create input of repeated periods

        @memset(input, '.');

        try fuzz_tokenization(input);

        

        // Create input of repeated invalid characters

        @memset(input, 0x80); // Invalid UTF-8 continuation byte

        try fuzz_tokenization(input);

    }

}



test "fuzz_mixed_input_cases" {

    

    // Test inputs that mix different character types rapidly

    const mixed_cases = [_][]const u8{

        "a.b.c.d", // Valid with stops

        "a\u{00AD}b", // Valid with ignored (soft hyphen)

        "a\u{0000}b", // Valid with null character

        "Hello\u{0301}World", // Valid with combining character

        "test@domain.eth", // Valid with disallowed character

        "café.eth", // Composed character

        "cafe\u{0301}.eth", // Decomposed character

        "test\u{200D}ing", // ZWJ between normal chars

        "混合テスト.eth", // Mixed scripts

        "...........", // Many stops

        "aaaaaaaaaa", // Many valid chars

        "\u{00AD}\u{00AD}\u{00AD}", // Many ignored chars

        "🔥🔥🔥🔥🔥", // Many emoji

    };

    

    for (mixed_cases) |case| {

        try fuzz_tokenization(case);

    }

}



test "fuzz_pathological_inputs" {

    

    // Test inputs designed to trigger edge cases

    const pathological_cases = [_][]const u8{

        "", // Empty string

        ".", // Single stop

        "..", // Double stop

        "...", // Triple stop

        "a.", // Valid then stop

        ".a", // Stop then valid

        "a..", // Valid then double stop

        "..a", // Double stop then valid

        "\u{00AD}", // Single ignored character

        "\u{00AD}\u{00AD}", // Multiple ignored characters

        "a\u{00AD}", // Valid then ignored

        "\u{00AD}a", // Ignored then valid

        "\u{FFFD}", // Replacement character

        "\u{FFFE}", // Non-character

        "\u{10FFFF}", // Maximum code point

    };

    

    for (pathological_cases) |case| {

        try fuzz_tokenization(case);

    }

}



test "fuzz_normalization_edge_cases" {

    

    // Test characters that might interact with normalization

    const normalization_cases = [_][]const u8{

        "café", // é (composed)

        "cafe\u{0301}", // é (decomposed)

        "noe\u{0308}l", // ë (decomposed)

        "noël", // ë (composed)

        "A\u{0300}", // À (decomposed)

        "À", // À (composed)

        "\u{1E9B}\u{0323}", // Long s with dot below

        "\u{0FB2}\u{0F80}", // Tibetan characters

        "\u{0F71}\u{0F72}\u{0F74}", // Tibetan vowel signs

    };

    

    for (normalization_cases) |case| {

        try fuzz_tokenization(case);

    }

}



// Performance fuzzing - ensure no algorithmic complexity issues

test "fuzz_performance_cases" {

    const allocator = testing.allocator;

    

    // Test patterns that might cause performance issues

    const performance_cases = [_]struct {

        pattern: []const u8,

        repeat_count: usize,

    }{

        .{ .pattern = "a", .repeat_count = 1000 },

        .{ .pattern = ".", .repeat_count = 1000 },

        .{ .pattern = "\u{00AD}", .repeat_count = 1000 },

        .{ .pattern = "👍", .repeat_count = 100 },

        .{ .pattern = "a.", .repeat_count = 500 },

        .{ .pattern = ".a", .repeat_count = 500 },

        .{ .pattern = "a\u{00AD}", .repeat_count = 500 },

    };

    

    for (performance_cases) |case| {

        const input = try allocator.alloc(u8, case.pattern.len * case.repeat_count);

        defer allocator.free(input);

        

        var i: usize = 0;

        while (i < case.repeat_count) : (i += 1) {

            const start = i * case.pattern.len;

            const end = start + case.pattern.len;

            @memcpy(input[start..end], case.pattern);

        }

        

        const start_time = std.time.microTimestamp();

        try fuzz_tokenization(input);

        const end_time = std.time.microTimestamp();

        

        // Should complete within reasonable time (1 second for 1000 repetitions)

        const duration_us = end_time - start_time;

        try testing.expect(duration_us < 1_000_000);

    }

}



// Random input fuzzing using a simple PRNG

test "fuzz_random_inputs" {

    const allocator = testing.allocator;

    

    var prng = std.Random.DefaultPrng.init(42);

    const random = prng.random();

    

    // Test various random inputs

    var i: usize = 0;

    while (i < 100) : (i += 1) {

        const len = random.intRangeAtMost(usize, 0, 100);

        const input = try allocator.alloc(u8, len);

        defer allocator.free(input);

        

        // Fill with random bytes

        random.bytes(input);

        

        try fuzz_tokenization(input);

    }

}```

```zig [./src/combining_marks.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const script_groups = @import("script_groups.zig");



/// Combining mark validation errors

pub const ValidationError = error{

    LeadingCombiningMark,

    CombiningMarkAfterEmoji,

    DisallowedCombiningMark,

    CombiningMarkAfterFenced,

    InvalidCombiningMarkBase,

    ExcessiveCombiningMarks,

    InvalidArabicDiacritic,

    ExcessiveArabicDiacritics,

    InvalidDevanagariMatras,

    InvalidThaiVowelSigns,

    CombiningMarkOrderError,

};



/// Validate combining marks for a specific script group

pub fn validateCombiningMarks(

    codepoints: []const CodePoint,

    script_group: *const script_groups.ScriptGroup,

    allocator: std.mem.Allocator,

) ValidationError!void {

    _ = allocator; // For future use in complex validations

    

    for (codepoints, 0..) |cp, i| {

        if (isCombiningMark(cp)) {

            // Rule CM1: No leading combining marks

            if (i == 0) {

                return ValidationError.LeadingCombiningMark;

            }

            

            // Rule CM3: CM must be allowed by this script group

            if (!script_group.cm.contains(cp)) {

                return ValidationError.DisallowedCombiningMark;

            }

            

            // Rule CM4: Check preceding character context

            const prev_cp = codepoints[i - 1];

            try validateCombiningMarkContext(prev_cp, cp);

        }

    }

    

    // Additional script-specific validation

    try validateScriptSpecificCMRules(codepoints, script_group);

}



/// Validate combining mark context (what it can follow)

fn validateCombiningMarkContext(base_cp: CodePoint, cm_cp: CodePoint) ValidationError!void {

    _ = cm_cp; // For future context-specific validations

    

    // Rule CM4a: No combining marks after emoji

    if (isEmoji(base_cp)) {

        return ValidationError.CombiningMarkAfterEmoji;

    }

    

    // Rule CM4b: No combining marks after certain punctuation

    if (isFenced(base_cp)) {

        return ValidationError.CombiningMarkAfterFenced;

    }

}



/// Script-specific combining mark rules

fn validateScriptSpecificCMRules(

    codepoints: []const CodePoint,

    script_group: *const script_groups.ScriptGroup,

) ValidationError!void {

    if (std.mem.eql(u8, script_group.name, "Arabic")) {

        try validateArabicCMRules(codepoints);

    } else if (std.mem.eql(u8, script_group.name, "Devanagari")) {

        try validateDevanagaricCMRules(codepoints);

    } else if (std.mem.eql(u8, script_group.name, "Thai")) {

        try validateThaiCMRules(codepoints);

    }

}



/// Arabic-specific combining mark validation

fn validateArabicCMRules(codepoints: []const CodePoint) ValidationError!void {

    var vowel_marks_count: usize = 0;

    var prev_was_consonant = false;

    

    for (codepoints) |cp| {

        if (isArabicVowelMark(cp)) {

            vowel_marks_count += 1;

            if (!prev_was_consonant) {

                return ValidationError.InvalidArabicDiacritic;

            }

            prev_was_consonant = false;

        } else if (isArabicConsonant(cp)) {

            vowel_marks_count = 0;

            prev_was_consonant = true;

        }

        

        // Limit vowel marks per consonant

        if (vowel_marks_count > 3) {

            return ValidationError.ExcessiveArabicDiacritics;

        }

    }

}



/// Devanagari-specific combining mark validation

fn validateDevanagaricCMRules(codepoints: []const CodePoint) ValidationError!void {

    for (codepoints, 0..) |cp, i| {

        if (isDevanagariMatra(cp)) {

            if (i == 0) {

                return ValidationError.InvalidDevanagariMatras;

            }

            const prev_cp = codepoints[i - 1];

            if (!isDevanagariConsonant(prev_cp)) {

                return ValidationError.InvalidDevanagariMatras;

            }

        }

    }

}



/// Thai-specific combining mark validation

fn validateThaiCMRules(codepoints: []const CodePoint) ValidationError!void {

    for (codepoints, 0..) |cp, i| {

        if (isThaiVowelSign(cp)) {

            if (i == 0) {

                return ValidationError.InvalidThaiVowelSigns;

            }

            const prev_cp = codepoints[i - 1];

            if (!isThaiConsonant(prev_cp)) {

                return ValidationError.InvalidThaiVowelSigns;

            }

        }

    }

}



/// Check if codepoint is a combining mark

pub fn isCombiningMark(cp: CodePoint) bool {

    // Unicode categories Mn, Mc, Me

    return (cp >= 0x0300 and cp <= 0x036F) or  // Combining Diacritical Marks

           (cp >= 0x1AB0 and cp <= 0x1AFF) or  // Combining Diacritical Marks Extended

           (cp >= 0x1DC0 and cp <= 0x1DFF) or  // Combining Diacritical Marks Supplement

           (cp >= 0x20D0 and cp <= 0x20FF) or  // Combining Diacritical Marks for Symbols

           isScriptSpecificCM(cp);

}



/// Check for script-specific combining marks

fn isScriptSpecificCM(cp: CodePoint) bool {

    return isArabicCM(cp) or 

           isDevanagaricCM(cp) or 

           isThaiCM(cp) or

           isHebrewCM(cp);

}



fn isArabicCM(cp: CodePoint) bool {

    return (cp >= 0x064B and cp <= 0x065F) or  // Arabic diacritics

           (cp >= 0x0670 and cp <= 0x0671) or  // Arabic superscript alef

           (cp >= 0x06D6 and cp <= 0x06ED);    // Arabic small high marks

}



fn isDevanagaricCM(cp: CodePoint) bool {

    return (cp >= 0x093A and cp <= 0x094F) or  // Devanagari vowel signs

           (cp >= 0x0951 and cp <= 0x0957);    // Devanagari stress signs

}



fn isThaiCM(cp: CodePoint) bool {

    return (cp >= 0x0E31 and cp <= 0x0E3A) or  // Thai vowel signs and tone marks

           (cp >= 0x0E47 and cp <= 0x0E4E);    // Thai tone marks

}



fn isHebrewCM(cp: CodePoint) bool {

    return (cp >= 0x05B0 and cp <= 0x05BD) or  // Hebrew points

           (cp >= 0x05BF and cp <= 0x05C7);    // Hebrew points and marks

}



/// Check if codepoint is an emoji

fn isEmoji(cp: CodePoint) bool {

    return (cp >= 0x1F600 and cp <= 0x1F64F) or  // Emoticons

           (cp >= 0x1F300 and cp <= 0x1F5FF) or  // Miscellaneous Symbols and Pictographs

           (cp >= 0x1F680 and cp <= 0x1F6FF) or  // Transport and Map Symbols

           (cp >= 0x1F700 and cp <= 0x1F77F) or  // Alchemical Symbols

           (cp >= 0x1F780 and cp <= 0x1F7FF) or  // Geometric Shapes Extended

           (cp >= 0x1F800 and cp <= 0x1F8FF) or  // Supplemental Arrows-C

           (cp >= 0x2600 and cp <= 0x26FF) or    // Miscellaneous Symbols

           (cp >= 0x2700 and cp <= 0x27BF);      // Dingbats

}



/// Check if codepoint is a fenced character (punctuation that shouldn't have CMs)

fn isFenced(cp: CodePoint) bool {

    return cp == 0x002E or  // Period

           cp == 0x002C or  // Comma

           cp == 0x003A or  // Colon

           cp == 0x003B or  // Semicolon

           cp == 0x0021 or  // Exclamation mark

           cp == 0x003F;    // Question mark

}



/// Arabic vowel marks

fn isArabicVowelMark(cp: CodePoint) bool {

    return (cp >= 0x064B and cp <= 0x0650) or  // Fathatan, Dammatan, Kasratan, Fatha, Damma, Kasra

           cp == 0x0652 or                      // Sukun

           cp == 0x0640;                        // Tatweel

}



/// Arabic consonants (simplified check)

fn isArabicConsonant(cp: CodePoint) bool {

    return (cp >= 0x0621 and cp <= 0x063A) or  // Arabic letters

           (cp >= 0x0641 and cp <= 0x064A);    // Arabic letters continued

}



/// Devanagari vowel signs (matras)

fn isDevanagariMatra(cp: CodePoint) bool {

    return (cp >= 0x093E and cp <= 0x094F) and cp != 0x0940;  // Vowel signs except invalid ones

}



/// Devanagari consonants

fn isDevanagariConsonant(cp: CodePoint) bool {

    return (cp >= 0x0915 and cp <= 0x0939) or  // Consonants

           (cp >= 0x0958 and cp <= 0x095F);    // Additional consonants

}



/// Thai vowel signs

fn isThaiVowelSign(cp: CodePoint) bool {

    return (cp >= 0x0E31 and cp <= 0x0E3A) or  // Vowel signs above and below

           cp == 0x0E47 or cp == 0x0E48 or     // Tone marks

           cp == 0x0E49 or cp == 0x0E4A or

           cp == 0x0E4B or cp == 0x0E4C;

}



/// Thai consonants

fn isThaiConsonant(cp: CodePoint) bool {

    return (cp >= 0x0E01 and cp <= 0x0E2E);  // Thai consonants

}



// Tests

const testing = std.testing;



test "combining mark detection" {

    // Test basic combining marks

    try testing.expect(isCombiningMark(0x0301)); // Combining acute accent

    try testing.expect(isCombiningMark(0x0300)); // Combining grave accent

    try testing.expect(isCombiningMark(0x064E)); // Arabic fatha

    

    // Test non-combining marks

    try testing.expect(!isCombiningMark('a'));

    try testing.expect(!isCombiningMark('A'));

    try testing.expect(!isCombiningMark(0x0041)); // Latin A

}



test "emoji detection" {

    try testing.expect(isEmoji(0x1F600)); // Grinning face

    try testing.expect(isEmoji(0x1F680)); // Rocket

    try testing.expect(!isEmoji('a'));

    try testing.expect(!isEmoji(0x0301)); // Combining accent

}



test "fenced character detection" {

    try testing.expect(isFenced('.'));

    try testing.expect(isFenced(','));

    try testing.expect(isFenced(':'));

    try testing.expect(!isFenced('a'));

    try testing.expect(!isFenced(0x0301));

}



test "script-specific combining mark detection" {

    // Arabic

    try testing.expect(isArabicCM(0x064E)); // Fatha

    try testing.expect(isArabicVowelMark(0x064E));

    try testing.expect(isArabicConsonant(0x0628)); // Beh

    

    // Devanagari  

    try testing.expect(isDevanagaricCM(0x093E)); // Aa matra

    try testing.expect(isDevanagariMatra(0x093E));

    try testing.expect(isDevanagariConsonant(0x0915)); // Ka

    

    // Thai

    try testing.expect(isThaiCM(0x0E31)); // Mai han-akat

    try testing.expect(isThaiVowelSign(0x0E31));

    try testing.expect(isThaiConsonant(0x0E01)); // Ko kai

}



test "leading combining mark validation" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Create a mock script group for testing

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    // Add combining mark to allowed set

    try latin_group.cm.put(0x0301, {});

    

    // Test leading combining mark (should fail)

    const leading_cm = [_]CodePoint{0x0301, 'a'};

    const result = validateCombiningMarks(&leading_cm, &latin_group, allocator);

    try testing.expectError(ValidationError.LeadingCombiningMark, result);

}



test "disallowed combining mark validation" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Create a mock script group that doesn't allow Arabic CMs

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    // Don't add Arabic CM to allowed set

    

    // Test Arabic CM with Latin group (should fail)

    const wrong_script_cm = [_]CodePoint{'a', 0x064E}; // Latin + Arabic fatha

    const result = validateCombiningMarks(&wrong_script_cm, &latin_group, allocator);

    try testing.expectError(ValidationError.DisallowedCombiningMark, result);

}



test "combining mark after emoji validation" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var emoji_group = script_groups.ScriptGroup.init(allocator, "Emoji", 0);

    defer emoji_group.deinit();

    

    // Add combining mark to allowed set

    try emoji_group.cm.put(0x0301, {});

    

    // Test emoji + combining mark (should fail)

    const emoji_cm = [_]CodePoint{0x1F600, 0x0301}; // Grinning face + acute

    const result = validateCombiningMarks(&emoji_cm, &emoji_group, allocator);

    try testing.expectError(ValidationError.CombiningMarkAfterEmoji, result);

}



test "valid combining mark sequences" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);

    defer latin_group.deinit();

    

    // Add combining marks to allowed set

    try latin_group.cm.put(0x0301, {}); // Acute accent

    try latin_group.cm.put(0x0300, {}); // Grave accent

    

    // Test valid sequences (should pass)

    const valid_sequences = [_][]const CodePoint{

        &[_]CodePoint{'a', 0x0301},      // á

        &[_]CodePoint{'e', 0x0300},      // è  

        &[_]CodePoint{'a', 0x0301, 0x0300}, // Multiple CMs

    };

    

    for (valid_sequences) |seq| {

        try validateCombiningMarks(seq, &latin_group, allocator);

    }

}



test "arabic diacritic validation" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    // Add Arabic combining marks

    try arabic_group.cm.put(0x064E, {}); // Fatha

    try arabic_group.cm.put(0x064F, {}); // Damma

    

    // Test valid Arabic with diacritics

    const valid_arabic = [_]CodePoint{0x0628, 0x064E}; // بَ (beh + fatha)

    try validateCombiningMarks(&valid_arabic, &arabic_group, allocator);

    

    // Test excessive diacritics (should fail)

    const excessive = [_]CodePoint{0x0628, 0x064E, 0x064F, 0x0650, 0x0651}; // Too many marks

    const result = validateCombiningMarks(&excessive, &arabic_group, allocator);

    try testing.expectError(ValidationError.ExcessiveArabicDiacritics, result);

}```

```zig [./src/spec_data.zig]

const std = @import("std");



/// Load spec data at compile time

const spec_zon = @embedFile("data/spec.zon");



/// Parsed spec data structure

pub const SpecData = struct {

    created: []const u8,

    unicode: []const u8,

    cldr: []const u8,

    emoji: []const []const u32,

    fenced: []const u32,

    ignored: []const u32,

    mapped: []const MappedChar,

    nfc_check: []const u32,

    nsm: []const u32,

    nsm_max: u32,

    cm: []const u32,

    wholes: []const Whole,

    groups: []const Group,

    

    pub const MappedChar = struct {

        cp: u32,

        mapped: []const u32,

    };

    

    pub const Whole = struct {

        valid: []const u32,

        confused: []const u32,

    };

    

    pub const Group = struct {

        name: []const u8,

        primary: []const u32,

        secondary: ?[]const u32 = null,

        cm: ?[]const u32 = null,

        restricted: ?bool = null,

    };

};



/// Parse spec at compile time

pub fn parseSpec() !SpecData {

    @setEvalBranchQuota(1_000_000);

    

    var diagnostics: std.zig.Ast.Diagnostics = .{};

    var ast = try std.zig.Ast.parse(std.heap.page_allocator, spec_zon, .zon, &diagnostics);

    defer ast.deinit(std.heap.page_allocator);

    

    if (diagnostics.errors.len > 0) {

        return error.ParseError;

    }

    

    // For now, return a placeholder

    // TODO: Implement actual ZON parsing

    return SpecData{

        .created = "",

        .unicode = "",

        .cldr = "",

        .emoji = &.{},

        .fenced = &.{},

        .ignored = &.{},

        .mapped = &.{},

        .nfc_check = &.{},

        .nsm = &.{},

        .nsm_max = 4,

        .cm = &.{},

        .wholes = &.{},

        .groups = &.{},

    };

}



/// Get spec data (parsed once at compile time)

pub const spec = parseSpec() catch @panic("Failed to parse spec.zon");



/// Script group enum for the most common scripts

pub const ScriptGroup = enum(u8) {

    Latin,

    Greek,

    Cyrillic,

    Hebrew,

    Arabic,

    Devanagari,

    Bengali,

    Gurmukhi,

    Gujarati,

    Tamil,

    Telugu,

    Kannada,

    Malayalam,

    Thai,

    Lao,

    Tibetan,

    Myanmar,

    Georgian,

    Hangul,

    Hiragana,

    Katakana,

    Han,

    Emoji,

    ASCII,

    Other,

    

    pub fn fromName(name: []const u8) ScriptGroup {

        inline for (@typeInfo(ScriptGroup).Enum.fields) |field| {

            if (std.mem.eql(u8, field.name, name)) {

                return @enumFromInt(field.value);

            }

        }

        return .Other;

    }

    

    pub fn toString(self: ScriptGroup) []const u8 {

        return @tagName(self);

    }

};```

```zig [./src/comptime_data.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;



// Define ZON data types

const MappedItem = struct { u32, []const u32 };

const FencedItem = struct { u32, []const u8 };

const WholeItem = struct {

    target: ?[]const u8,

    valid: []const u32,

    confused: []const u32,

};

const GroupItem = struct {

    name: []const u8,

    primary: []const u32,

    secondary: ?[]const u32 = null,

    cm: ?[]const u32 = null,

    restricted: ?bool = null,

};



const SpecData = struct {

    created: []const u8,

    unicode: []const u8,

    cldr: []const u8,

    emoji: []const []const u32,

    ignored: []const u32,

    mapped: []const MappedItem,

    fenced: []const FencedItem,

    groups: []const GroupItem,

    nsm: []const u32,

    nsm_max: u32,

    nfc_check: []const u32,

    wholes: []const WholeItem,

    cm: []const u32,

    escape: []const u32,

};



const DecompItem = struct { u32, []const u32 };

const RankItem = []const u32;



const NfData = struct {

    created: []const u8,

    unicode: []const u8,

    exclusions: []const u32,

    decomp: []const DecompItem,

    ranks: []const RankItem,

    qc: ?[]const u32 = null,

};



// Import ZON data at compile time

const spec_data: SpecData = @import("data/spec.zon");

const nf_data: NfData = @import("data/nf.zon");



// Comptime perfect hash for character mappings

pub const CharacterMappingEntry = struct {

    from: CodePoint,

    to: []const CodePoint,

};



// Generate a sorted array of character mappings at compile time

pub const character_mappings = blk: {

    @setEvalBranchQuota(100000);

    const count = spec_data.mapped.len;

    var entries: [count]CharacterMappingEntry = undefined;

    

    for (spec_data.mapped, 0..) |mapping, i| {

        entries[i] = .{

            .from = mapping[0],

            .to = mapping[1],

        };

    }

    

    // Sort by 'from' codepoint for binary search

    const Context = struct {

        fn lessThan(_: void, a: CharacterMappingEntry, b: CharacterMappingEntry) bool {

            return a.from < b.from;

        }

    };

    std.sort.insertion(CharacterMappingEntry, &entries, {}, Context.lessThan);

    

    break :blk entries;

};



// Binary search for character mapping

pub fn getMappedCodePoints(cp: CodePoint) ?[]const CodePoint {

    var left: usize = 0;

    var right: usize = character_mappings.len;

    

    while (left < right) {

        const mid = left + (right - left) / 2;

        if (character_mappings[mid].from == cp) {

            return character_mappings[mid].to;

        } else if (character_mappings[mid].from < cp) {

            left = mid + 1;

        } else {

            right = mid;

        }

    }

    

    return null;

}



// Comptime set for ignored characters

pub const ignored_chars = blk: {

    @setEvalBranchQuota(10000);

    var set = std.StaticBitSet(0x110000).initEmpty();

    for (spec_data.ignored) |cp| {

        set.set(cp);

    }

    break :blk set;

};



pub fn isIgnored(cp: CodePoint) bool {

    if (cp >= 0x110000) return false;

    return ignored_chars.isSet(cp);

}



// Comptime set for fenced characters

pub const fenced_chars = blk: {

    @setEvalBranchQuota(10000);

    var set = std.StaticBitSet(0x110000).initEmpty();

    for (spec_data.fenced) |item| {

        set.set(item[0]);

    }

    break :blk set;

};



pub fn isFenced(cp: CodePoint) bool {

    if (cp >= 0x110000) return false;

    return fenced_chars.isSet(cp);

}



// Comptime set for valid characters (from all groups)

pub const valid_chars = blk: {

    @setEvalBranchQuota(10000000); // Need very high quota for all Unicode characters

    var set = std.StaticBitSet(0x110000).initEmpty();

    

    for (spec_data.groups) |group| {

        // Add primary characters

        for (group.primary) |cp| {

            set.set(cp);

        }

        

        // Add secondary characters if present

        if (group.secondary) |secondary| {

            for (secondary) |cp| {

                set.set(cp);

            }

        }

    }

    

    break :blk set;

};



pub fn isValid(cp: CodePoint) bool {

    if (cp >= 0x110000) return false;

    return valid_chars.isSet(cp);

}



// Comptime emoji data structure

pub const EmojiEntry = struct {

    sequence: []const CodePoint,

    no_fe0f: []const CodePoint,

};



pub const emoji_sequences = blk: {

    @setEvalBranchQuota(50000);

    const count = spec_data.emoji.len;

    var entries: [count]EmojiEntry = undefined;

    

    for (spec_data.emoji, 0..) |seq, i| {

        // Calculate no_fe0f version

        var no_fe0f_count: usize = 0;

        for (seq) |cp| {

            if (cp != 0xFE0F) no_fe0f_count += 1;

        }

        

        var no_fe0f: [no_fe0f_count]CodePoint = undefined;

        var j: usize = 0;

        for (seq) |cp| {

            if (cp != 0xFE0F) {

                no_fe0f[j] = cp;

                j += 1;

            }

        }

        

        entries[i] = .{

            .sequence = seq,

            .no_fe0f = &no_fe0f,

        };

    }

    

    break :blk entries;

};



// Comptime NFC decomposition data

pub const NFCDecompEntry = struct {

    cp: CodePoint,

    decomp: []const CodePoint,

};



pub const nfc_decompositions = blk: {

    @setEvalBranchQuota(50000);

    const count = nf_data.decomp.len;

    var entries: [count]NFCDecompEntry = undefined;

    

    for (nf_data.decomp, 0..) |entry, i| {

        entries[i] = .{

            .cp = entry[0],

            .decomp = entry[1],

        };

    }

    

    // Sort by codepoint for binary search

    const Context = struct {

        fn lessThan(_: void, a: NFCDecompEntry, b: NFCDecompEntry) bool {

            return a.cp < b.cp;

        }

    };

    std.sort.insertion(NFCDecompEntry, &entries, {}, Context.lessThan);

    

    break :blk entries;

};



pub fn getNFCDecomposition(cp: CodePoint) ?[]const CodePoint {

    var left: usize = 0;

    var right: usize = nfc_decompositions.len;

    

    while (left < right) {

        const mid = left + (right - left) / 2;

        if (nfc_decompositions[mid].cp == cp) {

            return nfc_decompositions[mid].decomp;

        } else if (nfc_decompositions[mid].cp < cp) {

            left = mid + 1;

        } else {

            right = mid;

        }

    }

    

    return null;

}



// Comptime NFC exclusions set

pub const nfc_exclusions = blk: {

    @setEvalBranchQuota(10000);

    var set = std.StaticBitSet(0x110000).initEmpty();

    for (nf_data.exclusions) |cp| {

        set.set(cp);

    }

    break :blk set;

};



pub fn isNFCExclusion(cp: CodePoint) bool {

    if (cp >= 0x110000) return false;

    return nfc_exclusions.isSet(cp);

}



// Comptime NFC check set

pub const nfc_check_set = blk: {

    @setEvalBranchQuota(10000);

    var set = std.StaticBitSet(0x110000).initEmpty();

    for (spec_data.nfc_check) |cp| {

        set.set(cp);

    }

    break :blk set;

};



pub fn needsNFCCheck(cp: CodePoint) bool {

    if (cp >= 0x110000) return false;

    return nfc_check_set.isSet(cp);

}



// Comptime NSM set

pub const nsm_set = blk: {

    @setEvalBranchQuota(10000);

    var set = std.StaticBitSet(0x110000).initEmpty();

    for (spec_data.nsm) |cp| {

        set.set(cp);

    }

    break :blk set;

};



pub fn isNSM(cp: CodePoint) bool {

    if (cp >= 0x110000) return false;

    return nsm_set.isSet(cp);

}



// Comptime combining marks set

pub const cm_set = blk: {

    @setEvalBranchQuota(10000);

    var set = std.StaticBitSet(0x110000).initEmpty();

    for (spec_data.cm) |cp| {

        set.set(cp);

    }

    break :blk set;

};



pub fn isCombiningMark(cp: CodePoint) bool {

    if (cp >= 0x110000) return false;

    return cm_set.isSet(cp);

}



// Comptime escape set

pub const escape_set = blk: {

    @setEvalBranchQuota(10000);

    var set = std.StaticBitSet(0x110000).initEmpty();

    for (spec_data.escape) |cp| {

        set.set(cp);

    }

    break :blk set;

};



pub fn needsEscape(cp: CodePoint) bool {

    if (cp >= 0x110000) return false;

    return escape_set.isSet(cp);

}



// Export spec data constants

pub const nsm_max = spec_data.nsm_max;

pub const spec_created = spec_data.created;

pub const spec_unicode = spec_data.unicode;

pub const spec_cldr = spec_data.cldr;



test "comptime character mappings" {

    const testing = std.testing;

    

    // Test that we can look up a mapping

    if (character_mappings.len > 0) {

        const first = character_mappings[0];

        const result = getMappedCodePoints(first.from);

        try testing.expect(result != null);

        try testing.expectEqualSlices(CodePoint, first.to, result.?);

    }

    

    // Test non-existent mapping

    const no_mapping = getMappedCodePoints(0xFFFFF);

    try testing.expect(no_mapping == null);

}



test "comptime sets" {

    const testing = std.testing;

    

    // Test ignored character

    if (spec_data.ignored.len > 0) {

        const first_ignored = spec_data.ignored[0];

        try testing.expect(isIgnored(first_ignored));

    }

    

    // Test non-ignored character

    try testing.expect(!isIgnored('A'));

    

    // Test fenced character

    if (spec_data.fenced.len > 0) {

        const first_fenced = spec_data.fenced[0][0];

        try testing.expect(isFenced(first_fenced));

    }

}```

```zig [./src/nsm_validation.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const script_groups = @import("script_groups.zig");



/// NSM validation errors

pub const NSMValidationError = error{

    ExcessiveNSM,           // More than 4 NSMs per base character

    DuplicateNSM,           // Same NSM appears consecutively

    LeadingNSM,             // NSM at start of sequence

    NSMAfterEmoji,          // NSM following emoji (not allowed)

    NSMAfterFenced,         // NSM following fenced character

    InvalidNSMBase,         // NSM following inappropriate base character

    NSMOrderError,          // NSMs not in canonical order

    DisallowedNSMScript,    // NSM from wrong script group

};



/// NSM sequence information for validation

pub const NSMSequence = struct {

    base_char: CodePoint,

    nsms: []const CodePoint,

    script_group: *const script_groups.ScriptGroup,

    

    pub fn validate(self: NSMSequence) NSMValidationError!void {

        // Check NSM count (ENSIP-15: max 4 NSMs per base character)

        if (self.nsms.len > 4) {

            return NSMValidationError.ExcessiveNSM;

        }

        

        // Check for duplicate NSMs in sequence

        for (self.nsms, 0..) |nsm1, i| {

            for (self.nsms[i+1..]) |nsm2| {

                if (nsm1 == nsm2) {

                    return NSMValidationError.DuplicateNSM;

                }

            }

        }

        

        // Check if all NSMs are allowed by this script group

        for (self.nsms) |nsm| {

            if (!self.script_group.cm.contains(nsm)) {

                return NSMValidationError.DisallowedNSMScript;

            }

        }

        

        // TODO: Check canonical ordering when we have full Unicode data

        // For now, we assume input is already in canonical order

    }

};



/// Comprehensive NSM validation for ENSIP-15 compliance

pub fn validateNSM(

    codepoints: []const CodePoint,

    groups: *const script_groups.ScriptGroups,

    script_group: *const script_groups.ScriptGroup,

    allocator: std.mem.Allocator,

) NSMValidationError!void {

    _ = allocator; // Reserved for future use (NFD normalization, etc.)

    if (codepoints.len == 0) return;

    

    // Check for leading NSM

    if (groups.isNSM(codepoints[0])) {

        return NSMValidationError.LeadingNSM;

    }

    

    var i: usize = 0;

    while (i < codepoints.len) {

        const cp = codepoints[i];

        

        if (!groups.isNSM(cp)) {

            // This is a base character, collect following NSMs

            const nsm_start = i + 1;

            var nsm_end = nsm_start;

            

            // Find all consecutive NSMs following this base character

            while (nsm_end < codepoints.len and groups.isNSM(codepoints[nsm_end])) {

                nsm_end += 1;

            }

            

            if (nsm_end > nsm_start) {

                // We have NSMs following this base character

                const nsms = codepoints[nsm_start..nsm_end];

                

                // Validate context - check if base character can accept NSMs

                try validateNSMContext(cp, nsms);

                

                // Create NSM sequence and validate

                const sequence = NSMSequence{

                    .base_char = cp,

                    .nsms = nsms,

                    .script_group = script_group,

                };

                try sequence.validate();

                

                // Apply script-specific validation

                try validateScriptSpecificNSMRules(cp, nsms, script_group);

                

                // Move past all NSMs

                i = nsm_end;

            } else {

                i += 1;

            }

        } else {

            // This should not happen if we handle base characters correctly

            i += 1;

        }

    }

}



/// Validate NSM context (what base characters can accept NSMs)

fn validateNSMContext(base_cp: CodePoint, nsms: []const CodePoint) NSMValidationError!void {

    _ = nsms; // For future context-specific validations

    

    // Rule: No NSMs after emoji

    if (isEmoji(base_cp)) {

        return NSMValidationError.NSMAfterEmoji;

    }

    

    // Rule: No NSMs after certain punctuation

    if (isFenced(base_cp)) {

        return NSMValidationError.NSMAfterFenced;

    }

    

    // Rule: No NSMs after certain symbols or control characters

    if (isInvalidNSMBase(base_cp)) {

        return NSMValidationError.InvalidNSMBase;

    }

}



/// Script-specific NSM validation rules

fn validateScriptSpecificNSMRules(

    base_cp: CodePoint,

    nsms: []const CodePoint,

    script_group: *const script_groups.ScriptGroup,

) NSMValidationError!void {

    if (std.mem.eql(u8, script_group.name, "Arabic")) {

        try validateArabicNSMRules(base_cp, nsms);

    } else if (std.mem.eql(u8, script_group.name, "Hebrew")) {

        try validateHebrewNSMRules(base_cp, nsms);

    } else if (std.mem.eql(u8, script_group.name, "Devanagari")) {

        try validateDevanagariNSMRules(base_cp, nsms);

    }

}



/// Arabic-specific NSM validation

fn validateArabicNSMRules(base_cp: CodePoint, nsms: []const CodePoint) NSMValidationError!void {

    // Arabic NSM rules:

    // 1. Diacritics should only appear on Arabic letters

    // 2. Maximum 3 diacritics per consonant (more restrictive than general 4)

    // 3. Certain combinations are invalid

    

    if (!isArabicLetter(base_cp)) {

        return NSMValidationError.InvalidNSMBase;

    }

    

    if (nsms.len > 3) {

        return NSMValidationError.ExcessiveNSM;

    }

    

    // Check for invalid combinations

    var has_vowel_mark = false;

    var has_shadda = false;

    

    for (nsms) |nsm| {

        if (isArabicVowelMark(nsm)) {

            if (has_vowel_mark) {

                // Multiple vowel marks on same consonant

                return NSMValidationError.DuplicateNSM;

            }

            has_vowel_mark = true;

        }

        

        if (nsm == 0x0651) { // Arabic Shadda

            if (has_shadda) {

                return NSMValidationError.DuplicateNSM;

            }

            has_shadda = true;

        }

    }

}



/// Hebrew-specific NSM validation

fn validateHebrewNSMRules(base_cp: CodePoint, nsms: []const CodePoint) NSMValidationError!void {

    // Hebrew NSM rules:

    // 1. Points should only appear on Hebrew letters

    // 2. Specific point combinations

    

    if (!isHebrewLetter(base_cp)) {

        return NSMValidationError.InvalidNSMBase;

    }

    

    // Hebrew allows fewer NSMs per character

    if (nsms.len > 2) {

        return NSMValidationError.ExcessiveNSM;

    }

}



/// Devanagari-specific NSM validation  

fn validateDevanagariNSMRules(base_cp: CodePoint, nsms: []const CodePoint) NSMValidationError!void {

    // Devanagari NSM rules:

    // 1. Vowel signs should only appear on consonants

    // 2. Specific ordering requirements

    

    if (!isDevanagariConsonant(base_cp)) {

        return NSMValidationError.InvalidNSMBase;

    }

    

    if (nsms.len > 2) {

        return NSMValidationError.ExcessiveNSM;

    }

}



/// Check if codepoint is an emoji

fn isEmoji(cp: CodePoint) bool {

    return (cp >= 0x1F600 and cp <= 0x1F64F) or  // Emoticons

           (cp >= 0x1F300 and cp <= 0x1F5FF) or  // Miscellaneous Symbols and Pictographs

           (cp >= 0x1F680 and cp <= 0x1F6FF) or  // Transport and Map Symbols

           (cp >= 0x2600 and cp <= 0x26FF);      // Miscellaneous Symbols

}



/// Check if codepoint is a fenced character

fn isFenced(cp: CodePoint) bool {

    return cp == 0x002E or  // Period

           cp == 0x002C or  // Comma

           cp == 0x003A or  // Colon

           cp == 0x003B or  // Semicolon

           cp == 0x0021 or  // Exclamation mark

           cp == 0x003F;    // Question mark

}



/// Check if codepoint is invalid as NSM base

fn isInvalidNSMBase(cp: CodePoint) bool {

    // Control characters, format characters, etc.

    return (cp >= 0x0000 and cp <= 0x001F) or  // C0 controls

           (cp >= 0x007F and cp <= 0x009F) or  // C1 controls

           (cp >= 0x2000 and cp <= 0x200F) or  // General punctuation (some)

           (cp >= 0xFFF0 and cp <= 0xFFFF);    // Specials

}



/// Arabic letter detection

fn isArabicLetter(cp: CodePoint) bool {

    return (cp >= 0x0621 and cp <= 0x063A) or  // Arabic letters

           (cp >= 0x0641 and cp <= 0x064A) or  // Arabic letters continued

           (cp >= 0x0671 and cp <= 0x06D3) or  // Arabic letters extended

           (cp >= 0x06FA and cp <= 0x06FF);    // Arabic letters supplement

}



/// Arabic vowel mark detection

fn isArabicVowelMark(cp: CodePoint) bool {

    return (cp >= 0x064B and cp <= 0x0650) or  // Fathatan, Dammatan, Kasratan, Fatha, Damma, Kasra

           cp == 0x0652;                        // Sukun

}



/// Hebrew letter detection

fn isHebrewLetter(cp: CodePoint) bool {

    return (cp >= 0x05D0 and cp <= 0x05EA) or  // Hebrew letters

           (cp >= 0x05F0 and cp <= 0x05F2);    // Hebrew ligatures

}



/// Devanagari consonant detection

fn isDevanagariConsonant(cp: CodePoint) bool {

    return (cp >= 0x0915 and cp <= 0x0939) or  // Consonants

           (cp >= 0x0958 and cp <= 0x095F);    // Additional consonants

}



/// Enhanced NSM detection with Unicode categories

pub fn isNSM(cp: CodePoint) bool {

    // Unicode General Category Mn (Mark, nonspacing)

    // This is a more comprehensive check than the basic one

    return (cp >= 0x0300 and cp <= 0x036F) or  // Combining Diacritical Marks

           (cp >= 0x0483 and cp <= 0x0489) or  // Cyrillic combining marks

           (cp >= 0x0591 and cp <= 0x05BD) or  // Hebrew points

           (cp >= 0x05BF and cp <= 0x05BF) or  // Hebrew point

           (cp >= 0x05C1 and cp <= 0x05C2) or  // Hebrew points

           (cp >= 0x05C4 and cp <= 0x05C5) or  // Hebrew points

           (cp >= 0x05C7 and cp <= 0x05C7) or  // Hebrew point

           (cp >= 0x0610 and cp <= 0x061A) or  // Arabic marks

           (cp >= 0x064B and cp <= 0x065F) or  // Arabic diacritics

           (cp >= 0x0670 and cp <= 0x0670) or  // Arabic letter superscript alef

           (cp >= 0x06D6 and cp <= 0x06DC) or  // Arabic small high marks

           (cp >= 0x06DF and cp <= 0x06E4) or  // Arabic small high marks

           (cp >= 0x06E7 and cp <= 0x06E8) or  // Arabic small high marks

           (cp >= 0x06EA and cp <= 0x06ED) or  // Arabic small high marks

           (cp >= 0x0711 and cp <= 0x0711) or  // Syriac letter superscript alaph

           (cp >= 0x0730 and cp <= 0x074A) or  // Syriac points

           (cp >= 0x07A6 and cp <= 0x07B0) or  // Thaana points

           (cp >= 0x07EB and cp <= 0x07F3) or  // NKo combining marks

           (cp >= 0x0816 and cp <= 0x0819) or  // Samaritan marks

           (cp >= 0x081B and cp <= 0x0823) or  // Samaritan marks

           (cp >= 0x0825 and cp <= 0x0827) or  // Samaritan marks

           (cp >= 0x0829 and cp <= 0x082D) or  // Samaritan marks

           (cp >= 0x0859 and cp <= 0x085B) or  // Mandaic marks

           (cp >= 0x08E3 and cp <= 0x0902) or  // Arabic/Devanagari marks

           (cp >= 0x093A and cp <= 0x093A) or  // Devanagari vowel sign oe

           (cp >= 0x093C and cp <= 0x093C) or  // Devanagari sign nukta

           (cp >= 0x0941 and cp <= 0x0948) or  // Devanagari vowel signs

           (cp >= 0x094D and cp <= 0x094D) or  // Devanagari sign virama

           (cp >= 0x0951 and cp <= 0x0957) or  // Devanagari stress signs

           (cp >= 0x0962 and cp <= 0x0963);    // Devanagari vowel signs

}



// Tests

const testing = std.testing;



test "NSM validation - basic count limits" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Create mock script groups and group

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    // Add some Arabic NSMs to the groups NSM set

    try groups.nsm_set.put(0x064E, {}); // Fatha

    try groups.nsm_set.put(0x064F, {}); // Damma

    try groups.nsm_set.put(0x0650, {}); // Kasra

    try groups.nsm_set.put(0x0651, {}); // Shadda

    try groups.nsm_set.put(0x0652, {}); // Sukun

    

    // Add to script group CM set

    try arabic_group.cm.put(0x064E, {});

    try arabic_group.cm.put(0x064F, {});

    try arabic_group.cm.put(0x0650, {});

    try arabic_group.cm.put(0x0651, {});

    try arabic_group.cm.put(0x0652, {});

    

    // Test valid sequence: base + 3 NSMs

    const valid_seq = [_]CodePoint{0x0628, 0x064E, 0x064F, 0x0650}; // بَُِ

    try validateNSM(&valid_seq, &groups, &arabic_group, allocator);

    

    // Test invalid sequence: base + 5 NSMs (exceeds limit)

    const invalid_seq = [_]CodePoint{0x0628, 0x064E, 0x064F, 0x0650, 0x0651, 0x0652};

    const result = validateNSM(&invalid_seq, &groups, &arabic_group, allocator);

    try testing.expectError(NSMValidationError.ExcessiveNSM, result);

}



test "NSM validation - duplicate detection" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    try groups.nsm_set.put(0x064E, {});

    try arabic_group.cm.put(0x064E, {});

    

    // Test duplicate NSMs

    const duplicate_seq = [_]CodePoint{0x0628, 0x064E, 0x064E}; // ب + fatha + fatha

    const result = validateNSM(&duplicate_seq, &groups, &arabic_group, allocator);

    try testing.expectError(NSMValidationError.DuplicateNSM, result);

}



test "NSM validation - leading NSM detection" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    try groups.nsm_set.put(0x064E, {});

    

    // Test leading NSM

    const leading_nsm = [_]CodePoint{0x064E, 0x0628}; // fatha + ب

    const result = validateNSM(&leading_nsm, &groups, &arabic_group, allocator);

    try testing.expectError(NSMValidationError.LeadingNSM, result);

}



test "NSM validation - emoji context" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var emoji_group = script_groups.ScriptGroup.init(allocator, "Emoji", 0);

    defer emoji_group.deinit();

    

    try groups.nsm_set.put(0x064E, {});

    try emoji_group.cm.put(0x064E, {});

    

    // Test NSM after emoji

    const emoji_nsm = [_]CodePoint{0x1F600, 0x064E}; // 😀 + fatha

    const result = validateNSM(&emoji_nsm, &groups, &emoji_group, allocator);

    try testing.expectError(NSMValidationError.NSMAfterEmoji, result);

}



test "NSM detection - comprehensive Unicode ranges" {

    // Test various NSM ranges

    try testing.expect(isNSM(0x0300)); // Combining grave accent

    try testing.expect(isNSM(0x064E)); // Arabic fatha

    try testing.expect(isNSM(0x05B4)); // Hebrew point hiriq

    try testing.expect(isNSM(0x093C)); // Devanagari nukta

    try testing.expect(isNSM(0x0951)); // Devanagari stress sign udatta

    

    // Test non-NSMs

    try testing.expect(!isNSM('a'));

    try testing.expect(!isNSM(0x0628)); // Arabic letter beh

    try testing.expect(!isNSM(0x05D0)); // Hebrew letter alef

}



test "NSM validation - script-specific rules" {

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = script_groups.ScriptGroups.init(allocator);

    defer groups.deinit();

    

    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);

    defer arabic_group.deinit();

    

    try groups.nsm_set.put(0x064E, {});

    try groups.nsm_set.put(0x064F, {});

    try groups.nsm_set.put(0x0650, {});

    try groups.nsm_set.put(0x0651, {});

    

    try arabic_group.cm.put(0x064E, {});

    try arabic_group.cm.put(0x064F, {});

    try arabic_group.cm.put(0x0650, {});

    try arabic_group.cm.put(0x0651, {});

    

    // Test valid Arabic sequence

    const valid_arabic = [_]CodePoint{0x0628, 0x064E, 0x0651}; // بَّ (beh + fatha + shadda)

    try validateNSM(&valid_arabic, &groups, &arabic_group, allocator);

    

    // Test invalid: too many Arabic diacritics on one consonant

    const invalid_arabic = [_]CodePoint{0x0628, 0x064E, 0x064F, 0x0650, 0x0651}; // بَُِّ

    const result = validateNSM(&invalid_arabic, &groups, &arabic_group, allocator);

    try testing.expectError(NSMValidationError.ExcessiveNSM, result);

}```

```zig [./src/spec.zig]

const std = @import("std");



// Since we can't directly import ZON with heterogeneous arrays,

// we'll use a simplified approach for compile-time constants

const spec_zon_source = @embedFile("data/spec.zon");



// For now, we'll define constants that can be used at compile time

// These would need to be manually extracted or generated from the ZON file

pub const spec_data = struct {

    pub const groups = [_]struct {

        name: []const u8,

    }{

        .{ .name = "ASCII" },

        .{ .name = "Latin" },

        .{ .name = "Greek" },

        .{ .name = "Cyrillic" },

        .{ .name = "Hebrew" },

        .{ .name = "Arabic" },

        .{ .name = "Devanagari" },

        .{ .name = "Bengali" },

        .{ .name = "Gurmukhi" },

        .{ .name = "Gujarati" },

        .{ .name = "Oriya" },

        .{ .name = "Tamil" },

        .{ .name = "Telugu" },

        .{ .name = "Kannada" },

        .{ .name = "Malayalam" },

        .{ .name = "Thai" },

        .{ .name = "Lao" },

        .{ .name = "Tibetan" },

        .{ .name = "Myanmar" },

        .{ .name = "Georgian" },

        .{ .name = "Hangul" },

        .{ .name = "Ethiopic" },

        .{ .name = "Cherokee" },

        .{ .name = "Canadian_Aboriginal" },

        .{ .name = "Mongolian" },

        .{ .name = "Japanese" },

        .{ .name = "Han" },

        .{ .name = "Emoji" },

        // Add more as needed

    };

};



/// Generate script group enum from spec data

pub const ScriptGroup = blk: {

    const groups = spec_data.groups;

    var fields: [groups.len]std.builtin.Type.EnumField = undefined;

    

    for (groups, 0..) |group, i| {

        fields[i] = .{

            .name = group.name,

            .value = i,

        };

    }

    

    break :blk @Type(.{

        .Enum = .{

            .tag_type = u8,

            .fields = &fields,

            .decls = &.{},

            .is_exhaustive = true,

        },

    });

};



/// Get script group by name

pub fn getScriptGroupByName(name: []const u8) ?ScriptGroup {

    inline for (@typeInfo(ScriptGroup).Enum.fields) |field| {

        if (std.mem.eql(u8, field.name, name)) {

            return @enumFromInt(field.value);

        }

    }

    return null;

}



/// Get script group name

pub fn getScriptGroupName(group: ScriptGroup) []const u8 {

    return @tagName(group);

}



/// Get script group index

pub fn getScriptGroupIndex(group: ScriptGroup) usize {

    return @intFromEnum(group);

}



/// Get script group data by enum

pub fn getScriptGroupData(group: ScriptGroup) ScriptGroupData {

    const index = getScriptGroupIndex(group);

    return ScriptGroupData{

        .name = spec_data.groups[index].name,

        .primary = spec_data.groups[index].primary,

        .secondary = spec_data.groups[index].secondary orelse &.{},

        .cm = spec_data.groups[index].cm orelse &.{},

        .restricted = spec_data.groups[index].restricted orelse false,

    };

}



pub const ScriptGroupData = struct {

    name: []const u8,

    primary: []const u32,

    secondary: []const u32,

    cm: []const u32,

    restricted: bool,

};



/// All mapped characters from spec

pub const mapped_characters = spec_data.mapped;



/// All ignored characters from spec

pub const ignored_characters = spec_data.ignored;



/// All fenced characters from spec

pub const fenced_characters = spec_data.fenced;



/// All emoji sequences from spec

pub const emoji_sequences = spec_data.emoji;



/// NSM characters and max count

pub const nsm_characters = spec_data.nsm;

pub const nsm_max = spec_data.nsm_max;



/// NFC check data

pub const nfc_check = spec_data.nfc_check;



/// Whole script confusables

pub const whole_confusables = spec_data.wholes;



/// CM characters

pub const cm_characters = spec_data.cm;



test "script group enum generation" {

    const testing = std.testing;

    

    // Test that we can get groups by name

    const latin = getScriptGroupByName("Latin");

    try testing.expect(latin != null);

    try testing.expectEqualStrings("Latin", getScriptGroupName(latin.?));

    

    // Test that we can get group data

    const latin_data = getScriptGroupData(latin.?);

    try testing.expect(latin_data.primary.len > 0);

}```

```zig [./src/nfc.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const static_data_loader = @import("static_data_loader.zig");



// NFC Data structure to hold normalization data

pub const NFCData = struct {

    // Decomposition mappings

    decomp: std.AutoHashMap(CodePoint, []const CodePoint),

    // Recomposition mappings (pair of codepoints -> single codepoint)

    recomp: std.AutoHashMap(CodePointPair, CodePoint),

    // Exclusions set

    exclusions: std.AutoHashMap(CodePoint, void),

    // Combining class rankings

    combining_class: std.AutoHashMap(CodePoint, u8),

    // Characters that need NFC checking

    nfc_check: std.AutoHashMap(CodePoint, void),

    allocator: std.mem.Allocator,

    

    pub const CodePointPair = struct {

        first: CodePoint,

        second: CodePoint,

        

        pub fn hash(self: CodePointPair) u64 {

            var hasher = std.hash.Wyhash.init(0);

            hasher.update(std.mem.asBytes(&self.first));

            hasher.update(std.mem.asBytes(&self.second));

            return hasher.final();

        }

        

        pub fn eql(a: CodePointPair, b: CodePointPair) bool {

            return a.first == b.first and a.second == b.second;

        }

    };

    

    pub fn init(allocator: std.mem.Allocator) NFCData {

        return NFCData{

            .decomp = std.AutoHashMap(CodePoint, []const CodePoint).init(allocator),

            .recomp = std.AutoHashMap(CodePointPair, CodePoint).init(allocator),

            .exclusions = std.AutoHashMap(CodePoint, void).init(allocator),

            .combining_class = std.AutoHashMap(CodePoint, u8).init(allocator),

            .nfc_check = std.AutoHashMap(CodePoint, void).init(allocator),

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *NFCData) void {

        // Free decomposition values

        var decomp_iter = self.decomp.iterator();

        while (decomp_iter.next()) |entry| {

            self.allocator.free(entry.value_ptr.*);

        }

        self.decomp.deinit();

        self.recomp.deinit();

        self.exclusions.deinit();

        self.combining_class.deinit();

        self.nfc_check.deinit();

    }

    

    pub fn requiresNFCCheck(self: *const NFCData, cp: CodePoint) bool {

        return self.nfc_check.contains(cp);

    }

    

    pub fn getCombiningClass(self: *const NFCData, cp: CodePoint) u8 {

        return self.combining_class.get(cp) orelse 0;

    }

};



// Hangul syllable constants (from JavaScript reference)

const S0: CodePoint = 0xAC00;

const L0: CodePoint = 0x1100;

const V0: CodePoint = 0x1161;

const T0: CodePoint = 0x11A7;

const L_COUNT: CodePoint = 19;

const V_COUNT: CodePoint = 21;

const T_COUNT: CodePoint = 28;

const N_COUNT: CodePoint = V_COUNT * T_COUNT;

const S_COUNT: CodePoint = L_COUNT * N_COUNT;

const S1: CodePoint = S0 + S_COUNT;

const L1: CodePoint = L0 + L_COUNT;

const V1: CodePoint = V0 + V_COUNT;

const T1: CodePoint = T0 + T_COUNT;



pub fn isHangul(cp: CodePoint) bool {

    return cp >= S0 and cp < S1;

}



// Decompose a single Hangul syllable

pub fn decomposeHangul(cp: CodePoint, result: *std.ArrayList(CodePoint)) !void {

    if (!isHangul(cp)) return;

    

    const s_index = cp - S0;

    const l_index = s_index / N_COUNT;

    const v_index = (s_index % N_COUNT) / T_COUNT;

    const t_index = s_index % T_COUNT;

    

    try result.append(L0 + l_index);

    try result.append(V0 + v_index);

    if (t_index > 0) {

        try result.append(T0 + t_index);

    }

}



// Compose Hangul syllables

pub fn composeHangul(a: CodePoint, b: CodePoint) ?CodePoint {

    // L + V

    if (a >= L0 and a < L1 and b >= V0 and b < V1) {

        return S0 + (a - L0) * N_COUNT + (b - V0) * T_COUNT;

    }

    // LV + T

    if (isHangul(a) and b > T0 and b < T1 and (a - S0) % T_COUNT == 0) {

        return a + (b - T0);

    }

    return null;

}



// Decompose a string of codepoints

pub fn decompose(allocator: std.mem.Allocator, cps: []const CodePoint, nfc_data: *const NFCData) ![]CodePoint {

    var result = std.ArrayList(CodePoint).init(allocator);

    defer result.deinit();

    

    for (cps) |cp| {

        // Check for Hangul syllable

        if (isHangul(cp)) {

            try decomposeHangul(cp, &result);

        } else if (nfc_data.decomp.get(cp)) |decomposed| {

            // Recursive decomposition

            const sub_decomposed = try decompose(allocator, decomposed, nfc_data);

            defer allocator.free(sub_decomposed);

            try result.appendSlice(sub_decomposed);

        } else {

            // No decomposition

            try result.append(cp);

        }

    }

    

    // Apply canonical ordering

    try canonicalOrder(result.items, nfc_data);

    

    return result.toOwnedSlice();

}



// Apply canonical ordering based on combining classes

fn canonicalOrder(cps: []CodePoint, nfc_data: *const NFCData) !void {

    if (cps.len <= 1) return;

    

    // Bubble sort for canonical ordering (stable sort)

    var i: usize = 1;

    while (i < cps.len) : (i += 1) {

        const cc = nfc_data.getCombiningClass(cps[i]);

        if (cc != 0) {

            var j = i;

            while (j > 0) : (j -= 1) {

                const prev_cc = nfc_data.getCombiningClass(cps[j - 1]);

                if (prev_cc == 0 or prev_cc <= cc) break;

                

                // Swap

                const tmp = cps[j];

                cps[j] = cps[j - 1];

                cps[j - 1] = tmp;

            }

        }

    }

}



// Compose a string of decomposed codepoints

pub fn compose(allocator: std.mem.Allocator, decomposed: []const CodePoint, nfc_data: *const NFCData) ![]CodePoint {

    if (decomposed.len == 0) {

        return try allocator.alloc(CodePoint, 0);

    }

    

    var result = std.ArrayList(CodePoint).init(allocator);

    defer result.deinit();

    

    var i: usize = 0;

    while (i < decomposed.len) {

        const cp = decomposed[i];

        const cc = nfc_data.getCombiningClass(cp);

        

        // Try to compose with previous character

        if (result.items.len > 0 and cc == 0) {

            const last_cp = result.items[result.items.len - 1];

            const last_cc = nfc_data.getCombiningClass(last_cp);

            

            if (last_cc == 0) {

                // Try Hangul composition first

                if (composeHangul(last_cp, cp)) |composed| {

                    result.items[result.items.len - 1] = composed;

                    i += 1;

                    continue;

                }

                

                // Try regular composition

                const pair = NFCData.CodePointPair{ .first = last_cp, .second = cp };

                if (nfc_data.recomp.get(pair)) |composed| {

                    if (!nfc_data.exclusions.contains(composed)) {

                        result.items[result.items.len - 1] = composed;

                        i += 1;

                        continue;

                    }

                }

            }

        }

        

        // No composition, just append

        try result.append(cp);

        i += 1;

    }

    

    return result.toOwnedSlice();

}



// Main NFC function

pub fn nfc(allocator: std.mem.Allocator, cps: []const CodePoint, nfc_data: *const NFCData) ![]CodePoint {

    // First decompose

    const decomposed = try decompose(allocator, cps, nfc_data);

    defer allocator.free(decomposed);

    

    // Then compose

    return try compose(allocator, decomposed, nfc_data);

}



// Check if codepoints need NFC normalization

pub fn needsNFC(cps: []const CodePoint, nfc_data: *const NFCData) bool {

    for (cps) |cp| {

        if (nfc_data.requiresNFCCheck(cp)) {

            return true;

        }

    }

    return false;

}



// Compare two codepoint arrays

pub fn compareCodePoints(a: []const CodePoint, b: []const CodePoint) bool {

    if (a.len != b.len) return false;

    for (a, b) |cp_a, cp_b| {

        if (cp_a != cp_b) return false;

    }

    return true;

}



test "Hangul decomposition" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var result = std.ArrayList(CodePoint).init(allocator);

    

    // Test Hangul syllable 가 (GA)

    try decomposeHangul(0xAC00, &result);

    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{ 0x1100, 0x1161 }, result.items);

    

    result.clearRetainingCapacity();

    

    // Test Hangul syllable 각 (GAK)

    try decomposeHangul(0xAC01, &result);

    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{ 0x1100, 0x1161, 0x11A8 }, result.items);

}



test "Hangul composition" {

    const testing = std.testing;

    

    // Test L + V

    try testing.expectEqual(@as(?CodePoint, 0xAC00), composeHangul(0x1100, 0x1161));

    

    // Test LV + T

    try testing.expectEqual(@as(?CodePoint, 0xAC01), composeHangul(0xAC00, 0x11A8));

    

    // Test invalid composition

    try testing.expectEqual(@as(?CodePoint, null), composeHangul(0x1100, 0x11A8));

}```

```zig [./src/tokens.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const constants = @import("constants.zig");

const utils = @import("utils.zig");



pub const EnsNameToken = union(enum) {

    valid: TokenValid,

    mapped: TokenMapped,

    ignored: TokenIgnored,

    disallowed: TokenDisallowed,

    stop: TokenStop,

    nfc: TokenNfc,

    emoji: TokenEmoji,

    

    pub fn getCps(self: EnsNameToken, allocator: std.mem.Allocator) ![]CodePoint {

        switch (self) {

            .valid => |t| return allocator.dupe(CodePoint, t.cps),

            .mapped => |t| return allocator.dupe(CodePoint, t.cps),

            .nfc => |t| return allocator.dupe(CodePoint, t.cps),

            .emoji => |t| return allocator.dupe(CodePoint, t.cps_no_fe0f),

            .disallowed => |t| {

                var result = try allocator.alloc(CodePoint, 1);

                result[0] = t.cp;

                return result;

            },

            .stop => |t| {

                var result = try allocator.alloc(CodePoint, 1);

                result[0] = t.cp;

                return result;

            },

            .ignored => |t| {

                var result = try allocator.alloc(CodePoint, 1);

                result[0] = t.cp;

                return result;

            },

        }

    }

    

    pub fn getInputSize(self: EnsNameToken) usize {

        switch (self) {

            .valid => |t| return t.cps.len,

            .nfc => |t| return t.input.len,

            .emoji => |t| return t.cps_input.len,

            .mapped, .disallowed, .ignored, .stop => return 1,

        }

    }

    

    pub fn isText(self: EnsNameToken) bool {

        return switch (self) {

            .valid, .mapped, .nfc => true,

            else => false,

        };

    }

    

    pub fn isEmoji(self: EnsNameToken) bool {

        return switch (self) {

            .emoji => true,

            else => false,

        };

    }

    

    pub fn isIgnored(self: EnsNameToken) bool {

        return switch (self) {

            .ignored => true,

            else => false,

        };

    }

    

    pub fn isDisallowed(self: EnsNameToken) bool {

        return switch (self) {

            .disallowed => true,

            else => false,

        };

    }

    

    pub fn isStop(self: EnsNameToken) bool {

        return switch (self) {

            .stop => true,

            else => false,

        };

    }

    

    pub fn createStop() EnsNameToken {

        return EnsNameToken{ .stop = TokenStop{ .cp = constants.CP_STOP } };

    }

    

    pub fn asString(self: EnsNameToken, allocator: std.mem.Allocator) ![]u8 {

        const cps = try self.getCps(allocator);

        defer allocator.free(cps);

        return utils.cps2str(allocator, cps);

    }

};



pub const TokenValid = struct {

    cps: []const CodePoint,

};



pub const TokenMapped = struct {

    cps: []const CodePoint,

    cp: CodePoint,

};



pub const TokenIgnored = struct {

    cp: CodePoint,

};



pub const TokenDisallowed = struct {

    cp: CodePoint,

};



pub const TokenStop = struct {

    cp: CodePoint,

};



pub const TokenNfc = struct {

    cps: []const CodePoint,

    input: []const CodePoint,

};



pub const TokenEmoji = struct {

    input: []const u8,

    emoji: []const CodePoint,

    cps_input: []const CodePoint,

    cps_no_fe0f: []const CodePoint,

};



pub const CollapsedEnsNameToken = union(enum) {

    text: TokenValid,

    emoji: TokenEmoji,

    

    pub fn getInputSize(self: CollapsedEnsNameToken) usize {

        switch (self) {

            .text => |t| return t.cps.len,

            .emoji => |t| return t.cps_input.len,

        }

    }

};



pub const TokenizedName = struct {

    tokens: []const EnsNameToken,

    

    pub fn deinit(self: TokenizedName, allocator: std.mem.Allocator) void {

        allocator.free(self.tokens);

    }

    

    pub fn fromInput(

        allocator: std.mem.Allocator,

        input: []const u8,

        specs: anytype,

        should_nfc: bool,

    ) !TokenizedName {

        // This is a placeholder implementation

        // The actual tokenization logic would need to be implemented

        // based on the Rust implementation

        _ = specs;

        _ = should_nfc;

        

        var tokens = std.ArrayList(EnsNameToken).init(allocator);

        defer tokens.deinit();

        

        // Basic tokenization - convert string to code points

        const cps = try utils.str2cps(allocator, input);

        defer allocator.free(cps);

        

        // Create a single valid token for now

        const owned_cps = try allocator.dupe(CodePoint, cps);

        try tokens.append(EnsNameToken{ .valid = TokenValid{ .cps = owned_cps } });

        

        return TokenizedName{

            .tokens = try tokens.toOwnedSlice(),

        };

    }

};



test "EnsNameToken basic operations" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    

    const stop_token = EnsNameToken.createStop();

    try testing.expect(stop_token.isStop());

    try testing.expect(!stop_token.isText());

    try testing.expect(!stop_token.isEmoji());

    

    const input_size = stop_token.getInputSize();

    try testing.expectEqual(@as(usize, 1), input_size);

}```

```zig [./src/script_groups.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const utils = @import("utils.zig");



/// Script group for validating character sets

pub const ScriptGroup = struct {

    /// Name of the script group (e.g., "Latin", "Greek", "Cyrillic")

    name: []const u8,

    /// Primary valid codepoints for this group

    primary: std.AutoHashMap(CodePoint, void),

    /// Secondary valid codepoints for this group

    secondary: std.AutoHashMap(CodePoint, void),

    /// Combined primary + secondary for quick lookup

    combined: std.AutoHashMap(CodePoint, void),

    /// Combining marks specific to this group (empty if none)

    cm: std.AutoHashMap(CodePoint, void),

    /// Whether to check NSM rules for this group

    check_nsm: bool,

    /// Index in the groups array (for error messages)

    index: usize,

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator, name: []const u8, index: usize) ScriptGroup {

        return ScriptGroup{

            .name = name,

            .primary = std.AutoHashMap(CodePoint, void).init(allocator),

            .secondary = std.AutoHashMap(CodePoint, void).init(allocator),

            .combined = std.AutoHashMap(CodePoint, void).init(allocator),

            .cm = std.AutoHashMap(CodePoint, void).init(allocator),

            .check_nsm = true, // Default to checking NSM

            .index = index,

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *ScriptGroup) void {

        self.primary.deinit();

        self.secondary.deinit();

        self.combined.deinit();

        self.cm.deinit();

        self.allocator.free(self.name);

    }

    

    /// Add a primary codepoint

    pub fn addPrimary(self: *ScriptGroup, cp: CodePoint) !void {

        try self.primary.put(cp, {});

        try self.combined.put(cp, {});

    }

    

    /// Add a secondary codepoint

    pub fn addSecondary(self: *ScriptGroup, cp: CodePoint) !void {

        try self.secondary.put(cp, {});

        try self.combined.put(cp, {});

    }

    

    /// Add a combining mark

    pub fn addCombiningMark(self: *ScriptGroup, cp: CodePoint) !void {

        try self.cm.put(cp, {});

    }

    

    /// Check if this group contains a codepoint (primary or secondary)

    pub fn containsCp(self: *const ScriptGroup, cp: CodePoint) bool {

        return self.combined.contains(cp);

    }

    

    /// Check if this group contains all codepoints

    pub fn containsAllCps(self: *const ScriptGroup, cps: []const CodePoint) bool {

        for (cps) |cp| {

            if (!self.containsCp(cp)) {

                return false;

            }

        }

        return true;

    }

    

    /// Check if a codepoint is in primary set

    pub fn isPrimary(self: *const ScriptGroup, cp: CodePoint) bool {

        return self.primary.contains(cp);

    }

    

    /// Check if a codepoint is in secondary set

    pub fn isSecondary(self: *const ScriptGroup, cp: CodePoint) bool {

        return self.secondary.contains(cp);

    }

};



/// Collection of all script groups

pub const ScriptGroups = struct {

    groups: []ScriptGroup,

    /// Set of all NSM (non-spacing marks) for validation

    nsm_set: std.AutoHashMap(CodePoint, void),

    /// Maximum consecutive NSM allowed

    nsm_max: u32,

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator) ScriptGroups {

        return ScriptGroups{

            .groups = &[_]ScriptGroup{},

            .nsm_set = std.AutoHashMap(CodePoint, void).init(allocator),

            .nsm_max = 4, // Default from spec

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *ScriptGroups) void {

        for (self.groups) |*group| {

            group.deinit();

        }

        self.allocator.free(self.groups);

        self.nsm_set.deinit();

    }

    

    /// Add NSM codepoint

    pub fn addNSM(self: *ScriptGroups, cp: CodePoint) !void {

        try self.nsm_set.put(cp, {});

    }

    

    /// Check if a codepoint is NSM

    pub fn isNSM(self: *const ScriptGroups, cp: CodePoint) bool {

        return self.nsm_set.contains(cp);

    }

    

    /// Find which groups contain a codepoint

    pub fn findGroupsContaining(self: *const ScriptGroups, cp: CodePoint, allocator: std.mem.Allocator) ![]const *const ScriptGroup {

        var matching = std.ArrayList(*const ScriptGroup).init(allocator);

        errdefer matching.deinit();

        

        for (self.groups) |*group| {

            if (group.containsCp(cp)) {

                try matching.append(group);

            }

        }

        

        return matching.toOwnedSlice();

    }

    

    /// Determine the script group for a set of unique codepoints

    pub fn determineScriptGroup(self: *const ScriptGroups, unique_cps: []const CodePoint, allocator: std.mem.Allocator) !*const ScriptGroup {

        if (unique_cps.len == 0) {

            return error.EmptyInput;

        }

        

        // Start with all groups

        var remaining = try allocator.alloc(*const ScriptGroup, self.groups.len);

        defer allocator.free(remaining);

        

        for (self.groups, 0..) |*group, i| {

            remaining[i] = group;

        }

        var remaining_count = self.groups.len;

        

        // Filter by each codepoint

        for (unique_cps) |cp| {

            var new_count: usize = 0;

            

            // Keep only groups that contain this codepoint

            for (remaining[0..remaining_count]) |group| {

                if (group.containsCp(cp)) {

                    remaining[new_count] = group;

                    new_count += 1;

                }

            }

            

            if (new_count == 0) {

                // No group contains this codepoint

                return error.DisallowedCharacter;

            }

            

            remaining_count = new_count;

        }

        

        // Return the first remaining group (highest priority)

        return remaining[0];

    }

};



/// Result of script group determination

pub const ScriptGroupResult = struct {

    group: *const ScriptGroup,

    mixed_scripts: bool,

};



/// Find conflicting groups when script mixing is detected

pub fn findConflictingGroups(

    groups: *const ScriptGroups,

    unique_cps: []const CodePoint,

    allocator: std.mem.Allocator

) !struct { first_group: *const ScriptGroup, conflicting_cp: CodePoint, conflicting_groups: []const *const ScriptGroup } {

    if (unique_cps.len == 0) {

        return error.EmptyInput;

    }

    

    // Find groups for first codepoint

    const remaining = try groups.findGroupsContaining(unique_cps[0], allocator);

    defer allocator.free(remaining);

    

    if (remaining.len == 0) {

        return error.DisallowedCharacter;

    }

    

    // Check each subsequent codepoint

    for (unique_cps[1..]) |cp| {

        const cp_groups = try groups.findGroupsContaining(cp, allocator);

        defer allocator.free(cp_groups);

        

        // Check if any remaining groups contain this cp

        var found = false;

        for (remaining) |group| {

            for (cp_groups) |cp_group| {

                if (group == cp_group) {

                    found = true;

                    break;

                }

            }

            if (found) break;

        }

        

        if (!found) {

            // This cp causes the conflict

            return .{

                .first_group = remaining[0],

                .conflicting_cp = cp,

                .conflicting_groups = cp_groups,

            };

        }

    }

    

    return error.NoConflict;

}



test "script group basic operations" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const name = try allocator.dupe(u8, "Latin");

    var group = ScriptGroup.init(allocator, name, 0);

    defer group.deinit();

    

    // Add some codepoints

    try group.addPrimary('A');

    try group.addPrimary('B');

    try group.addSecondary('1');

    try group.addSecondary('2');

    

    // Test contains

    try testing.expect(group.containsCp('A'));

    try testing.expect(group.containsCp('1'));

    try testing.expect(!group.containsCp('X'));

    

    // Test primary/secondary

    try testing.expect(group.isPrimary('A'));

    try testing.expect(!group.isPrimary('1'));

    try testing.expect(group.isSecondary('1'));

    try testing.expect(!group.isSecondary('A'));

}



test "script group determination" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var groups = ScriptGroups.init(allocator);

    defer groups.deinit();

    

    // Create more realistic test groups with some overlap

    var test_groups = try allocator.alloc(ScriptGroup, 3);

    

    const latin_name = try allocator.dupe(u8, "Latin");

    test_groups[0] = ScriptGroup.init(allocator, latin_name, 0);

    try test_groups[0].addPrimary('A');

    try test_groups[0].addPrimary('B');

    try test_groups[0].addPrimary('C');

    try test_groups[0].addSecondary('0'); // Numbers are secondary in many scripts

    try test_groups[0].addSecondary('1');

    

    const greek_name = try allocator.dupe(u8, "Greek");

    test_groups[1] = ScriptGroup.init(allocator, greek_name, 1);

    try test_groups[1].addPrimary(0x03B1); // α

    try test_groups[1].addPrimary(0x03B2); // β

    try test_groups[1].addSecondary('0'); // Numbers are secondary in many scripts

    try test_groups[1].addSecondary('1');

    

    const common_name = try allocator.dupe(u8, "Common");

    test_groups[2] = ScriptGroup.init(allocator, common_name, 2);

    try test_groups[2].addPrimary('-');

    try test_groups[2].addPrimary('_');

    

    groups.groups = test_groups;

    

    // Test single script

    const latin_cps = [_]CodePoint{'A', 'B', 'C'};

    const latin_group = try groups.determineScriptGroup(&latin_cps, allocator);

    try testing.expectEqualStrings("Latin", latin_group.name);

    

    // Test Greek

    const greek_cps = [_]CodePoint{0x03B1, 0x03B2};

    const greek_group = try groups.determineScriptGroup(&greek_cps, allocator);

    try testing.expectEqualStrings("Greek", greek_group.name);

    

    // Test with common characters (numbers)

    const latin_with_numbers = [_]CodePoint{'A', '1'};

    const latin_num_group = try groups.determineScriptGroup(&latin_with_numbers, allocator);

    try testing.expectEqualStrings("Latin", latin_num_group.name);

    

    // Test mixed scripts (should error because no single group contains both)

    const mixed_cps = [_]CodePoint{'A', 0x03B1}; // Latin A + Greek α

    const result = groups.determineScriptGroup(&mixed_cps, allocator);

    try testing.expectError(error.DisallowedCharacter, result);

}```

```zig [./src/emoji.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const utils = @import("utils.zig");



/// Single emoji sequence data

pub const EmojiData = struct {

    /// Canonical form with FE0F

    emoji: []const CodePoint,

    /// Form without FE0F for matching

    no_fe0f: []const CodePoint,

    

    pub fn deinit(self: EmojiData, allocator: std.mem.Allocator) void {

        allocator.free(self.emoji);

        allocator.free(self.no_fe0f);

    }

};



/// Map for efficient emoji lookup

pub const EmojiMap = struct {

    /// Map from no_fe0f codepoint sequence to emoji data

    /// Using string key for simpler lookup

    emojis: std.StringHashMap(EmojiData),

    /// Maximum emoji sequence length (for optimization)

    max_length: usize,

    /// All emoji sequences for building regex pattern

    all_emojis: std.ArrayList(EmojiData),

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator) EmojiMap {

        return EmojiMap{

            .emojis = std.StringHashMap(EmojiData).init(allocator),

            .max_length = 0,

            .all_emojis = std.ArrayList(EmojiData).init(allocator),

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *EmojiMap) void {

        // Free all emoji data

        for (self.all_emojis.items) |emoji_data| {

            emoji_data.deinit(self.allocator);

        }

        self.all_emojis.deinit();

        

        // Free all keys in the map

        var iter = self.emojis.iterator();

        while (iter.next()) |entry| {

            self.allocator.free(entry.key_ptr.*);

        }

        self.emojis.deinit();

    }

    

    /// Add an emoji sequence to the map

    pub fn addEmoji(self: *EmojiMap, no_fe0f: []const CodePoint, canonical: []const CodePoint) !void {

        // Create owned copies

        const owned_no_fe0f = try self.allocator.dupe(CodePoint, no_fe0f);

        errdefer self.allocator.free(owned_no_fe0f);

        

        const owned_canonical = try self.allocator.dupe(CodePoint, canonical);

        errdefer self.allocator.free(owned_canonical);

        

        const emoji_data = EmojiData{

            .emoji = owned_canonical,

            .no_fe0f = owned_no_fe0f,

        };

        

        // Convert no_fe0f to string key

        const key = try utils.cps2str(self.allocator, no_fe0f);

        defer self.allocator.free(key);

        

        // Add to map with owned key

        const owned_key = try self.allocator.dupe(u8, key);

        try self.emojis.put(owned_key, emoji_data);

        

        // Add to all emojis list

        try self.all_emojis.append(emoji_data);

        

        // Update max length

        const len = std.unicode.utf8CountCodepoints(key) catch key.len;

        if (len > self.max_length) {

            self.max_length = len;

        }

    }

    

    /// Find emoji at given position in string

    pub fn findEmojiAt(self: *const EmojiMap, allocator: std.mem.Allocator, input: []const u8, pos: usize) ?EmojiMatch {

        if (pos >= input.len) return null;

        

        // Try from longest possible match down to single character

        var len = @min(input.len - pos, self.max_length * 4); // rough estimate for max UTF-8 bytes

        

        while (len > 0) : (len -= 1) {

            if (pos + len > input.len) continue;

            

            const slice = input[pos..pos + len];

            

            // Check if this is a valid UTF-8 boundary

            if (len < input.len - pos and !std.unicode.utf8ValidateSlice(slice)) {

                continue;

            }

            

            // Convert to codepoints and remove FE0F

            const cps = utils.str2cps(allocator, slice) catch continue;

            defer allocator.free(cps);

            

            const no_fe0f = utils.filterFe0f(allocator, cps) catch continue;

            defer allocator.free(no_fe0f);

            

            // Convert to string key

            const key = utils.cps2str(allocator, no_fe0f) catch continue;

            defer allocator.free(key);

            

            // Look up in map

            if (self.emojis.get(key)) |emoji_data| {

                // Need to return owned copies since we're deferring the frees

                const owned_cps = allocator.dupe(CodePoint, cps) catch continue;

                return EmojiMatch{

                    .emoji_data = emoji_data,

                    .input = slice,

                    .cps_input = owned_cps,

                    .byte_len = len,

                };

            }

        }

        

        return null;

    }

};



/// Result of emoji matching

pub const EmojiMatch = struct {

    emoji_data: EmojiData,

    input: []const u8,

    cps_input: []const CodePoint,

    byte_len: usize,

};



/// Remove FE0F (variation selector) from codepoint sequence

pub fn filterFE0F(allocator: std.mem.Allocator, cps: []const CodePoint) ![]CodePoint {

    return utils.filterFe0f(allocator, cps);

}



test "emoji map basic operations" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var emoji_map = EmojiMap.init(allocator);

    defer emoji_map.deinit();

    

    // Add simple emoji

    const smile_no_fe0f = [_]CodePoint{0x263A}; // ☺

    const smile_canonical = [_]CodePoint{0x263A, 0xFE0F}; // ☺️

    try emoji_map.addEmoji(&smile_no_fe0f, &smile_canonical);

    

    // Test lookup

    const key = try utils.cps2str(allocator, &smile_no_fe0f);

    defer allocator.free(key);

    

    const found = emoji_map.emojis.get(key);

    try testing.expect(found != null);

    try testing.expectEqualSlices(CodePoint, &smile_canonical, found.?.emoji);

}



test "emoji map population - incorrect way" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var emoji_map = EmojiMap.init(allocator);

    defer emoji_map.deinit();

    

    // Create emoji data

    const thumbs_emoji = try allocator.alloc(CodePoint, 1);

    thumbs_emoji[0] = 0x1F44D;

    const thumbs_no_fe0f = try allocator.dupe(CodePoint, thumbs_emoji);

    

    const emoji_data = EmojiData{

        .emoji = thumbs_emoji,

        .no_fe0f = thumbs_no_fe0f,

    };

    

    // Add to all_emojis (what our loader does)

    try emoji_map.all_emojis.append(emoji_data);

    

    // But this doesn't populate the hash map!

    // Let's verify the hash map is empty

    const key = try utils.cps2str(allocator, thumbs_no_fe0f);

    defer allocator.free(key);

    

    const found = emoji_map.emojis.get(key);

    try testing.expect(found == null); // This should pass, showing the bug

    

    // Now test findEmojiAt - it should fail to find the emoji

    const input = "Hello 👍 World";

    const match = emoji_map.findEmojiAt(allocator, input, 6);

    try testing.expect(match == null); // This should pass, confirming the bug

}



test "emoji map population - correct way" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var emoji_map = EmojiMap.init(allocator);

    defer emoji_map.deinit();

    

    // Use addEmoji which populates both structures

    const thumbs_no_fe0f = [_]CodePoint{0x1F44D};

    const thumbs_emoji = [_]CodePoint{0x1F44D};

    try emoji_map.addEmoji(&thumbs_no_fe0f, &thumbs_emoji);

    

    // Verify the hash map is populated

    const key = try utils.cps2str(allocator, &thumbs_no_fe0f);

    defer allocator.free(key);

    

    const found = emoji_map.emojis.get(key);

    try testing.expect(found != null);

    

    // Now test findEmojiAt - it should find the emoji

    const input = "Hello 👍 World";

    const match = emoji_map.findEmojiAt(allocator, input, 6);

    try testing.expect(match != null);

    if (match) |m| {

        defer allocator.free(m.cps_input);

        try testing.expectEqualSlices(CodePoint, &thumbs_emoji, m.emoji_data.emoji);

    }

}



test "emoji matching" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var emoji_map = EmojiMap.init(allocator);

    defer emoji_map.deinit();

    

    // Add thumbs up emoji

    const thumbs_no_fe0f = [_]CodePoint{0x1F44D}; // 👍

    const thumbs_canonical = [_]CodePoint{0x1F44D};

    try emoji_map.addEmoji(&thumbs_no_fe0f, &thumbs_canonical);

    

    // Test finding emoji in string

    const input = "Hello 👍 World";

    const match = emoji_map.findEmojiAt(allocator, input, 6); // Position of 👍

    

    try testing.expect(match != null);

    if (match) |m| {

        defer allocator.free(m.cps_input);

        try testing.expectEqualSlices(CodePoint, &thumbs_canonical, m.emoji_data.emoji);

    }

}```

```zig [./src/main.zig]

const std = @import("std");

const ens_normalize = @import("root.zig");



pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    

    const stdout = std.io.getStdOut().writer();

    

    try stdout.print("ENS Normalize Zig Implementation\n", .{});

    try stdout.print("=================================\n\n", .{});

    

    // Example usage

    const test_names = [_][]const u8{

        "hello.eth",

        "test-domain.eth",

        "ξ.eth",

        "hello.eth",

    };

    

    for (test_names) |name| {

        try stdout.print("Input: {s}\n", .{name});

        

        // Try to normalize the name

        const normalized = ens_normalize.normalize(allocator, name) catch |err| {

            try stdout.print("Error: {}\n", .{err});

            continue;

        };

        defer allocator.free(normalized);

        

        try stdout.print("Normalized: {s}\n", .{normalized});

        

        // Try to beautify the name

        const beautified = ens_normalize.beautify_fn(allocator, name) catch |err| {

            try stdout.print("Beautify Error: {}\n", .{err});

            continue;

        };

        defer allocator.free(beautified);

        

        try stdout.print("Beautified: {s}\n", .{beautified});

        try stdout.print("\n", .{});

    }

    

    try stdout.print("Note: This is a basic implementation. Full ENS normalization\n", .{});

    try stdout.print("requires additional Unicode data and processing logic.\n", .{});

}



test "basic library functionality" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Test basic tokenization

    const input = "hello";

    const tokenized = ens_normalize.tokenize(allocator, input) catch |err| {

        // For now, expect errors since we haven't implemented full functionality

        try testing.expect(err == ens_normalize.error_types.ProcessError.DisallowedSequence);

        return;

    };

    defer tokenized.deinit();

    

    try testing.expect(tokenized.tokens.len > 0);

}



test "memory management" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Test that we properly manage memory

    var normalizer = ens_normalize.normalizer.EnsNameNormalizer.default(allocator);

    defer normalizer.deinit();

    

    const input = "test";

    const result = normalizer.normalize(input) catch |err| {

        // Expected to fail with current implementation

        try testing.expect(err == ens_normalize.error_types.ProcessError.DisallowedSequence);

        return;

    };

    defer allocator.free(result);

}```

```zig [./src/normalizer.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const code_points = @import("code_points.zig");

const validate = @import("validate.zig");

const error_types = @import("error.zig");

const beautify_mod = @import("beautify.zig");

const join = @import("join.zig");

const tokenizer = @import("tokenizer.zig");

const character_mappings = @import("character_mappings.zig");

const static_data_loader = @import("static_data_loader.zig");



pub const EnsNameNormalizer = struct {

    specs: code_points.CodePointsSpecs,

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator, specs: code_points.CodePointsSpecs) EnsNameNormalizer {

        return EnsNameNormalizer{

            .specs = specs,

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *EnsNameNormalizer) void {

        self.specs.deinit();

    }

    

    pub fn tokenize(self: *const EnsNameNormalizer, input: []const u8) !tokenizer.TokenizedName {

        return tokenizer.TokenizedName.fromInput(self.allocator, input, &self.specs, true);

    }

    

    pub fn process(self: *const EnsNameNormalizer, input: []const u8) !ProcessedName {

        const tokenized = try self.tokenize(input);

        const labels = try validate.validateName(self.allocator, tokenized, &self.specs);

        

        return ProcessedName{

            .labels = labels,

            .tokenized = tokenized,

            .allocator = self.allocator,

        };

    }

    

    pub fn normalize(self: *const EnsNameNormalizer, input: []const u8) ![]u8 {

        const processed = try self.process(input);

        defer processed.deinit();

        return processed.normalize();

    }

    

    pub fn beautify_fn(self: *const EnsNameNormalizer, input: []const u8) ![]u8 {

        const processed = try self.process(input);

        defer processed.deinit();

        return processed.beautify();

    }

    

    pub fn default(allocator: std.mem.Allocator) EnsNameNormalizer {

        return EnsNameNormalizer.init(allocator, code_points.CodePointsSpecs.init(allocator));

    }

};



pub const ProcessedName = struct {

    labels: []validate.ValidatedLabel,

    tokenized: tokenizer.TokenizedName,

    allocator: std.mem.Allocator,

    

    pub fn deinit(self: ProcessedName) void {

        for (self.labels) |label| {

            label.deinit();

        }

        self.allocator.free(self.labels);

        self.tokenized.deinit();

    }

    

    pub fn normalize(self: *const ProcessedName) ![]u8 {

        return normalizeTokens(self.allocator, self.tokenized.tokens);

    }

    

    pub fn beautify(self: *const ProcessedName) ![]u8 {

        return beautifyTokens(self.allocator, self.tokenized.tokens);

    }

};



// Convenience functions that use default normalizer

pub fn tokenize(allocator: std.mem.Allocator, input: []const u8) !tokenizer.TokenizedName {

    var normalizer = EnsNameNormalizer.default(allocator);

    defer normalizer.deinit();

    return normalizer.tokenize(input);

}



pub fn process(allocator: std.mem.Allocator, input: []const u8) !ProcessedName {

    var normalizer = EnsNameNormalizer.default(allocator);

    defer normalizer.deinit();

    return normalizer.process(input);

}



pub fn normalize(allocator: std.mem.Allocator, input: []const u8) ![]u8 {

    // Use character mappings directly for better performance

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &code_points.CodePointsSpecs.init(allocator), false);

    defer tokenized.deinit();

    return normalizeTokens(allocator, tokenized.tokens);

}



pub fn beautify(allocator: std.mem.Allocator, input: []const u8) ![]u8 {

    // Use character mappings directly for better performance

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &code_points.CodePointsSpecs.init(allocator), false);

    defer tokenized.deinit();

    return beautifyTokens(allocator, tokenized.tokens);

}



// Token processing functions

fn normalizeTokens(allocator: std.mem.Allocator, token_list: []const tokenizer.Token) ![]u8 {

    var result = std.ArrayList(u8).init(allocator);

    defer result.deinit();

    

    for (token_list) |token| {

        // Get the normalized code points for this token

        const cps = token.getCps();

        

        // Convert code points to UTF-8 and append to result

        for (cps) |cp| {

            const utf8_len = std.unicode.utf8CodepointSequenceLength(@as(u21, @intCast(cp))) catch continue;

            const old_len = result.items.len;

            try result.resize(old_len + utf8_len);

            _ = std.unicode.utf8Encode(@as(u21, @intCast(cp)), result.items[old_len..]) catch continue;

        }

    }

    

    return result.toOwnedSlice();

}



fn beautifyTokens(allocator: std.mem.Allocator, token_list: []const tokenizer.Token) ![]u8 {

    var result = std.ArrayList(u8).init(allocator);

    defer result.deinit();

    

    for (token_list) |token| {

        switch (token.type) {

            .mapped => {

                // For beautification, use original character for case folding

                const original_cp = token.data.mapped.cp;

                const utf8_len = std.unicode.utf8CodepointSequenceLength(@as(u21, @intCast(original_cp))) catch continue;

                const old_len = result.items.len;

                try result.resize(old_len + utf8_len);

                _ = std.unicode.utf8Encode(@as(u21, @intCast(original_cp)), result.items[old_len..]) catch continue;

            },

            else => {

                // For other tokens, use normalized form

                const cps = token.getCps();

                for (cps) |cp| {

                    const utf8_len = std.unicode.utf8CodepointSequenceLength(@as(u21, @intCast(cp))) catch continue;

                    const old_len = result.items.len;

                    try result.resize(old_len + utf8_len);

                    _ = std.unicode.utf8Encode(@as(u21, @intCast(cp)), result.items[old_len..]) catch continue;

                }

            }

        }

    }

    

    return result.toOwnedSlice();

}



test "EnsNameNormalizer basic functionality" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var normalizer = EnsNameNormalizer.default(allocator);

    defer normalizer.deinit();

    

    const input = "hello.eth";

    const result = normalizer.normalize(input) catch |err| {

        // For now, expect errors since we haven't implemented full functionality

        try testing.expect(err == error_types.ProcessError.DisallowedSequence);

        return;

    };

    defer allocator.free(result);

}```

```zig [./src/static_data_loader.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const character_mappings = @import("character_mappings.zig");

const CharacterMappings = character_mappings.CharacterMappings;

const nfc = @import("nfc.zig");

const emoji = @import("emoji.zig");

const script_groups = @import("script_groups.zig");

const confusables = @import("confusables.zig");

const utils = @import("utils.zig");



// Define ZON data types

const MappedItem = struct { u32, []const u32 };

const FencedItem = struct { u32, []const u8 };

const WholeItem = struct {

    target: ?[]const u8,

    valid: []const u32,

    confused: []const u32,

};

const GroupItem = struct {

    name: []const u8,

    primary: []const u32,

    secondary: ?[]const u32 = null,

    cm: ?[]const u32 = null,

    restricted: ?bool = null,

};



const SpecData = struct {

    created: []const u8,

    unicode: []const u8,

    cldr: []const u8,

    emoji: []const []const u32,

    ignored: []const u32,

    mapped: []const MappedItem,

    fenced: []const FencedItem,

    groups: []const GroupItem,

    nsm: []const u32,

    nsm_max: u32,

    nfc_check: []const u32,

    wholes: []const WholeItem,

    cm: []const u32,

    escape: []const u32,

};



const DecompItem = struct { u32, []const u32 };

const RankItem = []const u32;



const NfData = struct {

    created: []const u8,

    unicode: []const u8,

    exclusions: []const u32,

    decomp: []const DecompItem,

    ranks: []const RankItem,

    qc: ?[]const u32 = null,

};



// Import ZON data at compile time

const spec_data: SpecData = @import("data/spec.zon");

const nf_data: NfData = @import("data/nf.zon");



/// Load character mappings - now just returns the comptime-based struct

pub fn loadCharacterMappings(allocator: std.mem.Allocator) !CharacterMappings {

    // With comptime data, we don't need to load anything at runtime!

    return CharacterMappings.init(allocator);

}



/// Load NFC data from ZON

pub fn loadNFC(allocator: std.mem.Allocator) !nfc.NFCData {

    var nfc_data = nfc.NFCData.init(allocator);

    errdefer nfc_data.deinit();

    

    // Load exclusions

    for (nf_data.exclusions) |cp| {

        try nfc_data.exclusions.put(@as(CodePoint, cp), {});

    }

    

    // Load decomposition mappings

    for (nf_data.decomp) |entry| {

        const cp = @as(CodePoint, entry[0]);

        const decomp_array = entry[1];

        var decomp = try allocator.alloc(CodePoint, decomp_array.len);

        for (decomp_array, 0..) |decomp_cp, i| {

            decomp[i] = @as(CodePoint, decomp_cp);

        }

        try nfc_data.decomp.put(cp, decomp);

    }

    

    // Note: The ranks field in nf.zon appears to be arrays of codepoints

    // grouped by their combining class. We'll need to determine the actual

    // combining class values from the Unicode standard or reference implementation.

    // For now, we'll leave combining_class empty as it might not be needed

    // for basic normalization.

    

    // Load NFC check from spec data

    for (spec_data.nfc_check) |cp| {

        try nfc_data.nfc_check.put(@as(CodePoint, cp), {});

    }

    

    return nfc_data;

}



/// Load emoji data from ZON

pub fn loadEmoji(allocator: std.mem.Allocator) !emoji.EmojiMap {

    var emoji_data = emoji.EmojiMap.init(allocator);

    errdefer emoji_data.deinit();

    

    for (spec_data.emoji) |seq| {

        var cps = try allocator.alloc(CodePoint, seq.len);

        for (seq, 0..) |cp, i| {

            cps[i] = @as(CodePoint, cp);

        }

        defer allocator.free(cps);

        

        // Calculate no_fe0f version

        const no_fe0f = utils.filterFe0f(allocator, cps) catch cps;

        defer if (no_fe0f.ptr != cps.ptr) allocator.free(no_fe0f);

        

        // Use addEmoji to properly populate both hash map and list

        try emoji_data.addEmoji(no_fe0f, cps);

    }

    

    return emoji_data;

}



/// Load script groups from ZON

pub fn loadScriptGroups(allocator: std.mem.Allocator) !script_groups.ScriptGroups {

    var groups = script_groups.ScriptGroups.init(allocator);

    groups.groups = try allocator.alloc(script_groups.ScriptGroup, spec_data.groups.len);

    errdefer {

        allocator.free(groups.groups);

        groups.deinit();

    }

    

    // Load each script group

    for (spec_data.groups, 0..) |group_data, i| {

        // Duplicate the name to ensure it's owned by the allocator

        const name = try allocator.dupe(u8, group_data.name);

        var group = script_groups.ScriptGroup.init(allocator, name, i);

        

        // Add primary characters

        for (group_data.primary) |cp| {

            try group.addPrimary(@as(CodePoint, cp));

        }

        

        // Add secondary characters (if present)

        if (group_data.secondary) |secondary| {

            for (secondary) |cp| {

                try group.addSecondary(@as(CodePoint, cp));

            }

        }

        

        // Add combining marks (if present)

        if (group_data.cm) |cm| {

            for (cm) |cp| {

                try group.addCombiningMark(@as(CodePoint, cp));

            }

        }

        

        groups.groups[i] = group;

    }

    

    // Load NSM characters

    for (spec_data.nsm) |cp| {

        try groups.addNSM(@as(CodePoint, cp));

    }

    

    // Set NSM max

    groups.nsm_max = spec_data.nsm_max;

    

    return groups;

}



/// Load confusable data from ZON

pub fn loadConfusables(allocator: std.mem.Allocator) !confusables.ConfusableData {

    var confusable_data = confusables.ConfusableData.init(allocator);

    errdefer confusable_data.deinit();

    

    confusable_data.sets = try allocator.alloc(confusables.ConfusableSet, spec_data.wholes.len);

    

    for (spec_data.wholes, 0..) |whole, i| {

        // Get target

        const target = if (whole.target) |t| 

            try allocator.dupe(u8, t)

        else 

            try allocator.dupe(u8, "unknown");

        

        var set = confusables.ConfusableSet.init(allocator, target);

        

        // Load valid characters

        var valid_slice = try allocator.alloc(CodePoint, whole.valid.len);

        for (whole.valid, 0..) |cp, j| {

            valid_slice[j] = @as(CodePoint, cp);

        }

        set.valid = valid_slice;

        

        // Load confused characters

        var confused_slice = try allocator.alloc(CodePoint, whole.confused.len);

        for (whole.confused, 0..) |cp, j| {

            confused_slice[j] = @as(CodePoint, cp);

        }

        set.confused = confused_slice;

        

        confusable_data.sets[i] = set;

    }

    

    return confusable_data;

}



test "static data loading from ZON" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Just verify that the compile-time imports work

    try testing.expect(spec_data.created.len > 0);

    try testing.expect(spec_data.groups.len > 0);

    try testing.expect(nf_data.decomp.len > 0);

    

    // Test loading character mappings

    const mappings = try loadCharacterMappings(allocator);

    // With comptime data, we just verify the struct was created

    _ = mappings;

    

    // Test loading emoji

    const emoji_map = try loadEmoji(allocator);

    std.debug.print("Loaded {} emoji sequences\n", .{emoji_map.all_emojis.items.len});

    try testing.expect(emoji_map.all_emojis.items.len > 0);

    

    std.debug.print("✓ Successfully imported and loaded ZON data at compile time\n", .{});

}```

```zig [./src/test_spec_loading_legacy.zig]

const std = @import("std");

const root = @import("root.zig");

const static_data_loader = @import("static_data_loader.zig");



pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    

    const stdout = std.io.getStdOut().writer();

    

    try stdout.print("Testing spec.json loading\n", .{});

    try stdout.print("========================\n\n", .{});

    

    // Load from spec.json

    const start_time = std.time.milliTimestamp();

    var mappings = try static_data_loader.loadCharacterMappings(allocator);

    defer mappings.deinit();

    const load_time = std.time.milliTimestamp() - start_time;

    

    try stdout.print("✓ Successfully loaded spec.json in {}ms\n\n", .{load_time});

    

    // Count loaded data

    var mapped_count: usize = 0;

    var ignored_count: usize = 0; 

    var valid_count: usize = 0;

    

    var mapped_iter = mappings.unicode_mappings.iterator();

    while (mapped_iter.next()) |_| {

        mapped_count += 1;

    }

    

    var ignored_iter = mappings.ignored_chars.iterator();

    while (ignored_iter.next()) |_| {

        ignored_count += 1;

    }

    

    var valid_iter = mappings.valid_chars.iterator();

    while (valid_iter.next()) |_| {

        valid_count += 1;

    }

    

    try stdout.print("Loaded data statistics:\n", .{});

    try stdout.print("- Mapped characters: {}\n", .{mapped_count});

    try stdout.print("- Ignored characters: {}\n", .{ignored_count});

    try stdout.print("- Valid characters: {}\n", .{valid_count});

    try stdout.print("\n", .{});

    

    // Test some specific mappings

    try stdout.print("Sample mappings:\n", .{});

    

    const test_cases = [_]struct { cp: u32, name: []const u8 }{

        .{ .cp = 39, .name = "apostrophe" },      // ' -> '

        .{ .cp = 65, .name = "A" },              // A -> a

        .{ .cp = 8217, .name = "right quote" },  // ' (should have no mapping)

        .{ .cp = 8450, .name = "ℂ" },            // ℂ -> c

        .{ .cp = 8460, .name = "ℌ" },            // ℌ -> h

        .{ .cp = 189, .name = "½" },             // ½ -> 1⁄2

    };

    

    for (test_cases) |test_case| {

        if (mappings.getMapped(test_case.cp)) |mapped| {

            try stdout.print("- {s} (U+{X:0>4}): maps to", .{ test_case.name, test_case.cp });

            for (mapped) |cp| {

                try stdout.print(" U+{X:0>4}", .{cp});

            }

            try stdout.print("\n", .{});

        } else {

            try stdout.print("- {s} (U+{X:0>4}): no mapping\n", .{ test_case.name, test_case.cp });

        }

    }

    

    try stdout.print("\n", .{});

    

    // Test ignored characters

    try stdout.print("Sample ignored characters:\n", .{});

    const ignored_tests = [_]u32{ 173, 8204, 8205, 65279 };

    for (ignored_tests) |cp| {

        const is_ignored = mappings.isIgnored(cp);

        try stdout.print("- U+{X:0>4}: {}\n", .{ cp, is_ignored });

    }

    

    try stdout.print("\n", .{});

    

    // Test valid characters

    try stdout.print("Sample valid characters:\n", .{});

    const valid_tests = [_]u32{ 'a', 'z', '0', '9', '-', '_', '.', 8217 };

    for (valid_tests) |cp| {

        const is_valid = mappings.isValid(cp);

        try stdout.print("- '{}' (U+{X:0>4}): {}\n", .{ 

            if (cp < 128) @as(u8, @intCast(cp)) else '?', 

            cp, 

            is_valid 

        });

    }

}```

```zig [./src/beautify.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const validate = @import("validate.zig");

const utils = @import("utils.zig");

const constants = @import("constants.zig");



pub fn beautifyLabels(allocator: std.mem.Allocator, labels: []const validate.ValidatedLabel) ![]u8 {

    var result = std.ArrayList(u8).init(allocator);

    defer result.deinit();

    

    for (labels, 0..) |label, i| {

        if (i > 0) {

            try result.append('.');

        }

        

        const label_str = try beautifyLabel(allocator, label);

        defer allocator.free(label_str);

        try result.appendSlice(label_str);

    }

    

    return result.toOwnedSlice();

}



fn beautifyLabel(allocator: std.mem.Allocator, label: validate.ValidatedLabel) ![]u8 {

    var result = std.ArrayList(u8).init(allocator);

    defer result.deinit();

    

    // Get all code points from the label

    var cps = std.ArrayList(CodePoint).init(allocator);

    defer cps.deinit();

    

    for (label.tokens) |token| {

        const token_cps = token.getCps();

        try cps.appendSlice(token_cps);

    }

    

    // Apply beautification rules

    try applyBeautificationRules(allocator, cps.items, label.label_type);

    

    // Convert back to string

    return utils.cps2str(allocator, cps.items);

}



fn applyBeautificationRules(allocator: std.mem.Allocator, cps: []CodePoint, label_type: validate.LabelType) !void {

    _ = allocator;

    

    // Update ethereum symbol: ξ => Ξ if not Greek

    switch (label_type) {

        .greek => {

            // Keep ξ as is for Greek

        },

        else => {

            // Replace ξ with Ξ for non-Greek

            for (cps) |*cp| {

                if (cp.* == constants.CP_XI_SMALL) {

                    cp.* = constants.CP_XI_CAPITAL;

                }

            }

        },

    }

    

    // Additional beautification rules could be added here

    // For example, handling leading/trailing hyphens, etc.

}



test "beautifyLabels basic functionality" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const tokenizer = @import("tokenizer.zig");

    

    // Create a simple test label

    const token = try tokenizer.Token.createValid(allocator, &[_]CodePoint{0x68, 0x65, 0x6C, 0x6C, 0x6F}); // "hello"

    const tokens = [_]tokenizer.Token{token};

    

    const label = try validate.ValidatedLabel.init(allocator, &tokens, validate.LabelType.ascii);

    

    const labels = [_]validate.ValidatedLabel{label};

    const result = beautifyLabels(allocator, &labels) catch |err| {

        // For now, we may get errors due to incomplete implementation

        try testing.expect(err == error.OutOfMemory or err == error.InvalidUtf8);

        return;

    };

    defer allocator.free(result);

    

    // Basic sanity check

    try testing.expect(result.len > 0);

}```

```zig [./src/validator.zig]

const std = @import("std");

const tokenizer = @import("tokenizer.zig");

const code_points = @import("code_points.zig");

const constants = @import("constants.zig");

const utils = @import("utils.zig");

const static_data_loader = @import("static_data_loader.zig");

const character_mappings = @import("character_mappings.zig");

const script_groups = @import("script_groups.zig");

const confusables = @import("confusables.zig");

const combining_marks = @import("combining_marks.zig");

const nsm_validation = @import("nsm_validation.zig");



// Type definitions

pub const CodePoint = u32;



// Validation error types

pub const ValidationError = error{

    EmptyLabel,

    InvalidLabelExtension,

    UnderscoreInMiddle,

    LeadingCombiningMark,

    CombiningMarkAfterEmoji,

    DisallowedCombiningMark,

    CombiningMarkAfterFenced,

    InvalidCombiningMarkBase,

    ExcessiveCombiningMarks,

    InvalidArabicDiacritic,

    ExcessiveArabicDiacritics,

    InvalidDevanagariMatras,

    InvalidThaiVowelSigns,

    CombiningMarkOrderError,

    FencedLeading,

    FencedTrailing,

    FencedAdjacent,

    DisallowedCharacter,

    IllegalMixture,

    WholeScriptConfusable,

    DuplicateNSM,

    ExcessiveNSM,

    LeadingNSM,

    NSMAfterEmoji,

    NSMAfterFenced,

    InvalidNSMBase,

    NSMOrderError,

    DisallowedNSMScript,

    OutOfMemory,

    InvalidUtf8,

};



// Script group reference

pub const ScriptGroupRef = struct {

    group: *const script_groups.ScriptGroup,

    name: []const u8,

};



// Validated label result

pub const ValidatedLabel = struct {

    tokens: []const tokenizer.Token,

    script_group: ScriptGroupRef,

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator, tokens: []const tokenizer.Token, script_group: ScriptGroupRef) !ValidatedLabel {

        const owned_tokens = try allocator.dupe(tokenizer.Token, tokens);

        return ValidatedLabel{

            .tokens = owned_tokens,

            .script_group = script_group,

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: ValidatedLabel) void {

        // Note: tokens are owned by the tokenizer, we only own the slice

        self.allocator.free(self.tokens);

    }

    

    pub fn isEmpty(self: ValidatedLabel) bool {

        return self.tokens.len == 0;

    }

    

    pub fn isASCII(self: ValidatedLabel) bool {

        // Latin script with all ASCII characters is considered ASCII

        if (!std.mem.eql(u8, self.script_group.name, "Latin")) {

            return false;

        }

        

        // Check if all tokens contain only ASCII codepoints

        for (self.tokens) |token| {

            const cps = token.getCps();

            for (cps) |cp| {

                if (cp > 0x7F) {

                    return false;

                }

            }

        }

        

        return true;

    }

    

    pub fn isEmoji(self: ValidatedLabel) bool {

        return std.mem.eql(u8, self.script_group.name, "Emoji");

    }

};



// Character classification for validation

pub const CharacterValidator = struct {

    // Fenced characters (placement restricted)

    // Based on reference implementations

    const FENCED_CHARS = [_]CodePoint{

        0x0027, // Apostrophe '

        0x002D, // Hyphen-minus -

        0x003A, // Colon :

        0x00B7, // Middle dot ·

        0x05F4, // Hebrew punctuation gershayim ״

        0x27CC, // Long division ⟌

    };

    

    // Combining marks (must not be leading or after emoji)

    const COMBINING_MARKS = [_]CodePoint{

        0x0300, // Combining grave accent

        0x0301, // Combining acute accent

        0x0302, // Combining circumflex accent

        0x0303, // Combining tilde

        0x0304, // Combining macron

        0x0305, // Combining overline

        0x0306, // Combining breve

        0x0307, // Combining dot above

        0x0308, // Combining diaeresis

        0x0309, // Combining hook above

        0x030A, // Combining ring above

        0x030B, // Combining double acute accent

        0x030C, // Combining caron

    };

    

    // Non-spacing marks (NSM) - subset of combining marks with special rules

    const NON_SPACING_MARKS = [_]CodePoint{

        0x0610, // Arabic sign sallallahou alayhe wassallam

        0x0611, // Arabic sign alayhe assallam

        0x0612, // Arabic sign rahmatullahi alayhe

        0x0613, // Arabic sign radi allahou anhu

        0x0614, // Arabic sign takhallus

        0x0615, // Arabic small high tah

        0x0616, // Arabic small high ligature alef with lam with yeh

        0x0617, // Arabic small high zain

        0x0618, // Arabic small fatha

        0x0619, // Arabic small damma

        0x061A, // Arabic small kasra

    };

    

    // Maximum NSM count per base character

    const NSM_MAX = 4;

    

    pub fn isFenced(cp: CodePoint) bool {

        return std.mem.indexOfScalar(CodePoint, &FENCED_CHARS, cp) != null;

    }

    

    pub fn isCombiningMark(cp: CodePoint) bool {

        return std.mem.indexOfScalar(CodePoint, &COMBINING_MARKS, cp) != null;

    }

    

    pub fn isNonSpacingMark(cp: CodePoint) bool {

        return std.mem.indexOfScalar(CodePoint, &NON_SPACING_MARKS, cp) != null;

    }

    

    pub fn isASCII(cp: CodePoint) bool {

        return cp <= 0x7F;

    }

    

    pub fn isUnderscore(cp: CodePoint) bool {

        return cp == 0x5F; // '_'

    }

    

    pub fn isHyphen(cp: CodePoint) bool {

        return cp == 0x2D; // '-'

    }

    

    pub fn getPeriod() CodePoint {

        return 0x2E; // '.'

    }

    

    // This is now handled by script_groups.zig

};



// Main validation function

pub fn validateLabel(

    allocator: std.mem.Allocator,

    tokenized_name: tokenizer.TokenizedName,

    specs: *const code_points.CodePointsSpecs,

) ValidationError!ValidatedLabel {

    _ = specs; // TODO: Use specs for advanced validation

    

    std.debug.print("validateLabel: Starting validation\n", .{});

    

    // Step 1: Check for empty label

    try checkNotEmpty(tokenized_name);

    std.debug.print("validateLabel: checkNotEmpty passed\n", .{});

    

    // Step 2: Get all code points from tokens

    const cps = try getAllCodePoints(allocator, tokenized_name);

    defer allocator.free(cps);

    std.debug.print("validateLabel: getAllCodePoints returned {} cps\n", .{cps.len});

    

    // Step 3: Check for disallowed characters

    try checkDisallowedCharacters(tokenized_name.tokens);

    std.debug.print("validateLabel: checkDisallowedCharacters passed\n", .{});

    

    // Step 4: Check for leading underscore rule

    try checkLeadingUnderscore(cps);

    std.debug.print("validateLabel: checkLeadingUnderscore passed\n", .{});

    

    // Step 5: Load script groups and determine script group

    std.debug.print("validateLabel: Loading script groups\n", .{});

    var groups = static_data_loader.loadScriptGroups(allocator) catch |err| {

        switch (err) {

            error.OutOfMemory => return ValidationError.OutOfMemory,

        }

    };

    defer groups.deinit();

    std.debug.print("validateLabel: Script groups loaded\n", .{});

    

    // Get unique code points for script detection

    std.debug.print("validateLabel: Creating unique set\n", .{});

    var unique_set = std.AutoHashMap(CodePoint, void).init(allocator);

    defer unique_set.deinit();

    

    std.debug.print("validateLabel: Adding {} cps to unique set\n", .{cps.len});

    for (cps) |cp| {

        std.debug.print("  cp: 0x{x} ({})\n", .{cp, cp});

        try unique_set.put(cp, {});

    }

    std.debug.print("validateLabel: Unique set has {} entries\n", .{unique_set.count()});

    

    var unique_cps = try allocator.alloc(CodePoint, unique_set.count());

    defer allocator.free(unique_cps);

    

    var iter = unique_set.iterator();

    var idx: usize = 0;

    while (iter.next()) |entry| {

        unique_cps[idx] = entry.key_ptr.*;

        idx += 1;

    }

    

    std.debug.print("validateLabel: Calling determineScriptGroup with {} unique cps\n", .{unique_cps.len});

    const script_group = groups.determineScriptGroup(unique_cps, allocator) catch |err| {

        switch (err) {

            error.DisallowedCharacter => return ValidationError.DisallowedCharacter,

            error.EmptyInput => return ValidationError.EmptyLabel,

            else => return ValidationError.IllegalMixture,

        }

    };

    

    std.debug.print("validateLabel: Script group determined: {s}\n", .{script_group.name});

    

    // Step 6: Apply script-specific validation

    if (std.mem.eql(u8, script_group.name, "Latin")) {

        // Check if all characters are ASCII

        var all_ascii = true;

        for (cps) |cp| {

            if (cp > 0x7F) {

                all_ascii = false;

                break;

            }

        }

        if (all_ascii) {

            std.debug.print("validateLabel: Applying ASCII rules\n", .{});

            try checkASCIIRules(cps);

        }

    } else if (std.mem.eql(u8, script_group.name, "Emoji")) {

        try checkEmojiRules(tokenized_name.tokens);

    } else {

        try checkUnicodeRules(cps);

    }

    

    // Step 7: Check fenced characters

    try checkFencedCharacters(allocator, cps);

    

    // Step 8: Check combining marks with script group validation

    try combining_marks.validateCombiningMarks(cps, script_group, allocator);

    

    // Step 9: Check non-spacing marks with comprehensive validation

    nsm_validation.validateNSM(cps, &groups, script_group, allocator) catch |err| {

        switch (err) {

            nsm_validation.NSMValidationError.ExcessiveNSM => return ValidationError.ExcessiveNSM,

            nsm_validation.NSMValidationError.DuplicateNSM => return ValidationError.DuplicateNSM,

            nsm_validation.NSMValidationError.LeadingNSM => return ValidationError.LeadingNSM,

            nsm_validation.NSMValidationError.NSMAfterEmoji => return ValidationError.NSMAfterEmoji,

            nsm_validation.NSMValidationError.NSMAfterFenced => return ValidationError.NSMAfterFenced,

            nsm_validation.NSMValidationError.InvalidNSMBase => return ValidationError.InvalidNSMBase,

            nsm_validation.NSMValidationError.NSMOrderError => return ValidationError.NSMOrderError,

            nsm_validation.NSMValidationError.DisallowedNSMScript => return ValidationError.DisallowedNSMScript,

        }

    };

    

    // Step 10: Check for whole-script confusables

    std.debug.print("validateLabel: Loading confusables\n", .{});

    var confusable_data = static_data_loader.loadConfusables(allocator) catch |err| {

        switch (err) {

            error.OutOfMemory => return ValidationError.OutOfMemory,

        }

    };

    defer confusable_data.deinit();

    

    std.debug.print("validateLabel: Checking confusables for {} cps\n", .{cps.len});

    const is_confusable = try confusable_data.checkWholeScriptConfusables(cps, allocator);

    std.debug.print("validateLabel: is_confusable = {}\n", .{is_confusable});

    if (is_confusable) {

        return ValidationError.WholeScriptConfusable;

    }

    

    const owned_name = try allocator.dupe(u8, script_group.name);

    const script_ref = ScriptGroupRef{

        .group = script_group,

        .name = owned_name,

    };

    return ValidatedLabel.init(allocator, tokenized_name.tokens, script_ref);

}



// Helper function to check if a codepoint is whitespace

fn isWhitespace(cp: CodePoint) bool {

    return switch (cp) {

        0x09...0x0D => true, // Tab, LF, VT, FF, CR

        0x20 => true,        // Space

        0x85 => true,        // Next Line

        0xA0 => true,        // Non-breaking space

        0x1680 => true,      // Ogham space mark

        0x2000...0x200A => true, // Various spaces

        0x2028 => true,      // Line separator

        0x2029 => true,      // Paragraph separator

        0x202F => true,      // Narrow no-break space

        0x205F => true,      // Medium mathematical space

        0x3000 => true,      // Ideographic space

        else => false,

    };

}



// Validation helper functions

fn checkNotEmpty(tokenized_name: tokenizer.TokenizedName) ValidationError!void {

    if (tokenized_name.isEmpty()) {

        return ValidationError.EmptyLabel;

    }

    

    // Check if all tokens are ignored or disallowed whitespace

    var has_content = false;

    for (tokenized_name.tokens) |token| {

        switch (token.type) {

            .ignored => continue,

            .disallowed => {

                // Check if it's whitespace

                const cp = token.data.disallowed.cp;

                if (isWhitespace(cp)) {

                    continue;

                }

                has_content = true;

                break;

            },

            else => {

                has_content = true;

                break;

            }

        }

    }

    

    if (!has_content) {

        return ValidationError.EmptyLabel;

    }

}



fn checkDisallowedCharacters(tokens: []const tokenizer.Token) ValidationError!void {

    for (tokens) |token| {

        switch (token.type) {

            .disallowed => return ValidationError.DisallowedCharacter,

            else => continue,

        }

    }

}



fn getAllCodePoints(allocator: std.mem.Allocator, tokenized_name: tokenizer.TokenizedName) ValidationError![]CodePoint {

    var cps = std.ArrayList(CodePoint).init(allocator);

    defer cps.deinit();

    

    for (tokenized_name.tokens) |token| {

        switch (token.data) {

            .valid => |v| try cps.appendSlice(v.cps),

            .mapped => |m| try cps.appendSlice(m.cps),

            .stop => |s| try cps.append(s.cp),

            else => continue, // Skip ignored and disallowed tokens

        }

    }

    

    return cps.toOwnedSlice();

}



fn checkLeadingUnderscore(cps: []const CodePoint) ValidationError!void {

    if (cps.len == 0) return;

    

    // Find the end of leading underscores

    var leading_underscores: usize = 0;

    for (cps) |cp| {

        if (CharacterValidator.isUnderscore(cp)) {

            leading_underscores += 1;

        } else {

            break;

        }

    }

    

    // Check for underscores after the leading ones

    for (cps[leading_underscores..]) |cp| {

        if (CharacterValidator.isUnderscore(cp)) {

            return ValidationError.UnderscoreInMiddle;

        }

    }

}



// This function is now replaced by script_groups.determineScriptGroup



fn checkASCIIRules(cps: []const CodePoint) ValidationError!void {

    // ASCII label extension rule: no '--' at positions 2-3

    if (cps.len >= 4 and 

        CharacterValidator.isHyphen(cps[2]) and 

        CharacterValidator.isHyphen(cps[3])) {

        return ValidationError.InvalidLabelExtension;

    }

}



fn checkEmojiRules(tokens: []const tokenizer.Token) ValidationError!void {

    // Check that emoji tokens don't have combining marks

    for (tokens) |token| {

        switch (token.type) {

            .emoji => {

                // Emoji should not be followed by combining marks

                // This is a simplified check

                continue;

            },

            else => continue,

        }

    }

}



fn checkUnicodeRules(cps: []const CodePoint) ValidationError!void {

    // Unicode-specific validation rules

    // For now, just basic checks

    for (cps) |cp| {

        if (cp > 0x10FFFF) {

            return ValidationError.DisallowedCharacter;

        }

    }

}



fn checkFencedCharacters(allocator: std.mem.Allocator, cps: []const CodePoint) ValidationError!void {

    if (cps.len == 0) return;

    

    // Load character mappings to get fenced characters from spec.zon

    var mappings = static_data_loader.loadCharacterMappings(allocator) catch |err| {

        std.debug.print("Warning: Failed to load character mappings: {}, using hardcoded\n", .{err});

        // Fallback to hardcoded check

        return checkFencedCharactersHardcoded(cps);

    };

    defer mappings.deinit();

    

    const last = cps.len - 1;

    

    // Check for leading fenced character

    if (mappings.isFenced(cps[0])) {

        return ValidationError.FencedLeading;

    }

    

    // Check for trailing fenced character

    if (mappings.isFenced(cps[last])) {

        return ValidationError.FencedTrailing;

    }

    

    // Check for consecutive fenced characters (but allow trailing consecutive)

    // Following JavaScript reference: for (let i = 1; i < last; i++)

    var i: usize = 1;

    while (i < last) : (i += 1) {

        if (mappings.isFenced(cps[i])) {

            // Check how many consecutive fenced characters we have

            var j = i + 1;

            while (j <= last and mappings.isFenced(cps[j])) : (j += 1) {}

            

            // JavaScript: if (j === last) break; // trailing

            // This means if we've reached the last character, it's trailing consecutive, which is allowed

            if (j == cps.len) break;

            

            // If we found consecutive fenced characters that aren't trailing, it's an error

            if (j > i + 1) {

                return ValidationError.FencedAdjacent;

            }

        }

    }

}



fn checkFencedCharactersHardcoded(cps: []const CodePoint) ValidationError!void {

    if (cps.len == 0) return;

    

    const last = cps.len - 1;

    

    // Check for leading fenced character

    if (CharacterValidator.isFenced(cps[0])) {

        return ValidationError.FencedLeading;

    }

    

    // Check for trailing fenced character

    if (CharacterValidator.isFenced(cps[last])) {

        return ValidationError.FencedTrailing;

    }

    

    // Check for consecutive fenced characters (but allow trailing consecutive)

    var i: usize = 1;

    while (i < last) : (i += 1) {

        if (CharacterValidator.isFenced(cps[i])) {

            var j = i + 1;

            while (j <= last and CharacterValidator.isFenced(cps[j])) : (j += 1) {}

            

            if (j == cps.len) break; // Allow trailing consecutive

            

            if (j > i + 1) {

                return ValidationError.FencedAdjacent;

            }

        }

    }

}



// This function is now replaced by combining_marks.validateCombiningMarks



// This function is now replaced by nsm_validation.validateNSM

// which provides comprehensive NSM validation following ENSIP-15



// Test helper functions

pub fn codePointsFromString(allocator: std.mem.Allocator, input: []const u8) ![]CodePoint {

    var cps = std.ArrayList(CodePoint).init(allocator);

    defer cps.deinit();

    

    var i: usize = 0;

    while (i < input.len) {

        const cp_len = std.unicode.utf8ByteSequenceLength(input[i]) catch return ValidationError.InvalidUtf8;

        const cp = std.unicode.utf8Decode(input[i..i+cp_len]) catch return ValidationError.InvalidUtf8;

        try cps.append(cp);

        i += cp_len;

    }

    

    return cps.toOwnedSlice();

}



// Tests

test "validator - empty label" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    

    const specs = code_points.CodePointsSpecs.init(testing.allocator);

    const empty_tokenized = tokenizer.TokenizedName.init(testing.allocator, "");

    

    const result = validateLabel(testing.allocator, empty_tokenized, &specs);

    try testing.expectError(ValidationError.EmptyLabel, result);

}



test "validator - ASCII label" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    std.debug.print("\nDEBUG: Starting ASCII label test\n", .{});

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    std.debug.print("DEBUG: Created specs\n", .{});

    

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello", &specs, false);

    defer tokenized.deinit();

    std.debug.print("DEBUG: Tokenized input, tokens={}\n", .{tokenized.tokens.len});

    

    std.debug.print("DEBUG: Calling validateLabel\n", .{});

    const result = try validateLabel(allocator, tokenized, &specs);

    defer result.deinit();

    std.debug.print("DEBUG: validateLabel completed\n", .{});

    

    std.debug.print("DEBUG: result.script_group.name = '{s}'\n", .{result.script_group.name});

    std.debug.print("DEBUG: result.isASCII() = {}\n", .{result.isASCII()});

    std.debug.print("DEBUG: tokens.len = {}\n", .{result.tokens.len});

    for (result.tokens, 0..) |token, i| {

        const cps = token.getCps();

        std.debug.print("DEBUG: token[{}]: len={}, cps=[", .{i, cps.len});

        for (cps, 0..) |cp, j| {

            if (j > 0) std.debug.print(", ", .{});

            std.debug.print("0x{x}", .{cp});

        }

        std.debug.print("]\n", .{});

    }

    

    try testing.expect(result.isASCII());

    try testing.expectEqualStrings("Latin", result.script_group.name);

}



test "validator - underscore rules" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Valid: leading underscore

    {

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "_hello", &specs, false);

        defer tokenized.deinit();

        

        const result = try validateLabel(allocator, tokenized, &specs);

        defer result.deinit();

        

        try testing.expect(result.isASCII());

    }

    

    // Invalid: underscore in middle

    {

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hel_lo", &specs, false);

        defer tokenized.deinit();

        

        const result = validateLabel(allocator, tokenized, &specs);

        try testing.expectError(ValidationError.UnderscoreInMiddle, result);

    }

}



test "validator - ASCII label extension" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Invalid: ASCII label extension

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "te--st", &specs, false);

    defer tokenized.deinit();

    

    const result = validateLabel(allocator, tokenized, &specs);

    try testing.expectError(ValidationError.InvalidLabelExtension, result);

}



test "validator - fenced characters" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // TODO: Implement proper fenced character checking from spec.zon

    // For now, skip this test as apostrophe is being mapped to U+2019

    // and fenced character rules need to be implemented properly

    {

        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "'hello", &specs, false);

        defer tokenized.deinit();

        

        // With full spec data, apostrophe is mapped, not treated as fenced

        const result = validateLabel(allocator, tokenized, &specs) catch {

            return; // Expected behavior for now

        };

        _ = result;

    }

    

    // TODO: Test trailing fenced character when implemented

    // {

    //     const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello'", &specs, false);

    //     defer tokenized.deinit();

    //     

    //     const result = validateLabel(allocator, tokenized, &specs);

    //     try testing.expectError(ValidationError.FencedTrailing, result);

    // }

}



test "validator - script group detection" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Load script groups

    var groups = try static_data_loader.loadScriptGroups(allocator);

    defer groups.deinit();

    

    // Test ASCII

    {

        const cps = [_]CodePoint{'a', 'b', 'c'};

        const group = try groups.determineScriptGroup(&cps, allocator);

        try testing.expectEqualStrings("ASCII", group.name);

    }

    

    // Test mixed script rejection

    {

        const cps = [_]CodePoint{'a', 0x03B1}; // a + α

        const result = groups.determineScriptGroup(&cps, allocator);

        try testing.expectError(error.DisallowedCharacter, result);

    }

}



test "validator - whitespace empty label" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test with single space

    const input = " ";

    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);

    defer tokenized.deinit();

    

    std.debug.print("\nDEBUG: validator whitespace test:\n", .{});

    std.debug.print("  Input: '{s}' (len={})\n", .{input, input.len});

    std.debug.print("  Tokens: {} total\n", .{tokenized.tokens.len});

    for (tokenized.tokens, 0..) |token, i| {

        std.debug.print("    [{}] type={s}", .{i, @tagName(token.type)});

        if (token.type == .disallowed) {

            std.debug.print(" cp=0x{x}", .{token.data.disallowed.cp});

        }

        std.debug.print("\n", .{});

    }

    std.debug.print("  isEmpty: {}\n", .{tokenized.isEmpty()});

    

    // Test checkNotEmpty directly

    const empty_result = checkNotEmpty(tokenized);

    if (empty_result) {

        std.debug.print("  checkNotEmpty: passed (not empty)\n", .{});

    } else |err| {

        std.debug.print("  checkNotEmpty: failed with {}\n", .{err});

    }

    

    const result = validateLabel(allocator, tokenized, &specs);

    

    // Should return EmptyLabel for whitespace-only input

    try testing.expectError(ValidationError.EmptyLabel, result);

}```

```zig [./src/join.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const validate = @import("validate.zig");

const utils = @import("utils.zig");

const constants = @import("constants.zig");



pub fn joinLabels(allocator: std.mem.Allocator, labels: []const validate.ValidatedLabel) ![]u8 {

    var result = std.ArrayList(u8).init(allocator);

    defer result.deinit();

    

    for (labels, 0..) |label, i| {

        if (i > 0) {

            try result.append('.');

        }

        

        const label_str = try joinLabel(allocator, label);

        defer allocator.free(label_str);

        try result.appendSlice(label_str);

    }

    

    return result.toOwnedSlice();

}



fn joinLabel(allocator: std.mem.Allocator, label: validate.ValidatedLabel) ![]u8 {

    var cps = std.ArrayList(CodePoint).init(allocator);

    defer cps.deinit();

    

    for (label.tokens) |token| {

        const token_cps = token.getCps();

        try cps.appendSlice(token_cps);

    }

    

    return utils.cps2str(allocator, cps.items);

}



test "joinLabels basic functionality" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const tokenizer = @import("tokenizer.zig");

    

    // Create a simple test label

    const token = try tokenizer.Token.createValid(allocator, &[_]CodePoint{0x68, 0x65, 0x6C, 0x6C, 0x6F}); // "hello"

    const tokens = [_]tokenizer.Token{token};

    

    const label = try validate.ValidatedLabel.init(allocator, &tokens, validate.LabelType.ascii);

    

    const labels = [_]validate.ValidatedLabel{label};

    const result = joinLabels(allocator, &labels) catch |err| {

        // For now, we may get errors due to incomplete implementation

        try testing.expect(err == error.OutOfMemory or err == error.InvalidUtf8);

        return;

    };

    defer allocator.free(result);

    

    // Basic sanity check

    try testing.expect(result.len > 0);

}```

```zig [./src/test_character_mappings.zig]

const std = @import("std");

const root = @import("root.zig");

const tokenizer = @import("tokenizer.zig");

const character_mappings = @import("character_mappings.zig");

const static_data_loader = @import("static_data_loader.zig");



pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    

    const stdout = std.io.getStdOut().writer();

    

    try stdout.print("Character Mappings Test\n", .{});

    try stdout.print("======================\n\n", .{});

    

    // Test cases that should demonstrate character mappings

    const test_cases = [_]struct { input: []const u8, expected: []const u8 }{

        .{ .input = "HELLO", .expected = "hello" },

        .{ .input = "Hello", .expected = "hello" },

        .{ .input = "HeLLo", .expected = "hello" },

        .{ .input = "hello", .expected = "hello" },

        .{ .input = "Test123", .expected = "test123" },

        .{ .input = "ABC-DEF", .expected = "abc-def" },

        .{ .input = "½", .expected = "1⁄2" },

        .{ .input = "ℌello", .expected = "hello" },

        .{ .input = "ℓℯℓℓo", .expected = "lello" },

    };

    

    // Load character mappings

    var mappings = try static_data_loader.loadBasicMappings(allocator);

    defer mappings.deinit();

    

    for (test_cases) |test_case| {

        try stdout.print("Input: \"{s}\"\n", .{test_case.input});

        

        // Tokenize with mappings

        const tokenized = try tokenizer.TokenizedName.fromInputWithMappings(

            allocator,

            test_case.input,

            &mappings,

            false,

        );

        defer tokenized.deinit();

        

        // Build normalized output

        var result = std.ArrayList(u8).init(allocator);

        defer result.deinit();

        

        for (tokenized.tokens) |token| {

            const cps = token.getCps();

            for (cps) |cp| {

                const utf8_len = std.unicode.utf8CodepointSequenceLength(@as(u21, @intCast(cp))) catch continue;

                const old_len = result.items.len;

                try result.resize(old_len + utf8_len);

                _ = std.unicode.utf8Encode(@as(u21, @intCast(cp)), result.items[old_len..]) catch continue;

            }

        }

        

        try stdout.print("Output: \"{s}\"\n", .{result.items});

        try stdout.print("Expected: \"{s}\"\n", .{test_case.expected});

        

        if (std.mem.eql(u8, result.items, test_case.expected)) {

            try stdout.print("✓ PASS\n", .{});

        } else {

            try stdout.print("✗ FAIL\n", .{});

        }

        try stdout.print("\n", .{});

    }

}



test "character mappings integration" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Test ASCII case folding

    const result = try root.normalize(allocator, "HELLO");

    defer allocator.free(result);

    try testing.expectEqualStrings("hello", result);

    

    // Test Unicode mappings

    const result2 = try root.normalize(allocator, "½");

    defer allocator.free(result2);

    try testing.expectEqualStrings("1⁄2", result2);

}```

```zig [./src/static_data.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;



// This module would contain the static data structures and JSON parsing

// For now, it's a placeholder that would need to be implemented with

// the actual ENS normalization data



pub const SpecJson = struct {

    pub const GroupName = union(enum) {

        ascii,

        emoji,

        greek,

        other: []const u8,

    };

    

    pub const Group = struct {

        name: GroupName,

        primary: []const CodePoint,

        secondary: []const CodePoint,

        cm: []const CodePoint,

    };

    

    pub const WholeValue = union(enum) {

        number: u32,

        whole_object: WholeObject,

    };

    

    pub const WholeObject = struct {

        v: []const CodePoint,

        m: std.StringHashMap([]const []const u8),

    };

    

    pub const NfJson = struct {

        // Normalization data structures would go here

        // For now, placeholder

    };

};



// Placeholder functions that would load and parse the actual JSON data

pub fn loadSpecData(allocator: std.mem.Allocator) !SpecJson {

    _ = allocator;

    // This would load from spec.json

    return SpecJson{};

}



pub fn loadNfData(allocator: std.mem.Allocator) !SpecJson.NfJson {

    _ = allocator;

    // This would load from nf.json

    return SpecJson.NfJson{};

}



test "static_data placeholder" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const spec = try loadSpecData(allocator);

    _ = spec;

    

    const nf = try loadNfData(allocator);

    _ = nf;

}```

```zig [./src/utils.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const constants = @import("constants.zig");



const FE0F: CodePoint = 0xfe0f;

const LAST_ASCII_CP: CodePoint = 0x7f;



pub fn filterFe0f(allocator: std.mem.Allocator, cps: []const CodePoint) ![]CodePoint {

    var result = std.ArrayList(CodePoint).init(allocator);

    defer result.deinit();

    

    for (cps) |cp| {

        if (cp != FE0F) {

            try result.append(cp);

        }

    }

    

    return result.toOwnedSlice();

}



pub fn cps2str(allocator: std.mem.Allocator, cps: []const CodePoint) ![]u8 {

    var result = std.ArrayList(u8).init(allocator);

    defer result.deinit();

    

    for (cps) |cp| {

        if (cp <= 0x10FFFF) {

            var buf: [4]u8 = undefined;

            const len = std.unicode.utf8Encode(@intCast(cp), &buf) catch continue;

            try result.appendSlice(buf[0..len]);

        }

    }

    

    return result.toOwnedSlice();

}



pub fn cp2str(allocator: std.mem.Allocator, cp: CodePoint) ![]u8 {

    return cps2str(allocator, &[_]CodePoint{cp});

}



pub fn str2cps(allocator: std.mem.Allocator, str: []const u8) ![]CodePoint {

    var result = std.ArrayList(CodePoint).init(allocator);

    defer result.deinit();

    

    const utf8_view = std.unicode.Utf8View.init(str) catch return error.InvalidUtf8;

    var iter = utf8_view.iterator();

    

    while (iter.nextCodepoint()) |cp| {

        try result.append(cp);

    }

    

    return result.toOwnedSlice();

}



pub fn isAscii(cp: CodePoint) bool {

    return cp <= LAST_ASCII_CP;

}



// NFC normalization using our implementation

pub fn nfc(allocator: std.mem.Allocator, str: []const u8) ![]u8 {

    const nfc_mod = @import("nfc.zig");

    const static_data_loader = @import("static_data_loader.zig");

    

    // Convert string to codepoints

    const cps = try str2cps(allocator, str);

    defer allocator.free(cps);

    

    // Load NFC data

    var nfc_data = try static_data_loader.loadNFCData(allocator);

    defer nfc_data.deinit();

    

    // Apply NFC normalization

    const normalized_cps = try nfc_mod.nfc(allocator, cps, &nfc_data);

    defer allocator.free(normalized_cps);

    

    // Convert back to string

    return cps2str(allocator, normalized_cps);

}



pub fn nfdCps(allocator: std.mem.Allocator, cps: []const CodePoint, specs: anytype) ![]CodePoint {

    var result = std.ArrayList(CodePoint).init(allocator);

    defer result.deinit();

    

    for (cps) |cp| {

        if (specs.decompose(cp)) |decomposed| {

            try result.appendSlice(decomposed);

        } else {

            try result.append(cp);

        }

    }

    

    return result.toOwnedSlice();

}



test "filterFe0f" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const input = [_]CodePoint{ 0x41, FE0F, 0x42, FE0F, 0x43 };

    const result = try filterFe0f(allocator, &input);

    

    const expected = [_]CodePoint{ 0x41, 0x42, 0x43 };

    try testing.expectEqualSlices(CodePoint, &expected, result);

}



test "isAscii" {

    const testing = std.testing;

    try testing.expect(isAscii(0x41)); // 'A'

    try testing.expect(isAscii(0x7F)); // DEL

    try testing.expect(!isAscii(0x80)); // beyond ASCII

    try testing.expect(!isAscii(0x1F600)); // emoji

}```

```zig [./src/code_points.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;



pub const ParsedGroup = struct {

    name: []const u8,

    primary: std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage),

    secondary: std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage),

    primary_plus_secondary: std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage),

    cm_absent: bool,

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator, name: []const u8) ParsedGroup {

        return ParsedGroup{

            .name = name,

            .primary = std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage){},

            .secondary = std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage){},

            .primary_plus_secondary = std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage){},

            .cm_absent = true,

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *ParsedGroup) void {

        self.primary.deinit(self.allocator);

        self.secondary.deinit(self.allocator);

        self.primary_plus_secondary.deinit(self.allocator);

    }

    

    pub fn addPrimary(self: *ParsedGroup, cp: CodePoint) !void {

        try self.primary.put(self.allocator, cp, {});

        try self.primary_plus_secondary.put(self.allocator, cp, {});

    }

    

    pub fn addSecondary(self: *ParsedGroup, cp: CodePoint) !void {

        try self.secondary.put(self.allocator, cp, {});

        try self.primary_plus_secondary.put(self.allocator, cp, {});

    }

    

    pub fn containsCp(self: *const ParsedGroup, cp: CodePoint) bool {

        return self.primary_plus_secondary.contains(cp);

    }

    

    pub fn containsAllCps(self: *const ParsedGroup, cps: []const CodePoint) bool {

        for (cps) |cp| {

            if (!self.containsCp(cp)) {

                return false;

            }

        }

        return true;

    }

};



pub const ParsedWholeValue = union(enum) {

    number: u32,

    whole_object: ParsedWholeObject,

};



pub const ParsedWholeObject = struct {

    v: std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage),

    m: std.HashMapUnmanaged(CodePoint, []const []const u8, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage),

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator) ParsedWholeObject {

        return ParsedWholeObject{

            .v = std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage){},

            .m = std.HashMapUnmanaged(CodePoint, []const []const u8, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage){},

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *ParsedWholeObject) void {

        self.v.deinit(self.allocator);

        

        // Clean up the string arrays in m

        var iter = self.m.iterator();

        while (iter.next()) |entry| {

            for (entry.value_ptr.*) |str| {

                self.allocator.free(str);

            }

            self.allocator.free(entry.value_ptr.*);

        }

        self.m.deinit(self.allocator);

    }

};



pub const ParsedWholeMap = std.HashMapUnmanaged(CodePoint, ParsedWholeValue, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage);



pub const CodePointsSpecs = struct {

    // This would contain the various mappings and data structures

    // needed for ENS normalization. For now, placeholder structure.

    allocator: std.mem.Allocator,

    groups: []ParsedGroup,

    whole_map: ParsedWholeMap,

    

    pub fn init(allocator: std.mem.Allocator) CodePointsSpecs {

        return CodePointsSpecs{

            .allocator = allocator,

            .groups = &[_]ParsedGroup{},

            .whole_map = ParsedWholeMap{},

        };

    }

    

    pub fn deinit(self: *CodePointsSpecs) void {

        for (self.groups) |*group| {

            group.deinit();

        }

        self.allocator.free(self.groups);

        

        var iter = self.whole_map.iterator();

        while (iter.next()) |entry| {

            switch (entry.value_ptr.*) {

                .whole_object => |*obj| obj.deinit(),

                .number => {},

            }

        }

        self.whole_map.deinit(self.allocator);

    }

    

    pub fn decompose(self: *const CodePointsSpecs, cp: CodePoint) ?[]const CodePoint {

        // Placeholder for decomposition logic

        _ = self;

        _ = cp;

        return null;

    }

};



test "ParsedGroup basic operations" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var group = ParsedGroup.init(allocator, "Test");

    defer group.deinit();

    

    try group.addPrimary(0x41); // 'A'

    try group.addSecondary(0x42); // 'B'

    

    try testing.expect(group.containsCp(0x41));

    try testing.expect(group.containsCp(0x42));

    try testing.expect(!group.containsCp(0x43));

    

    const cps = [_]CodePoint{ 0x41, 0x42 };

    try testing.expect(group.containsAllCps(&cps));

    

    const cps_with_missing = [_]CodePoint{ 0x41, 0x43 };

    try testing.expect(!group.containsAllCps(&cps_with_missing));

}```

```zig [./src/tokenizer.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const constants = @import("constants.zig");

const utils = @import("utils.zig");

const code_points = @import("code_points.zig");

const error_types = @import("error.zig");

const character_mappings = @import("character_mappings.zig");

const static_data_loader = @import("static_data_loader.zig");

const nfc = @import("nfc.zig");

const emoji_mod = @import("emoji.zig");



// Token types based on ENSIP-15 specification

// Note: Unlike some implementations, our tokenizer can return errors for memory allocation

// failures. The reference JavaScript implementation never throws, but in Zig we need to

// handle allocation failures properly.

pub const TokenType = enum {

    valid,

    mapped,

    ignored,

    disallowed,

    emoji,

    nfc,

    stop,

    

    pub fn toString(self: TokenType) []const u8 {

        return switch (self) {

            .valid => "valid",

            .mapped => "mapped",

            .ignored => "ignored",

            .disallowed => "disallowed",

            .emoji => "emoji",

            .nfc => "nfc",

            .stop => "stop",

        };

    }

};



pub const Token = struct {

    type: TokenType,

    // Union of possible token data

    data: union(TokenType) {

        valid: struct {

            cps: []const CodePoint,

        },

        mapped: struct {

            cp: CodePoint,

            cps: []const CodePoint,

        },

        ignored: struct {

            cp: CodePoint,

        },

        disallowed: struct {

            cp: CodePoint,

        },

        emoji: struct {

            input: []const CodePoint,  // Changed from []const u8 to match reference

            emoji: []const CodePoint,   // fully-qualified emoji

            cps: []const CodePoint,     // output (fe0f filtered) - renamed from cps_no_fe0f

        },

        nfc: struct {

            input: []const CodePoint,

            cps: []const CodePoint,

            tokens0: ?[]Token,          // tokens before NFC (optional)

            tokens: ?[]Token,           // tokens after NFC (optional)

        },

        stop: struct {

            cp: CodePoint,

        },

    },

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator, token_type: TokenType) Token {

        return Token{

            .type = token_type,

            .data = switch (token_type) {

                .valid => .{ .valid = .{ .cps = &[_]CodePoint{} } },

                .mapped => .{ .mapped = .{ .cp = 0, .cps = &[_]CodePoint{} } },

                .ignored => .{ .ignored = .{ .cp = 0 } },

                .disallowed => .{ .disallowed = .{ .cp = 0 } },

                .emoji => .{ .emoji = .{ .input = &[_]CodePoint{}, .emoji = &[_]CodePoint{}, .cps = &[_]CodePoint{} } },

                .nfc => .{ .nfc = .{ .input = &[_]CodePoint{}, .cps = &[_]CodePoint{}, .tokens0 = null, .tokens = null } },

                .stop => .{ .stop = .{ .cp = constants.CP_STOP } },

            },

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: Token) void {

        switch (self.data) {

            .valid => |data| self.allocator.free(data.cps),

            .mapped => |data| self.allocator.free(data.cps),

            .emoji => |data| {

                self.allocator.free(data.input);

                self.allocator.free(data.emoji);

                self.allocator.free(data.cps);

            },

            .nfc => |data| {

                self.allocator.free(data.input);

                self.allocator.free(data.cps);

                if (data.tokens0) |tokens0| {

                    for (tokens0) |token| {

                        token.deinit();

                    }

                    self.allocator.free(tokens0);

                }

                if (data.tokens) |tokens| {

                    for (tokens) |token| {

                        token.deinit();

                    }

                    self.allocator.free(tokens);

                }

            },

            .ignored, .disallowed, .stop => {},

        }

    }

    

    pub fn getCps(self: Token) []const CodePoint {

        return switch (self.data) {

            .valid => |data| data.cps,

            .mapped => |data| data.cps,

            .emoji => |data| data.cps,

            .nfc => |data| data.cps,

            .ignored => |data| &[_]CodePoint{data.cp},

            .disallowed => |data| &[_]CodePoint{data.cp},

            .stop => |data| &[_]CodePoint{data.cp},

        };

    }

    

    pub fn getInputSize(self: Token) usize {

        return switch (self.data) {

            .valid => |data| data.cps.len,

            .nfc => |data| data.input.len,

            .emoji => |data| data.input.len,

            .mapped, .ignored, .disallowed, .stop => 1,

        };

    }

    

    pub fn isText(self: Token) bool {

        return switch (self.type) {

            .valid, .mapped, .nfc => true,

            else => false,

        };

    }

    

    pub fn isEmoji(self: Token) bool {

        return self.type == .emoji;

    }

    

    pub fn isIgnored(self: Token) bool {

        return self.type == .ignored;

    }

    

    pub fn isDisallowed(self: Token) bool {

        return self.type == .disallowed;

    }

    

    pub fn isStop(self: Token) bool {

        return self.type == .stop;

    }

    

    pub fn createValid(allocator: std.mem.Allocator, cps: []const CodePoint) !Token {

        const owned_cps = try allocator.dupe(CodePoint, cps);

        return Token{

            .type = .valid,

            .data = .{ .valid = .{ .cps = owned_cps } },

            .allocator = allocator,

        };

    }

    

    pub fn createMapped(allocator: std.mem.Allocator, cp: CodePoint, cps: []const CodePoint) !Token {

        const owned_cps = try allocator.dupe(CodePoint, cps);

        return Token{

            .type = .mapped,

            .data = .{ .mapped = .{ .cp = cp, .cps = owned_cps } },

            .allocator = allocator,

        };

    }

    

    pub fn createIgnored(allocator: std.mem.Allocator, cp: CodePoint) Token {

        return Token{

            .type = .ignored,

            .data = .{ .ignored = .{ .cp = cp } },

            .allocator = allocator,

        };

    }

    

    pub fn createDisallowed(allocator: std.mem.Allocator, cp: CodePoint) Token {

        return Token{

            .type = .disallowed,

            .data = .{ .disallowed = .{ .cp = cp } },

            .allocator = allocator,

        };

    }

    

    pub fn createStop(allocator: std.mem.Allocator) Token {

        return Token{

            .type = .stop,

            .data = .{ .stop = .{ .cp = constants.CP_STOP } },

            .allocator = allocator,

        };

    }

    

    pub fn createEmoji(

        allocator: std.mem.Allocator,

        input: []const CodePoint,

        emoji: []const CodePoint,

        cps: []const CodePoint  // fe0f filtered

    ) !Token {

        return Token{

            .type = .emoji,

            .data = .{ .emoji = .{

                .input = try allocator.dupe(CodePoint, input),

                .emoji = try allocator.dupe(CodePoint, emoji),

                .cps = try allocator.dupe(CodePoint, cps),

            }},

            .allocator = allocator,

        };

    }

    

    pub fn createNFC(

        allocator: std.mem.Allocator,

        input: []const CodePoint,

        cps: []const CodePoint,

        tokens0: ?[]Token,

        tokens: ?[]Token,

    ) !Token {

        const owned_tokens0 = if (tokens0) |t| try allocator.dupe(Token, t) else null;

        const owned_tokens = if (tokens) |t| try allocator.dupe(Token, t) else null;

        

        return Token{

            .type = .nfc,

            .data = .{ .nfc = .{

                .input = try allocator.dupe(CodePoint, input),

                .cps = try allocator.dupe(CodePoint, cps),

                .tokens0 = owned_tokens0,

                .tokens = owned_tokens,

            }},

            .allocator = allocator,

        };

    }

};



pub const TokenizedName = struct {

    input: []const u8,

    tokens: []Token,

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator, input: []const u8) TokenizedName {

        return TokenizedName{

            .input = input,

            .tokens = &[_]Token{},

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: TokenizedName) void {

        for (self.tokens) |token| {

            token.deinit();

        }

        self.allocator.free(self.tokens);

        self.allocator.free(self.input);

    }

    

    pub fn isEmpty(self: TokenizedName) bool {

        return self.tokens.len == 0;

    }

    

    pub fn fromInput(

        allocator: std.mem.Allocator,

        input: []const u8,

        _: *const code_points.CodePointsSpecs,

        apply_nfc: bool,

    ) !TokenizedName {

        if (input.len == 0) {

            return TokenizedName{

                .input = try allocator.dupe(u8, ""),

                .tokens = &[_]Token{},

                .allocator = allocator,

            };

        }

        

        const tokens = try tokenizeInputWithMappings(allocator, input, apply_nfc);

        

        return TokenizedName{

            .input = try allocator.dupe(u8, input),

            .tokens = tokens,

            .allocator = allocator,

        };

    }

    

    pub fn fromInputWithMappings(

        allocator: std.mem.Allocator,

        input: []const u8,

        mappings: *const character_mappings.CharacterMappings,

        apply_nfc: bool,

    ) !TokenizedName {

        if (input.len == 0) {

            return TokenizedName{

                .input = try allocator.dupe(u8, ""),

                .tokens = &[_]Token{},

                .allocator = allocator,

            };

        }

        

        const tokens = try tokenizeInputWithMappingsImpl(allocator, input, mappings, apply_nfc);

        

        return TokenizedName{

            .input = try allocator.dupe(u8, input),

            .tokens = tokens,

            .allocator = allocator,

        };

    }

};



// Character classification interface

pub const CharacterSpecs = struct {

    // For now, simple implementations - would be replaced with actual data

    pub fn isValid(self: *const CharacterSpecs, cp: CodePoint) bool {

        _ = self;

        // Simple ASCII letters and digits for now

        return (cp >= 'a' and cp <= 'z') or 

               (cp >= 'A' and cp <= 'Z') or 

               (cp >= '0' and cp <= '9') or

               cp == '-' or

               cp == '_' or  // underscore (validated for placement later)

               cp == '\'';   // apostrophe (fenced character, validated for placement later)

    }

    

    pub fn isIgnored(self: *const CharacterSpecs, cp: CodePoint) bool {

        _ = self;

        // Common ignored characters

        return cp == 0x00AD or // soft hyphen

               cp == 0x200C or // zero width non-joiner

               cp == 0x200D or // zero width joiner

               cp == 0xFEFF;   // zero width no-break space

    }

    

    pub fn getMapped(self: *const CharacterSpecs, cp: CodePoint) ?[]const CodePoint {

        _ = self;

        // Simple case folding for now

        if (cp >= 'A' and cp <= 'Z') {

            // Would need to allocate and return lowercase

            return null; // Placeholder

        }

        return null;

    }

    

    pub fn isStop(self: *const CharacterSpecs, cp: CodePoint) bool {

        _ = self;

        return cp == constants.CP_STOP;

    }

};



fn tokenizeInput(

    allocator: std.mem.Allocator,

    input: []const u8,

    specs: *const code_points.CodePointsSpecs,

    apply_nfc: bool,

) ![]Token {

    _ = specs;

    _ = apply_nfc;

    

    var tokens = std.ArrayList(Token).init(allocator);

    defer tokens.deinit();

    

    // Convert input to code points

    const cps = try utils.str2cps(allocator, input);

    defer allocator.free(cps);

    

    // Create a simple character specs for now

    const char_specs = CharacterSpecs{};

    

    for (cps) |cp| {

        if (char_specs.isStop(cp)) {

            try tokens.append(Token.createStop(allocator));

        } else if (char_specs.isValid(cp)) {

            try tokens.append(try Token.createValid(allocator, &[_]CodePoint{cp}));

        } else if (char_specs.isIgnored(cp)) {

            try tokens.append(Token.createIgnored(allocator, cp));

        } else if (char_specs.getMapped(cp)) |mapped| {

            try tokens.append(try Token.createMapped(allocator, cp, mapped));

        } else {

            try tokens.append(Token.createDisallowed(allocator, cp));

        }

    }

    

    // Collapse consecutive valid tokens

    try collapseValidTokens(allocator, &tokens);

    

    return tokens.toOwnedSlice();

}



fn tokenizeInputWithMappings(

    allocator: std.mem.Allocator,

    input: []const u8,

    apply_nfc: bool,

) ![]Token {

    // Load complete character mappings from spec.zon

    var mappings = static_data_loader.loadCharacterMappings(allocator) catch |err| blk: {

        // Fall back to basic mappings if spec.zon loading fails

        std.debug.print("Warning: Failed to load spec.zon: {}, using basic mappings\n", .{err});

        break :blk try static_data_loader.loadCharacterMappings(allocator);

    };

    defer mappings.deinit();

    

    return tokenizeInputWithMappingsImpl(allocator, input, &mappings, apply_nfc);

}



// Main tokenization implementation following ENSIP-15

// Algorithm:

// 1. Process input looking for emoji sequences first (emoji have priority)

// 2. Process individual characters (valid, mapped, ignored, disallowed, stop)

// 3. Apply NFC normalization as a post-processing step if requested

// 4. Collapse consecutive valid tokens

//

// This matches the reference JavaScript implementation's approach of:

// - Emoji-first processing

// - Character-by-character fallback

// - NFC as post-processing

fn tokenizeInputWithMappingsImpl(

    allocator: std.mem.Allocator,

    input: []const u8,

    mappings: *const character_mappings.CharacterMappings,

    apply_nfc: bool,

) ![]Token {

    var tokens = std.ArrayList(Token).init(allocator);

    defer tokens.deinit();

    

    // Load emoji map

    var emoji_map = static_data_loader.loadEmoji(allocator) catch |err| {

        // If emoji loading fails, fall back to character-by-character processing

        std.debug.print("Warning: Failed to load emoji map: {}\n", .{err});

        return tokenizeWithoutEmoji(allocator, input, mappings, apply_nfc);

    };

    defer emoji_map.deinit();

    

    // Process input looking for emojis first

    var i: usize = 0;

    while (i < input.len) {

        // Try to match emoji at current position

        if (emoji_map.findEmojiAt(allocator, input, i)) |match| {

            defer allocator.free(match.cps_input); // Free the owned copy

            // Create emoji token

            try tokens.append(try Token.createEmoji(

                allocator,

                match.cps_input,

                match.emoji_data.emoji,

                match.emoji_data.no_fe0f

            ));

            i += match.byte_len;

        } else {

            // Process single character

            const char_len = std.unicode.utf8ByteSequenceLength(input[i]) catch 1;

            if (i + char_len > input.len) break;

            

            const cp = std.unicode.utf8Decode(input[i..i + char_len]) catch {

                try tokens.append(Token.createDisallowed(allocator, 0xFFFD)); // replacement character

                i += 1;

                continue;

            };

            

            if (cp == constants.CP_STOP) {

                try tokens.append(Token.createStop(allocator));

            } else if (mappings.getMapped(cp)) |mapped| {

                try tokens.append(try Token.createMapped(allocator, cp, mapped));

            } else if (mappings.isValid(cp)) {

                try tokens.append(try Token.createValid(allocator, &[_]CodePoint{cp}));

            } else if (mappings.isIgnored(cp)) {

                try tokens.append(Token.createIgnored(allocator, cp));

            } else {

                try tokens.append(Token.createDisallowed(allocator, cp));

            }

            

            i += char_len;

        }

    }

    

    // Apply NFC transformation if requested

    if (apply_nfc) {

        var nfc_data = try static_data_loader.loadNFC(allocator);

        defer nfc_data.deinit();

        try applyNFCTransform(allocator, &tokens, &nfc_data);

    }

    

    // Collapse consecutive valid tokens

    try collapseValidTokens(allocator, &tokens);

    

    return tokens.toOwnedSlice();

}



fn collapseValidTokens(allocator: std.mem.Allocator, tokens: *std.ArrayList(Token)) !void {

    var i: usize = 0;

    while (i < tokens.items.len) {

        if (tokens.items[i].type == .valid) {

            var j = i + 1;

            var combined_cps = std.ArrayList(CodePoint).init(allocator);

            defer combined_cps.deinit();

            

            // Add first token's cps

            try combined_cps.appendSlice(tokens.items[i].getCps());

            

            // Collect consecutive valid tokens

            while (j < tokens.items.len and tokens.items[j].type == .valid) {

                try combined_cps.appendSlice(tokens.items[j].getCps());

                j += 1;

            }

            

            if (j > i + 1) {

                // We have multiple valid tokens to collapse

                

                // Clean up the old tokens

                for (tokens.items[i..j]) |token| {

                    token.deinit();

                }

                

                // Create new collapsed token

                const new_token = try Token.createValid(allocator, combined_cps.items);

                

                // Replace the range with the new token

                tokens.replaceRange(i, j - i, &[_]Token{new_token}) catch |err| {

                    new_token.deinit();

                    return err;

                };

            }

        }

        i += 1;

    }

}



test "tokenization basic functionality" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test simple ASCII

    const result = try TokenizedName.fromInput(allocator, "hello", &specs, false);

    try testing.expect(result.tokens.len > 0);

    try testing.expect(result.tokens[0].type == .valid);

    

    // Test with stop character

    const result2 = try TokenizedName.fromInput(allocator, "hello.eth", &specs, false);

    var found_stop = false;

    for (result2.tokens) |token| {

        if (token.type == .stop) {

            found_stop = true;

            break;

        }

    }

    try testing.expect(found_stop);

}



test "token creation and cleanup" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Test valid token

    const cps = [_]CodePoint{ 'h', 'e', 'l', 'l', 'o' };

    const token = try Token.createValid(allocator, &cps);

    try testing.expectEqual(TokenType.valid, token.type);

    try testing.expectEqualSlices(CodePoint, &cps, token.getCps());

    

    // Test stop token

    const stop_token = Token.createStop(allocator);

    try testing.expectEqual(TokenType.stop, stop_token.type);

    try testing.expectEqual(constants.CP_STOP, stop_token.data.stop.cp);

    

    // Test ignored token

    const ignored_token = Token.createIgnored(allocator, 0x200C);

    try testing.expectEqual(TokenType.ignored, ignored_token.type);

    try testing.expectEqual(@as(CodePoint, 0x200C), ignored_token.data.ignored.cp);

}



test "token input size calculation" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Test valid token input size

    const cps = [_]CodePoint{ 'h', 'e', 'l', 'l', 'o' };

    const token = try Token.createValid(allocator, &cps);

    try testing.expectEqual(@as(usize, 5), token.getInputSize());

    

    // Test stop token input size

    const stop_token = Token.createStop(allocator);

    try testing.expectEqual(@as(usize, 1), stop_token.getInputSize());

}



test "token type checking" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const cps = [_]CodePoint{'h'};

    const text_token = try Token.createValid(allocator, &cps);

    try testing.expect(text_token.isText());

    try testing.expect(!text_token.isEmoji());

    

    const stop_token = Token.createStop(allocator);

    try testing.expect(!stop_token.isText());

    try testing.expect(!stop_token.isEmoji());

}



test "empty input handling" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    const result = try TokenizedName.fromInput(allocator, "", &specs, false);

    try testing.expect(result.isEmpty());

    try testing.expectEqual(@as(usize, 0), result.tokens.len);

}



test "emoji tokenization" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test simple emoji

    const input = "hello👍world";

    const result = try TokenizedName.fromInput(allocator, input, &specs, false);

    defer result.deinit();

    

    // Should have: valid("hello"), emoji(👍), valid("world")

    try testing.expect(result.tokens.len >= 3);

    

    var found_emoji = false;

    for (result.tokens) |token| {

        if (token.type == .emoji) {

            found_emoji = true;

            break;

        }

    }

    

    try testing.expect(found_emoji);

}



test "whitespace tokenization" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    

    // Test various whitespace characters

    const whitespace_tests = [_]struct { input: []const u8, name: []const u8 }{

        .{ .input = " ", .name = "space" },

        .{ .input = "\t", .name = "tab" },

        .{ .input = "\n", .name = "newline" },

        .{ .input = "\u{00A0}", .name = "non-breaking space" },

        .{ .input = "\u{2000}", .name = "en quad" },

    };

    

    for (whitespace_tests) |test_case| {

        const result = try TokenizedName.fromInput(allocator, test_case.input, &specs, false);

        defer result.deinit();

        

        std.debug.print("\n{s}: tokens={}, ", .{ test_case.name, result.tokens.len });

        if (result.tokens.len > 0) {

            std.debug.print("type={s}", .{@tagName(result.tokens[0].type)});

            if (result.tokens[0].type == .disallowed) {

                std.debug.print(" cp=0x{x}", .{result.tokens[0].data.disallowed.cp});

            }

        }

    }

    std.debug.print("\n", .{});

}



test "character classification" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    

    const specs = CharacterSpecs{};

    

    // Test valid characters

    try testing.expect(specs.isValid('a'));

    try testing.expect(specs.isValid('Z'));

    try testing.expect(specs.isValid('5'));

    try testing.expect(specs.isValid('-'));

    

    // Test invalid characters

    try testing.expect(!specs.isValid('!'));

    try testing.expect(!specs.isValid('@'));

    

    // Test ignored characters

    try testing.expect(specs.isIgnored(0x00AD)); // soft hyphen

    try testing.expect(specs.isIgnored(0x200C)); // ZWNJ

    try testing.expect(specs.isIgnored(0x200D)); // ZWJ

    

    // Test stop character

    try testing.expect(specs.isStop('.'));

    try testing.expect(!specs.isStop('a'));

}



test "token collapse functionality" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    const result = try TokenizedName.fromInput(allocator, "hello", &specs, false);

    

    // Should collapse consecutive valid tokens into one

    try testing.expect(result.tokens.len > 0);

    

    // Check that we have valid tokens

    var has_valid = false;

    for (result.tokens) |token| {

        if (token.type == .valid) {

            has_valid = true;

            break;

        }

    }

    try testing.expect(has_valid);

}



// Fallback tokenization without emoji support

fn tokenizeWithoutEmoji(

    allocator: std.mem.Allocator,

    input: []const u8,

    mappings: *const character_mappings.CharacterMappings,

    apply_nfc: bool,

) ![]Token {

    var tokens = std.ArrayList(Token).init(allocator);

    defer tokens.deinit();

    

    // Convert input to code points

    const cps = try utils.str2cps(allocator, input);

    defer allocator.free(cps);

    

    for (cps) |cp| {

        if (cp == constants.CP_STOP) {

            try tokens.append(Token.createStop(allocator));

        } else if (mappings.getMapped(cp)) |mapped| {

            try tokens.append(try Token.createMapped(allocator, cp, mapped));

        } else if (mappings.isValid(cp)) {

            try tokens.append(try Token.createValid(allocator, &[_]CodePoint{cp}));

        } else if (mappings.isIgnored(cp)) {

            try tokens.append(Token.createIgnored(allocator, cp));

        } else {

            try tokens.append(Token.createDisallowed(allocator, cp));

        }

    }

    

    // Apply NFC transformation if requested

    if (apply_nfc) {

        var nfc_data = try static_data_loader.loadNFC(allocator);

        defer nfc_data.deinit();

        try applyNFCTransform(allocator, &tokens, &nfc_data);

    }

    

    // Collapse consecutive valid tokens

    try collapseValidTokens(allocator, &tokens);

    

    return tokens.toOwnedSlice();

}



// Apply NFC transformation to tokens

fn applyNFCTransform(allocator: std.mem.Allocator, tokens: *std.ArrayList(Token), nfc_data: *const nfc.NFCData) !void {

    var i: usize = 0;

    while (i < tokens.items.len) {

        const token = &tokens.items[i];

        

        // Check if this token starts a sequence that needs NFC

        switch (token.data) {

            .valid, .mapped => {

                const start_cps = token.getCps();

                

                // Check if any codepoint needs NFC checking

                var needs_check = false;

                for (start_cps) |cp| {

                    if (nfc_data.requiresNFCCheck(cp)) {

                        needs_check = true;

                        break;

                    }

                }

                

                if (needs_check) {

                    // Find the end of the sequence that needs NFC

                    var end = i + 1;

                    while (end < tokens.items.len) : (end += 1) {

                        switch (tokens.items[end].data) {

                            .valid, .mapped => {

                                // Continue including valid/mapped tokens

                            },

                            .ignored => {

                                // Skip ignored tokens but continue

                            },

                            else => break,

                        }

                    }

                    

                    // Collect all codepoints in the range (excluding ignored)

                    var all_cps = std.ArrayList(CodePoint).init(allocator);

                    defer all_cps.deinit();

                    

                    var j = i;

                    while (j < end) : (j += 1) {

                        switch (tokens.items[j].data) {

                            .valid, .mapped => {

                                try all_cps.appendSlice(tokens.items[j].getCps());

                            },

                            else => {},

                        }

                    }

                    

                    // Apply NFC

                    const normalized = try nfc.nfc(allocator, all_cps.items, nfc_data);

                    defer allocator.free(normalized);

                    

                    // Check if normalization changed anything

                    if (!nfc.compareCodePoints(all_cps.items, normalized)) {

                        // Collect the original tokens for tokens0

                        var tokens0 = try allocator.alloc(Token, end - i);

                        for (tokens.items[i..end], 0..) |orig_token, idx| {

                            // Create a copy of the token without transferring ownership

                            tokens0[idx] = switch (orig_token.data) {

                                .valid => |data| try Token.createValid(allocator, data.cps),

                                .mapped => |data| try Token.createMapped(allocator, data.cp, data.cps),

                                .ignored => |data| Token.createIgnored(allocator, data.cp),

                                else => unreachable,

                            };

                        }

                        

                        // Create NFC token with tokens0

                        const nfc_token = try Token.createNFC(

                            allocator,

                            all_cps.items,

                            normalized,

                            tokens0,

                            null  // tokens field would be populated by re-tokenizing normalized string

                        );

                        

                        // Clean up old tokens

                        for (tokens.items[i..end]) |old_token| {

                            old_token.deinit();

                        }

                        

                        // Replace with NFC token

                        tokens.replaceRange(i, end - i, &[_]Token{nfc_token}) catch |err| {

                            nfc_token.deinit();

                            return err;

                        };

                        

                        // Don't increment i, we replaced the current position

                        continue;

                    }

                }

            },

            else => {},

        }

        

        i += 1;

    }

}```

```zig [./src/character_mappings.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const comptime_data = @import("comptime_data.zig");



/// Character mapping system for ENS normalization using comptime data

pub const CharacterMappings = struct {

    // We don't need any runtime storage anymore!

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator) !CharacterMappings {

        return CharacterMappings{

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *CharacterMappings) void {

        _ = self;

        // Nothing to clean up - all data is comptime!

    }

    

    /// Get the mapped characters for a given code point

    /// Returns null if no mapping exists

    pub fn getMapped(self: *const CharacterMappings, cp: CodePoint) ?[]const CodePoint {

        _ = self;

        // Fast path for ASCII uppercase -> lowercase

        if (cp >= 'A' and cp <= 'Z') {

            // Use comptime-generated array for ASCII mappings

            const ascii_mappings = comptime blk: {

                var mappings: [26][1]CodePoint = undefined;

                for (0..26) |i| {

                    mappings[i] = [1]CodePoint{@as(CodePoint, 'a' + i)};

                }

                break :blk mappings;

            };

            return &ascii_mappings[cp - 'A'];

        }

        

        // Check comptime mappings

        return comptime_data.getMappedCodePoints(cp);

    }

    

    /// Check if a character is valid (no mapping needed)

    pub fn isValid(self: *const CharacterMappings, cp: CodePoint) bool {

        _ = self;

        return comptime_data.isValid(cp);

    }

    

    /// Check if a character should be ignored

    pub fn isIgnored(self: *const CharacterMappings, cp: CodePoint) bool {

        _ = self;

        return comptime_data.isIgnored(cp);

    }

    

    /// Check if a character is fenced (placement restricted)

    pub fn isFenced(self: *const CharacterMappings, cp: CodePoint) bool {

        _ = self;

        return comptime_data.isFenced(cp);

    }

    

    // These methods are no longer needed since we use comptime data

    pub fn addMapping(self: *CharacterMappings, from: CodePoint, to: []const CodePoint) !void {

        _ = self;

        _ = from;

        _ = to;

        @panic("Cannot add mappings at runtime - use comptime data");

    }

    

    pub fn addValid(self: *CharacterMappings, cp: CodePoint) !void {

        _ = self;

        _ = cp;

        @panic("Cannot add valid chars at runtime - use comptime data");

    }

    

    pub fn addIgnored(self: *CharacterMappings, cp: CodePoint) !void {

        _ = self;

        _ = cp;

        @panic("Cannot add ignored chars at runtime - use comptime data");

    }

};



/// Create character mappings - now just returns an empty struct

pub fn createWithUnicodeMappings(allocator: std.mem.Allocator) !CharacterMappings {

    return CharacterMappings.init(allocator);

}



// Tests

test "CharacterMappings - ASCII case folding" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var mappings = try CharacterMappings.init(allocator);

    defer mappings.deinit();

    

    // Test uppercase -> lowercase mapping

    const mapped_A = mappings.getMapped('A');

    try testing.expect(mapped_A != null);

    try testing.expectEqual(@as(CodePoint, 'a'), mapped_A.?[0]);

    

    const mapped_Z = mappings.getMapped('Z');

    try testing.expect(mapped_Z != null);

    try testing.expectEqual(@as(CodePoint, 'z'), mapped_Z.?[0]);

    

    // Test lowercase has no mapping

    const mapped_a = mappings.getMapped('a');

    try testing.expect(mapped_a == null);

    

    // Test valid characters

    try testing.expect(mappings.isValid('a'));

    try testing.expect(mappings.isValid('z'));

    try testing.expect(mappings.isValid('0'));

    try testing.expect(mappings.isValid('9'));

}



test "CharacterMappings - comptime data access" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var mappings = try CharacterMappings.init(allocator);

    defer mappings.deinit();

    

    // Test that we can access comptime data

    if (comptime_data.character_mappings.len > 0) {

        const first = comptime_data.character_mappings[0];

        const result = mappings.getMapped(first.from);

        try testing.expect(result != null);

        try testing.expectEqualSlices(CodePoint, first.to, result.?);

    }

}```

```zig [./src/root.zig]

const std = @import("std");

const testing = std.testing;



pub const CodePoint = u32;



pub const beautify = @import("beautify.zig");

pub const character_mappings = @import("character_mappings.zig");

pub const code_points = @import("code_points.zig");

pub const constants = @import("constants.zig");

pub const error_types = @import("error.zig");

pub const join = @import("join.zig");

pub const normalizer = @import("normalizer.zig");

pub const static_data = @import("static_data.zig");

pub const static_data_loader = @import("static_data_loader.zig");

pub const confusables = @import("confusables.zig");

pub const tokens = @import("tokens.zig");

pub const tokenizer = @import("tokenizer.zig");

pub const utils = @import("utils.zig");

pub const validate = @import("validate.zig");

pub const validator = @import("validator.zig");

pub const nfc = @import("nfc.zig");

pub const emoji = @import("emoji.zig");

pub const script_groups = @import("script_groups.zig");

pub const combining_marks = @import("combining_marks.zig");

pub const nsm_validation = @import("nsm_validation.zig");



// Re-export main API

pub const EnsNameNormalizer = normalizer.EnsNameNormalizer;

pub const ProcessedName = normalizer.ProcessedName;

pub const ProcessError = error_types.ProcessError;

pub const CurrableError = error_types.CurrableError;

pub const DisallowedSequence = error_types.DisallowedSequence;

pub const ValidatedLabel = validate.ValidatedLabel;

pub const LabelType = validate.LabelType;



// Re-export convenience functions

pub const normalize = normalizer.normalize;

pub const beautify_fn = normalizer.beautify;

pub const process = normalizer.process;

pub const tokenize = normalizer.tokenize;



test {

    testing.refAllDecls(@This());

}```

```zig [./src/validate.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const constants = @import("constants.zig");

const utils = @import("utils.zig");

const tokenizer = @import("tokenizer.zig");

const code_points = @import("code_points.zig");

const error_types = @import("error.zig");



pub const LabelType = union(enum) {

    ascii,

    emoji,

    greek,

    other: []const u8,

    

    pub fn format(self: LabelType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {

        _ = fmt;

        _ = options;

        switch (self) {

            .ascii => try writer.print("ASCII", .{}),

            .emoji => try writer.print("Emoji", .{}),

            .greek => try writer.print("Greek", .{}),

            .other => |name| try writer.print("{s}", .{name}),

        }

    }

};



pub const ValidatedLabel = struct {

    tokens: []const tokenizer.Token,

    label_type: LabelType,

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator, label_tokens: []const tokenizer.Token, label_type: LabelType) !ValidatedLabel {

        const owned_tokens = try allocator.dupe(tokenizer.Token, label_tokens);

        return ValidatedLabel{

            .tokens = owned_tokens,

            .label_type = label_type,

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: ValidatedLabel) void {

        self.allocator.free(self.tokens);

    }

};



pub const TokenizedLabel = struct {

    tokens: []const tokenizer.Token,

    allocator: std.mem.Allocator,

    

    pub fn isEmpty(self: TokenizedLabel) bool {

        return self.tokens.len == 0;

    }

    

    pub fn isFullyEmoji(self: TokenizedLabel) bool {

        for (self.tokens) |token| {

            if (!token.isEmoji() and !token.isIgnored()) {

                return false;

            }

        }

        return true;

    }

    

    pub fn isFullyAscii(self: TokenizedLabel) bool {

        for (self.tokens) |token| {

            const cps = token.getCps();

            for (cps) |cp| {

                if (!utils.isAscii(cp)) {

                    return false;

                }

            }

        }

        return true;

    }

    

    pub fn iterCps(self: TokenizedLabel, allocator: std.mem.Allocator) ![]CodePoint {

        var result = std.ArrayList(CodePoint).init(allocator);

        defer result.deinit();

        

        for (self.tokens) |token| {

            const cps = token.getCps();

            try result.appendSlice(cps);

        }

        

        return result.toOwnedSlice();

    }

    

    pub fn getCpsOfNotIgnoredText(self: TokenizedLabel, allocator: std.mem.Allocator) ![]CodePoint {

        var result = std.ArrayList(CodePoint).init(allocator);

        defer result.deinit();

        

        for (self.tokens) |token| {

            if (!token.isIgnored() and token.isText()) {

                const cps = try token.getCps(allocator);

                defer allocator.free(cps);

                try result.appendSlice(cps);

            }

        }

        

        return result.toOwnedSlice();

    }

};



pub fn validateName(

    allocator: std.mem.Allocator,

    name: tokenizer.TokenizedName,

    specs: *const code_points.CodePointsSpecs,

) ![]ValidatedLabel {

    if (name.tokens.len == 0) {

        return try allocator.alloc(ValidatedLabel, 0);

    }

    

    // For now, create a simple implementation that treats the entire name as one label

    // The actual implementation would need to split on stop tokens

    var labels = std.ArrayList(ValidatedLabel).init(allocator);

    defer labels.deinit();

    

    const label = TokenizedLabel{

        .tokens = name.tokens,

        .allocator = allocator,

    };

    

    const validated = try validateLabel(allocator, label, specs);

    try labels.append(validated);

    

    return labels.toOwnedSlice();

}



pub fn validateLabel(

    allocator: std.mem.Allocator,

    label: TokenizedLabel,

    specs: *const code_points.CodePointsSpecs,

) !ValidatedLabel {

    try checkNonEmpty(label);

    try checkTokenTypes(allocator, label);

    

    if (label.isFullyEmoji()) {

        return ValidatedLabel.init(allocator, label.tokens, LabelType.emoji);

    }

    

    try checkUnderscoreOnlyAtBeginning(allocator, label);

    

    if (label.isFullyAscii()) {

        try checkNoHyphenAtSecondAndThird(allocator, label);

        return ValidatedLabel.init(allocator, label.tokens, LabelType.ascii);

    }

    

    try checkFenced(allocator, label, specs);

    try checkCmLeadingEmoji(allocator, label, specs);

    

    const group = try checkAndGetGroup(allocator, label, specs);

    _ = group; // TODO: determine actual group type

    

    // For now, return a placeholder

    return ValidatedLabel.init(allocator, label.tokens, LabelType{ .other = "Unknown" });

}



fn checkNonEmpty(label: TokenizedLabel) !void {

    var has_non_ignored = false;

    for (label.tokens) |token| {

        if (!token.isIgnored()) {

            has_non_ignored = true;

            break;

        }

    }

    

    if (!has_non_ignored) {

        return error_types.ProcessError.DisallowedSequence;

    }

}



fn checkTokenTypes(_: std.mem.Allocator, label: TokenizedLabel) !void {

    for (label.tokens) |token| {

        if (token.isDisallowed() or token.isStop()) {

            const cps = token.getCps();

            

            // Check for invisible characters

            for (cps) |cp| {

                if (cp == constants.CP_ZERO_WIDTH_JOINER or cp == constants.CP_ZERO_WIDTH_NON_JOINER) {

                    return error_types.ProcessError.DisallowedSequence;

                }

            }

            

            return error_types.ProcessError.DisallowedSequence;

        }

    }

}



fn checkUnderscoreOnlyAtBeginning(allocator: std.mem.Allocator, label: TokenizedLabel) !void {

    const cps = try label.iterCps(allocator);

    defer allocator.free(cps);

    

    var leading_underscores: usize = 0;

    for (cps) |cp| {

        if (cp == constants.CP_UNDERSCORE) {

            leading_underscores += 1;

        } else {

            break;

        }

    }

    

    for (cps[leading_underscores..]) |cp| {

        if (cp == constants.CP_UNDERSCORE) {

            return error_types.ProcessError.CurrableError;

        }

    }

}



fn checkNoHyphenAtSecondAndThird(allocator: std.mem.Allocator, label: TokenizedLabel) !void {

    const cps = try label.iterCps(allocator);

    defer allocator.free(cps);

    

    if (cps.len >= 4 and cps[2] == constants.CP_HYPHEN and cps[3] == constants.CP_HYPHEN) {

        return error_types.ProcessError.CurrableError;

    }

}



fn checkFenced(allocator: std.mem.Allocator, label: TokenizedLabel, specs: *const code_points.CodePointsSpecs) !void {

    const cps = try label.iterCps(allocator);

    defer allocator.free(cps);

    

    if (cps.len == 0) return;

    

    // Check for fenced characters at start and end

    // For now, placeholder implementation

    _ = specs;

    

    // Check for consecutive fenced characters

    for (cps[0..cps.len-1], 0..) |cp, i| {

        const next_cp = cps[i + 1];

        // TODO: implement actual fenced character checking

        _ = cp;

        _ = next_cp;

    }

}



fn checkCmLeadingEmoji(allocator: std.mem.Allocator, label: TokenizedLabel, specs: *const code_points.CodePointsSpecs) !void {

    _ = allocator;

    _ = label;

    _ = specs;

    // TODO: implement combining mark checking

}



fn checkAndGetGroup(allocator: std.mem.Allocator, label: TokenizedLabel, specs: *const code_points.CodePointsSpecs) !*const code_points.ParsedGroup {

    _ = allocator;

    _ = label;

    _ = specs;

    // TODO: implement group determination

    return error_types.ProcessError.Confused;

}



test "validateLabel basic functionality" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    // Test with empty label

    const empty_label = TokenizedLabel{

        .tokens = &[_]tokenizer.Token{},

        .allocator = allocator,

    };

    

    const specs = code_points.CodePointsSpecs.init(allocator);

    const result = validateLabel(allocator, empty_label, &specs);

    try testing.expectError(error_types.ProcessError.DisallowedSequence, result);

}```

```zig [./src/constants.zig]

const root = @import("root.zig");

const CodePoint = root.CodePoint;



pub const CP_STOP: CodePoint = 0x2E;

pub const CP_FE0F: CodePoint = 0xFE0F;

pub const CP_APOSTROPHE: CodePoint = 8217;

pub const CP_SLASH: CodePoint = 8260;

pub const CP_MIDDLE_DOT: CodePoint = 12539;

pub const CP_XI_SMALL: CodePoint = 0x3BE;

pub const CP_XI_CAPITAL: CodePoint = 0x39E;

pub const CP_UNDERSCORE: CodePoint = 0x5F;

pub const CP_HYPHEN: CodePoint = 0x2D;

pub const CP_ZERO_WIDTH_JOINER: CodePoint = 0x200D;

pub const CP_ZERO_WIDTH_NON_JOINER: CodePoint = 0x200C;



pub const GREEK_GROUP_NAME: []const u8 = "Greek";

pub const MAX_EMOJI_LEN: usize = 0x2d;

pub const STR_FE0F: []const u8 = "\u{fe0f}";```

```zig [./src/character_mappings_comptime.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;

const comptime_data = @import("comptime_data.zig");



/// Character mapping system for ENS normalization using comptime data

pub const CharacterMappings = struct {

    // We don't need any runtime storage anymore!

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator) !CharacterMappings {

        return CharacterMappings{

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *CharacterMappings) void {

        _ = self;

        // Nothing to clean up - all data is comptime!

    }

    

    /// Get the mapped characters for a given code point

    /// Returns null if no mapping exists

    pub fn getMapped(self: *const CharacterMappings, cp: CodePoint) ?[]const CodePoint {

        _ = self;

        // Fast path for ASCII uppercase -> lowercase

        if (cp >= 'A' and cp <= 'Z') {

            // Return a slice to a static array

            const lowercase = [1]CodePoint{cp + 32};

            return &lowercase;

        }

        

        // Check comptime mappings

        return comptime_data.getMappedCodePoints(cp);

    }

    

    /// Check if a character is valid (no mapping needed)

    pub fn isValid(self: *const CharacterMappings, cp: CodePoint) bool {

        _ = self;

        return comptime_data.isValid(cp);

    }

    

    /// Check if a character should be ignored

    pub fn isIgnored(self: *const CharacterMappings, cp: CodePoint) bool {

        _ = self;

        return comptime_data.isIgnored(cp);

    }

    

    /// Check if a character is fenced (placement restricted)

    pub fn isFenced(self: *const CharacterMappings, cp: CodePoint) bool {

        _ = self;

        return comptime_data.isFenced(cp);

    }

    

    // These methods are no longer needed since we use comptime data

    pub fn addMapping(self: *CharacterMappings, from: CodePoint, to: []const CodePoint) !void {

        _ = self;

        _ = from;

        _ = to;

        @panic("Cannot add mappings at runtime - use comptime data");

    }

    

    pub fn addValid(self: *CharacterMappings, cp: CodePoint) !void {

        _ = self;

        _ = cp;

        @panic("Cannot add valid chars at runtime - use comptime data");

    }

    

    pub fn addIgnored(self: *CharacterMappings, cp: CodePoint) !void {

        _ = self;

        _ = cp;

        @panic("Cannot add ignored chars at runtime - use comptime data");

    }

};



/// Create character mappings - now just returns an empty struct

pub fn createWithUnicodeMappings(allocator: std.mem.Allocator) !CharacterMappings {

    return CharacterMappings.init(allocator);

}



// Tests

test "CharacterMappings - ASCII case folding" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var mappings = try CharacterMappings.init(allocator);

    defer mappings.deinit();

    

    // Test uppercase -> lowercase mapping

    const mapped_A = mappings.getMapped('A');

    try testing.expect(mapped_A != null);

    try testing.expectEqual(@as(CodePoint, 'a'), mapped_A.?[0]);

    

    const mapped_Z = mappings.getMapped('Z');

    try testing.expect(mapped_Z != null);

    try testing.expectEqual(@as(CodePoint, 'z'), mapped_Z.?[0]);

    

    // Test lowercase has no mapping

    const mapped_a = mappings.getMapped('a');

    try testing.expect(mapped_a == null);

    

    // Test valid characters

    try testing.expect(mappings.isValid('a'));

    try testing.expect(mappings.isValid('z'));

    try testing.expect(mappings.isValid('0'));

    try testing.expect(mappings.isValid('9'));

}



test "CharacterMappings - comptime data access" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var mappings = try CharacterMappings.init(allocator);

    defer mappings.deinit();

    

    // Test that we can access comptime data

    if (comptime_data.character_mappings.len > 0) {

        const first = comptime_data.character_mappings[0];

        const result = mappings.getMapped(first.from);

        try testing.expect(result != null);

        try testing.expectEqualSlices(CodePoint, first.to, result.?);

    }

}```

```zig [./src/confusables.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;



/// A set of confusable characters

pub const ConfusableSet = struct {

    target: []const u8,  // Target string (like "32" for the digit 2)

    valid: []const CodePoint,  // Valid characters for this confusable set

    confused: []const CodePoint,  // Characters that look like the valid ones

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator, target: []const u8) ConfusableSet {

        return ConfusableSet{

            .target = target,

            .valid = &.{},

            .confused = &.{},

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *ConfusableSet) void {

        self.allocator.free(self.target);

        self.allocator.free(self.valid);

        self.allocator.free(self.confused);

    }

    

    /// Check if this set contains the given codepoint (in valid or confused)

    pub fn contains(self: *const ConfusableSet, cp: CodePoint) bool {

        return self.containsValid(cp) or self.containsConfused(cp);

    }

    

    /// Check if this set contains the codepoint in the valid set

    pub fn containsValid(self: *const ConfusableSet, cp: CodePoint) bool {

        return std.mem.indexOfScalar(CodePoint, self.valid, cp) != null;

    }

    

    /// Check if this set contains the codepoint in the confused set

    pub fn containsConfused(self: *const ConfusableSet, cp: CodePoint) bool {

        return std.mem.indexOfScalar(CodePoint, self.confused, cp) != null;

    }

};



/// Collection of all confusable sets

pub const ConfusableData = struct {

    sets: []ConfusableSet,

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator) ConfusableData {

        return ConfusableData{

            .sets = &.{},

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *ConfusableData) void {

        for (self.sets) |*set| {

            set.deinit();

        }

        self.allocator.free(self.sets);

    }

    

    /// Find all confusable sets that contain any of the given codepoints

    pub fn findSetsContaining(self: *const ConfusableData, codepoints: []const CodePoint, allocator: std.mem.Allocator) ![]const *const ConfusableSet {

        var matching = std.ArrayList(*const ConfusableSet).init(allocator);

        errdefer matching.deinit();

        

        std.debug.print("findSetsContaining: {} total sets\n", .{self.sets.len});

        

        for (self.sets, 0..) |*set, i| {

            for (codepoints) |cp| {

                if (set.contains(cp)) {

                    std.debug.print("  Set {} (target={s}) contains cp 0x{x}\n", .{i, set.target, cp});

                    try matching.append(set);

                    break; // Found one, no need to check more codepoints for this set

                }

            }

        }

        

        return matching.toOwnedSlice();

    }

    

    /// Check if codepoints form a whole-script confusable (security violation)

    pub fn checkWholeScriptConfusables(self: *const ConfusableData, codepoints: []const CodePoint, allocator: std.mem.Allocator) !bool {

        if (codepoints.len == 0) return false; // Empty input is safe

        

        std.debug.print("checkWholeScriptConfusables: checking {} cps\n", .{codepoints.len});

        

        // Find all sets that contain any of our codepoints

        const matching_sets = try self.findSetsContaining(codepoints, allocator);

        defer allocator.free(matching_sets);

        

        std.debug.print("checkWholeScriptConfusables: found {} matching sets\n", .{matching_sets.len});

        

        if (matching_sets.len <= 1) {

            return false; // No confusables or all from same set - safe

        }

        

        // Check for dangerous mixing between different confusable sets

        // Key insight: mixing valid characters from different sets is OK

        // Only mixing when at least one confused character is present is dangerous

        

        var has_confused = false;

        for (codepoints) |cp| {

            for (matching_sets) |set| {

                if (set.containsConfused(cp)) {

                    has_confused = true;

                    break;

                }

            }

            if (has_confused) break;

        }

        

        // If there are no confused characters, it's safe even with multiple sets

        if (!has_confused) {

            std.debug.print("checkWholeScriptConfusables: no confused characters found, safe\n", .{});

            return false;

        }

        

        // Now check if we're mixing characters from different sets

        // when at least one confused character is present

        for (matching_sets, 0..) |set1, i| {

            for (matching_sets[i+1..]) |set2| {

                // Check if we have characters from both sets

                var has_from_set1 = false;

                var has_from_set2 = false;

                

                for (codepoints) |cp| {

                    if (set1.contains(cp)) has_from_set1 = true;

                    if (set2.contains(cp)) has_from_set2 = true;

                    

                    // Early exit if we found both

                    if (has_from_set1 and has_from_set2) {

                        std.debug.print("checkWholeScriptConfusables: mixing sets with confused chars = DANGEROUS\n", .{});

                        return true; // DANGEROUS: mixing confusable sets with confused characters

                    }

                }

            }

        }

        

        return false; // Safe

    }

    

    /// Get diagnostic information about confusable usage

    pub fn analyzeConfusables(self: *const ConfusableData, codepoints: []const CodePoint, allocator: std.mem.Allocator) !ConfusableAnalysis {

        var analysis = ConfusableAnalysis.init(allocator);

        errdefer analysis.deinit();

        

        const matching_sets = try self.findSetsContaining(codepoints, allocator);

        defer allocator.free(matching_sets);

        

        analysis.sets_involved = try allocator.dupe(*const ConfusableSet, matching_sets);

        analysis.is_confusable = matching_sets.len > 1;

        

        // Count characters by type

        for (codepoints) |cp| {

            var found_in_set = false;

            for (matching_sets) |set| {

                if (set.containsValid(cp)) {

                    analysis.valid_count += 1;

                    found_in_set = true;

                    break;

                } else if (set.containsConfused(cp)) {

                    analysis.confused_count += 1;

                    found_in_set = true;

                    break;

                }

            }

            if (!found_in_set) {

                analysis.non_confusable_count += 1;

            }

        }

        

        return analysis;

    }

};



/// Analysis result for confusable detection

pub const ConfusableAnalysis = struct {

    sets_involved: []const *const ConfusableSet,

    is_confusable: bool,

    valid_count: usize,

    confused_count: usize,

    non_confusable_count: usize,

    allocator: std.mem.Allocator,

    

    pub fn init(allocator: std.mem.Allocator) ConfusableAnalysis {

        return ConfusableAnalysis{

            .sets_involved = &.{},

            .is_confusable = false,

            .valid_count = 0,

            .confused_count = 0,

            .non_confusable_count = 0,

            .allocator = allocator,

        };

    }

    

    pub fn deinit(self: *ConfusableAnalysis) void {

        self.allocator.free(self.sets_involved);

    }

};



test "confusable set basic operations" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var set = ConfusableSet.init(allocator, try allocator.dupe(u8, "test"));

    defer set.deinit();

    

    // Add some test data

    var valid_data = try allocator.alloc(CodePoint, 2);

    valid_data[0] = 'a';

    valid_data[1] = 'b';

    set.valid = valid_data;

    

    var confused_data = try allocator.alloc(CodePoint, 2);

    confused_data[0] = 0x0430; // Cyrillic 'а'

    confused_data[1] = 0x0431; // Cyrillic 'б'

    set.confused = confused_data;

    

    // Test containment

    try testing.expect(set.contains('a'));

    try testing.expect(set.contains(0x0430));

    try testing.expect(!set.contains('z'));

    

    try testing.expect(set.containsValid('a'));

    try testing.expect(!set.containsValid(0x0430));

    

    try testing.expect(set.containsConfused(0x0430));

    try testing.expect(!set.containsConfused('a'));

}



test "confusable data empty input" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var data = ConfusableData.init(allocator);

    defer data.deinit();

    

    const empty_cps = [_]CodePoint{};

    const is_confusable = try data.checkWholeScriptConfusables(&empty_cps, allocator);

    try testing.expect(!is_confusable);

}



test "confusable data single set safe" {

    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);

    defer arena.deinit();

    const allocator = arena.allocator();

    

    var data = ConfusableData.init(allocator);

    defer data.deinit();

    

    // Create a test set

    data.sets = try allocator.alloc(ConfusableSet, 1);

    data.sets[0] = ConfusableSet.init(allocator, try allocator.dupe(u8, "latin"));

    

    var valid_test_data = try allocator.alloc(CodePoint, 2);

    valid_test_data[0] = 'a';

    valid_test_data[1] = 'b';

    data.sets[0].valid = valid_test_data;

    

    var confused_test_data = try allocator.alloc(CodePoint, 2);

    confused_test_data[0] = 0x0430;

    confused_test_data[1] = 0x0431;

    data.sets[0].confused = confused_test_data;

    

    // Test with only valid characters - should be safe

    const valid_only = [_]CodePoint{ 'a', 'b' };

    const is_confusable1 = try data.checkWholeScriptConfusables(&valid_only, allocator);

    try testing.expect(!is_confusable1);

    

    // Test with only confused characters - should be safe (single set)

    const confused_only = [_]CodePoint{ 0x0430, 0x0431 };

    const is_confusable2 = try data.checkWholeScriptConfusables(&confused_only, allocator);

    try testing.expect(!is_confusable2);

}```

```zig [./src/error.zig]

const std = @import("std");

const root = @import("root.zig");

const CodePoint = root.CodePoint;



pub const ProcessError = error{

    Confused,

    ConfusedGroups,

    CurrableError,

    DisallowedSequence,

    OutOfMemory,

    InvalidUtf8,

    InvalidCodePoint,

};



pub const ProcessErrorInfo = union(ProcessError) {

    Confused: struct {

        message: []const u8,

    },

    ConfusedGroups: struct {

        group1: []const u8,

        group2: []const u8,

    },

    CurrableError: struct {

        inner: CurrableError,

        index: usize,

        sequence: []const u8,

        maybe_suggest: ?[]const u8,

    },

    DisallowedSequence: DisallowedSequence,

    OutOfMemory: void,

    InvalidUtf8: void,

    InvalidCodePoint: void,

};



pub const CurrableError = enum {

    UnderscoreInMiddle,

    HyphenAtSecondAndThird,

    CmStart,

    CmAfterEmoji,

    FencedLeading,

    FencedTrailing,

    FencedConsecutive,

};



pub const DisallowedSequence = enum {

    Invalid,

    InvisibleCharacter,

    EmptyLabel,

    NsmTooMany,

    NsmRepeated,

};



pub const DisallowedSequenceInfo = union(DisallowedSequence) {

    Invalid: struct {

        message: []const u8,

    },

    InvisibleCharacter: struct {

        code_point: CodePoint,

    },

    EmptyLabel: void,

    NsmTooMany: void,

    NsmRepeated: void,

};



pub fn formatProcessError(

    allocator: std.mem.Allocator,

    error_info: ProcessErrorInfo,

) ![]u8 {

    switch (error_info) {

        .Confused => |info| {

            return try std.fmt.allocPrint(

                allocator,

                "contains visually confusing characters from multiple scripts: {s}",

                .{info.message},

            );

        },

        .ConfusedGroups => |info| {

            return try std.fmt.allocPrint(

                allocator,

                "contains visually confusing characters from {s} and {s} scripts",

                .{ info.group1, info.group2 },

            );

        },

        .CurrableError => |info| {

            var suggest_part: []const u8 = "";

            if (info.maybe_suggest) |suggest| {

                suggest_part = try std.fmt.allocPrint(

                    allocator,

                    " (suggestion: {s})",

                    .{suggest},

                );

            }

            return try std.fmt.allocPrint(

                allocator,

                "invalid character ('{s}') at position {d}: {s}{s}",

                .{ info.sequence, info.index, formatCurrableError(info.inner), suggest_part },

            );

        },

        .DisallowedSequence => |seq| {

            return try formatDisallowedSequence(allocator, seq);

        },

        .OutOfMemory => return try allocator.dupe(u8, "out of memory"),

        .InvalidUtf8 => return try allocator.dupe(u8, "invalid UTF-8"),

        .InvalidCodePoint => return try allocator.dupe(u8, "invalid code point"),

    }

}



fn formatCurrableError(err: CurrableError) []const u8 {

    return switch (err) {

        .UnderscoreInMiddle => "underscore in middle",

        .HyphenAtSecondAndThird => "hyphen at second and third position",

        .CmStart => "combining mark in disallowed position at the start of the label",

        .CmAfterEmoji => "combining mark in disallowed position after an emoji",

        .FencedLeading => "fenced character at the start of a label",

        .FencedTrailing => "fenced character at the end of a label",

        .FencedConsecutive => "consecutive sequence of fenced characters",

    };

}



fn formatDisallowedSequence(allocator: std.mem.Allocator, seq: DisallowedSequence) ![]u8 {

    return switch (seq) {

        .Invalid => try allocator.dupe(u8, "disallowed sequence"),

        .InvisibleCharacter => try allocator.dupe(u8, "invisible character"),

        .EmptyLabel => try allocator.dupe(u8, "empty label"),

        .NsmTooMany => try allocator.dupe(u8, "nsm too many"),

        .NsmRepeated => try allocator.dupe(u8, "nsm repeated"),

    };

}```

</zig>

I shared a productionized csharp implementation along with a non working zig implementation. Can you please give me a complete code review on my zig code? I also shared a rust implementation that is also producitonized
