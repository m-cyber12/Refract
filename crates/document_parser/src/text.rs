use super::{paragraphs_from_plain, ParsedDocument};

pub fn parse(input: &str) -> ParsedDocument {
    let blocks = paragraphs_from_plain(input);
    let plain_text = blocks
        .iter()
        .map(|b| b.text.as_str())
        .collect::<Vec<_>>()
        .join("\n\n");
    ParsedDocument {
        title: None,
        author: None,
        language: None,
        blocks,
        plain_text,
        warnings: Vec::new(),
    }
}
