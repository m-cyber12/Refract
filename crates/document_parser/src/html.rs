//! Sanitizing HTML parser.
//!
//! The input is parsed with html5ever (via `scraper`). Script/style/noscript/
//! iframe content is never read, and output blocks contain plain text only,
//! so imported markup can never execute inside REFRACT.

use super::{normalize_ws, push_block, ParsedDocument};
use refract_core::{BlockKind, RefractResult};
use scraper::{Html, Selector};

fn select_first(doc: &Html, selector: &str) -> Option<String> {
    let sel = Selector::parse(selector).ok()?;
    doc.select(&sel)
        .next()
        .map(|el| normalize_ws(&el.text().collect::<String>()))
        .filter(|s| !s.is_empty())
}

pub fn parse(input: &str) -> RefractResult<ParsedDocument> {
    let doc = Html::parse_document(input);

    let title = select_first(&doc, "head title")
        .or_else(|| select_first(&doc, "meta[property='og:title']").map(|_| {
            // og:title lives in an attribute, not text; read it explicitly.
            let sel = Selector::parse("meta[property='og:title']").unwrap();
            doc.select(&sel)
                .next()
                .and_then(|el| el.value().attr("content").map(|s| s.to_string()))
                .unwrap_or_default()
        }))
        .filter(|s| !s.is_empty());

    let author = {
        let sel = Selector::parse("meta[name='author']").unwrap();
        doc.select(&sel)
            .next()
            .and_then(|el| el.value().attr("content").map(|s| s.to_string()))
    };

    let language = {
        let sel = Selector::parse("html").unwrap();
        doc.select(&sel)
            .next()
            .and_then(|el| el.value().attr("lang").map(|s| s.to_string()))
    };

    // Main-content identification: prefer semantic containers, fall back to body.
    let root = ["article", "main", "[role='main']", "#content", ".content", "body"]
        .iter()
        .find_map(|s| Selector::parse(s).ok().and_then(|sel| doc.select(&sel).next()));

    let mut parsed = ParsedDocument {
        title,
        author,
        language,
        ..Default::default()
    };

    let Some(root) = root else {
        return Ok(parsed);
    };

    // Walk the main container's descendants in document order.
    for node in root.descendants() {
        let Some(el) = scraper::ElementRef::wrap(node) else {
            continue;
        };
        let name = el.value().name();
        // Noise classification: skip non-content subtrees entirely.
        if matches!(
            name,
            "script" | "style" | "noscript" | "iframe" | "nav" | "footer" | "aside" | "form"
        ) {
            continue;
        }
        let kind = if el.value().name() == "h1" {
            Some(BlockKind::Heading1)
        } else if el.value().name() == "h2" {
            Some(BlockKind::Heading2)
        } else if el.value().name() == "h3" {
            Some(BlockKind::Heading3)
        } else if name == "p" {
            Some(BlockKind::Paragraph)
        } else if name == "li" {
            Some(BlockKind::ListItem)
        } else if name == "blockquote" {
            Some(BlockKind::Quote)
        } else if name == "pre" || name == "code" {
            Some(BlockKind::Code)
        } else {
            None
        };
        match kind {
            Some(k) => {
                let text = normalize_ws(&el.text().collect::<String>());
                push_block(&mut parsed.blocks, k, &text);
            }
            None if name == "img" => {
                if let Some(alt) = el.value().attr("alt") {
                    push_block(&mut parsed.blocks, BlockKind::Image, alt);
                }
            }
            _ => {}
        }
    }

    parsed.plain_text = parsed
        .blocks
        .iter()
        .map(|b| b.text.as_str())
        .collect::<Vec<_>>()
        .join("\n\n");
    Ok(parsed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_scripts_and_nav() {
        let html = r#"<html><head><title>T</title><script>alert(1)</script></head>
            <body><nav>menu</nav><article><h1>Hello</h1><p>World</p></article></body></html>"#;
        let doc = parse(html).unwrap();
        assert_eq!(doc.title.as_deref(), Some("T"));
        let texts: Vec<&str> = doc.blocks.iter().map(|b| b.text.as_str()).collect();
        assert!(texts.contains(&"Hello"));
        assert!(texts.contains(&"World"));
        assert!(!texts.iter().any(|t| t.contains("alert") || t.contains("menu")));
    }
}
