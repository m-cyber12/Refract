use super::{normalize_ws, push_block, ParsedDocument};
use refract_core::BlockKind;

/// Minimal, dependency-free Markdown block parser: headings, lists, quotes,
/// fenced code and paragraphs.
pub fn parse(input: &str) -> ParsedDocument {
    let mut doc = ParsedDocument {
        plain_text: normalize_ws(input),
        ..Default::default()
    };
    let mut fence_len: Option<usize> = None;
    let mut code_buf: Vec<&str> = Vec::new();

    for line in input.lines() {
        let t = line.trim_end();
        let ticks = t.bytes().take_while(|&b| b == b'`').count();
        if let Some(open_len) = fence_len {
            // A closing fence must be at least as long as its opening fence
            // and contain only trailing whitespace. A shorter fence or an
            // info string here is code, not a reason to drop later lines.
            if ticks >= open_len && t[ticks..].trim().is_empty() {
                push_block(&mut doc.blocks, BlockKind::Code, &code_buf.join("\n"));
                code_buf.clear();
                fence_len = None;
            } else {
                code_buf.push(t);
            }
            continue;
        }
        if ticks >= 3 && !t[ticks..].contains('`') {
            fence_len = Some(ticks);
            continue;
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
        } else {
            push_block(&mut doc.blocks, BlockKind::Paragraph, t);
        }
    }
    if !code_buf.is_empty() {
        push_block(&mut doc.blocks, BlockKind::Code, &code_buf.join("\n"));
    }
    doc
}


#[cfg(test)]
mod tests {
    use super::*;

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
