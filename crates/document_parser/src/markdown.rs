use super::{push_block, ParsedDocument};
use refract_core::BlockKind;

/// Minimal, dependency-free Markdown block parser: headings, lists, quotes,
/// fenced code and paragraphs.
pub fn parse(input: &str) -> ParsedDocument {
    let mut doc = ParsedDocument::default();
    let mut fence: Option<(u8, usize)> = None;
    let mut code_buf: Vec<&str> = Vec::new();

    for line in input.lines() {
        let t = line.trim_end();
        let marker = t.as_bytes().first().copied().filter(|b| *b == b'`' || *b == b'~');
        let count = marker.map_or(0, |m| t.bytes().take_while(|&b| b == m).count());
        if let Some((open_marker, open_len)) = fence {
            // A closing fence must use the same marker, be at least as long
            // as its opening fence, and have only trailing whitespace.
            if marker == Some(open_marker) && count >= open_len && t[count..].trim().is_empty() {
                push_block(&mut doc.blocks, BlockKind::Code, &code_buf.join("\n"));
                code_buf.clear();
                fence = None;
            } else {
                code_buf.push(t);
            }
            continue;
        }
        if let Some(m) = marker {
            // Backticks in a backtick fence's info string are not permitted.
            if count >= 3 && (m != b'`' || !t[count..].contains('`')) {
                fence = Some((m, count));
                continue;
            }
        }
        if t.is_empty() || matches!(t, "#" | "##" | "###") {
            continue;
        }
        // ATX headings require a space or tab after their marker.
        let heading = |prefix: &str| t.strip_prefix(prefix)
            .and_then(|rest| rest.strip_prefix(' ').or_else(|| rest.strip_prefix('\t')));
        if let Some(rest) = heading("###") {
            push_block(&mut doc.blocks, BlockKind::Heading3, rest);
        } else if let Some(rest) = heading("##") {
            push_block(&mut doc.blocks, BlockKind::Heading2, rest);
        } else if let Some(rest) = heading("#") {
            let rest = rest.trim_start();
            push_block(&mut doc.blocks, BlockKind::Heading1, rest);
            if doc.title.is_none() && !rest.is_empty() {
                doc.title = Some(rest.to_string());
            }
        } else if let Some(rest) = t.strip_prefix("> ") {
            push_block(&mut doc.blocks, BlockKind::Quote, rest);
        } else if t.starts_with("- ") || t.starts_with("* ") {
            push_block(&mut doc.blocks, BlockKind::ListItem, &t[2..]);
        } else if let Some(rest) = ordered_list_content(t) {
            push_block(&mut doc.blocks, BlockKind::ListItem, rest);
        } else {
            push_block(&mut doc.blocks, BlockKind::Paragraph, t);
        }
    }
    if !code_buf.is_empty() {
        push_block(&mut doc.blocks, BlockKind::Code, &code_buf.join("\n"));
    }
    if fence.is_some() {
        doc.warnings.push("Markdown code fence is not closed; remaining lines are treated as code. Review the original for formatting.".into());
    }
    // Preview text should reflect the same extracted blocks as the reader,
    // not raw Markdown markers or text from empty syntax-only blocks.
    doc.plain_text = doc.blocks.iter().map(|b| b.text.as_str()).collect::<Vec<_>>().join("\n\n");
    doc
}


// Recognize only an unindented decimal marker followed by '.' or ')' and
// whitespace. Longer digit runs and dates without a separating space remain text.
fn ordered_list_content(line: &str) -> Option<&str> {
    let digits = line.bytes().take_while(u8::is_ascii_digit).count();
    if !(1..=9).contains(&digits) { return None; }
    let rest = line.get(digits..)?;
    let rest = rest.strip_prefix('.').or_else(|| rest.strip_prefix(')'))?;
    rest.strip_prefix(' ').or_else(|| rest.strip_prefix('\t'))
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preview_text_matches_reader_blocks() {
        let parsed = parse("# Title\n\n1. First\n2. Second");
        assert_eq!(parsed.plain_text, "Title\n\nFirst\n\nSecond");
    }

    #[test]
    fn warns_only_when_fence_remains_open() {
        assert!(parse("```\ncode").warnings.iter().any(|w| w.contains("not closed")));
        assert!(parse("~~~\ncode\n~~~").warnings.is_empty());
        assert!(parse("text\n```\n```").warnings.is_empty());
    }

    #[test]
    fn hashtags_and_unsupported_headings_are_not_document_titles() {
        let parsed = parse("#hashtag\n#### Deep heading\n# Actual title");
        assert_eq!(parsed.title.as_deref(), Some("Actual title"));
        assert_eq!(parsed.blocks[0].kind, BlockKind::Paragraph);
        assert_eq!(parsed.blocks[0].text, "#hashtag");
        assert_eq!(parsed.blocks[1].kind, BlockKind::Paragraph);
        assert_eq!(parsed.blocks[1].text, "#### Deep heading");
        assert_eq!(parsed.blocks[2].kind, BlockKind::Heading1);
    }

    #[test]
    fn tabs_separate_heading_markers_from_text() {
        let parsed = parse("#\tTitle\n##\tSecond\n###\tThird\n#hashtag");
        assert_eq!(parsed.title.as_deref(), Some("Title"));
        assert_eq!(parsed.blocks.iter().map(|b| b.kind).collect::<Vec<_>>(),
            vec![BlockKind::Heading1, BlockKind::Heading2, BlockKind::Heading3, BlockKind::Paragraph]);
    }

    #[test]
    fn ordered_items_require_valid_markers() {
        let parsed = parse("1. First\n12)\tSecond\n2026.11.06\n1234567890. Too long");
        assert_eq!(parsed.blocks.iter().map(|b| b.kind).collect::<Vec<_>>(),
            vec![BlockKind::ListItem, BlockKind::ListItem, BlockKind::Paragraph, BlockKind::Paragraph]);
        assert_eq!(parsed.blocks[0].text, "First");
        assert_eq!(parsed.blocks[1].text, "Second");
    }

    #[test]
    fn tilde_fences_keep_other_fence_markers_as_code() {
        let parsed = parse("~~~~rust\nfirst\n~~~\n```\nlast\n~~~~\nafter");
        assert_eq!(parsed.blocks.len(), 2);
        assert_eq!(parsed.blocks[0].kind, BlockKind::Code);
        assert_eq!(parsed.blocks[0].text, "first ~~~ ``` last");
        assert_eq!(parsed.blocks[1].text, "after");
    }

    #[test]
    fn fence_length_and_closing_info_do_not_drop_code() {
        let parsed = parse("````text\nfirst\n```\n```language\nlast\n````\nafter");
        assert_eq!(parsed.blocks.len(), 2);
        assert_eq!(parsed.blocks[0].kind, BlockKind::Code);
        assert_eq!(parsed.blocks[0].text, "first ``` ```language last");
        assert_eq!(parsed.blocks[1].text, "after");
        let unclosed = parse("```\ncode\n```language\nstill code");
        assert_eq!(unclosed.blocks.len(), 1);
        assert_eq!(unclosed.blocks[0].text, "code ```language still code");
    }
}
