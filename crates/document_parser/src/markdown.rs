use super::{normalize_ws, push_block, ParsedDocument};
use refract_core::BlockKind;

/// Minimal, dependency-free Markdown block parser: headings, lists, quotes,
/// fenced code and paragraphs.
pub fn parse(input: &str) -> ParsedDocument {
    let mut doc = ParsedDocument {
        plain_text: normalize_ws(input),
        ..Default::default()
    };
    let mut in_code = false;
    let mut code_buf: Vec<&str> = Vec::new();

    for line in input.lines() {
        let t = line.trim_end();
        if t.starts_with("```") {
            if in_code {
                push_block(&mut doc.blocks, BlockKind::Code, &code_buf.join("\n"));
                code_buf.clear();
            }
            in_code = !in_code;
            continue;
        }
        if in_code {
            code_buf.push(t);
            continue;
        }
        if t.is_empty() {
            continue;
        }
        if let Some(rest) = t.strip_prefix("### ") {
            push_block(&mut doc.blocks, BlockKind::Heading3, rest);
        } else if let Some(rest) = t.strip_prefix("## ") {
            push_block(&mut doc.blocks, BlockKind::Heading2, rest);
        } else if let Some(rest) = t.strip_prefix('#') {
            let rest = rest.trim_start_matches('#').trim_start();
            push_block(&mut doc.blocks, BlockKind::Heading1, rest);
            if doc.title.is_none() && !rest.is_empty() {
                doc.title = Some(rest.to_string());
            }
        } else if let Some(rest) = t.strip_prefix("> ") {
            push_block(&mut doc.blocks, BlockKind::Quote, rest);
        } else if t.starts_with("- ") || t.starts_with("* ") {
            push_block(&mut doc.blocks, BlockKind::ListItem, &t[2..]);
        } else {
            push_block(&mut doc.blocks, BlockKind::Paragraph, t);
        }
    }
    if !code_buf.is_empty() {
        push_block(&mut doc.blocks, BlockKind::Code, &code_buf.join("\n"));
    }
    doc
}
