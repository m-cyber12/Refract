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
        .map(|el| normalize_ws(&visible_text(el)))
        .filter(|s| !s.is_empty())
}


fn own_blocked(e: scraper::ElementRef<'_>) -> bool {
    matches!(e.value().name(), "script" | "style" | "noscript" | "iframe" | "nav" | "footer" | "aside" | "form" | "template")
        || e.value().attr("hidden").is_some()
        || e.value().attr("aria-hidden").is_some_and(|v| v.eq_ignore_ascii_case("true"))
}
fn blocked(el: scraper::ElementRef<'_>) -> bool {
    own_blocked(el) || el.ancestors().filter_map(scraper::ElementRef::wrap).any(own_blocked)
}
fn visible_text(el: scraper::ElementRef<'_>) -> String {
    let mut out = String::new();
    for node in el.descendants() {
        if let scraper::node::Node::Text(text) = node.value() {
            if !node.ancestors().filter_map(scraper::ElementRef::wrap).any(own_blocked) { out.push_str(text); }
        }
    }
    out
}
fn block_kind(name: &str) -> Option<BlockKind> { match name { "h1"=>Some(BlockKind::Heading1),"h2"=>Some(BlockKind::Heading2),"h3"=>Some(BlockKind::Heading3),"p"=>Some(BlockKind::Paragraph),"li"=>Some(BlockKind::ListItem),"blockquote"=>Some(BlockKind::Quote),"pre"|"code"=>Some(BlockKind::Code),_=>None } }

pub fn parse(input: &str) -> RefractResult<ParsedDocument> {
    let doc = Html::parse_document(input);

    let title = select_first(&doc, "head title").or_else(|| {
        let sel = Selector::parse("meta[property='og:title']").ok()?;
        doc.select(&sel).find_map(|el| el.value().attr("content").map(normalize_ws)).filter(|v| !v.is_empty())
    });

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
        .find_map(|s| Selector::parse(s).ok().and_then(|sel| doc.select(&sel).find(|el| !blocked(*el))));

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
        if blocked(el) { continue; }
        // A recognized container owns its visible text; don't duplicate nested
        // paragraphs/code inside blockquotes/list items/pre blocks.
        if el.ancestors().filter_map(scraper::ElementRef::wrap).any(|a| a.id() != el.id() && block_kind(a.value().name()).is_some()) { continue; }
        let kind = block_kind(name);
        match kind {
            Some(k) => {
                let text = normalize_ws(&visible_text(el));
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

    if parsed.blocks.is_empty() {
        let fallback = visible_text(root);
        push_block(&mut parsed.blocks, BlockKind::Paragraph, &fallback);
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

#[cfg(test)] mod capture_tests {
 use super::*;
 #[test] fn excluded_descendants_never_leak_into_reader_text() {
  let d=parse("<article><nav><p>navigation secret</p></nav><p>Hello <script>tracking_secret()</script> world <span hidden>hidden secret</span></p><aside><div><p>aside secret</p></div></aside><div aria-hidden='true'><p>private</p></div></article>").unwrap();
  assert_eq!(d.plain_text,"Hello world");assert_eq!(d.blocks.len(),1);
 }
 #[test] fn nested_content_is_not_duplicated_and_bare_text_is_supported() {
  let d=parse("<main><blockquote><p>One quote</p></blockquote><pre><code>one code block</code></pre></main>").unwrap();
  assert_eq!(d.blocks.len(),2);assert_eq!(d.blocks[0].kind,BlockKind::Quote);assert_eq!(d.blocks[1].kind,BlockKind::Code);
  assert_eq!(parse("<main>Readable bare text</main>").unwrap().plain_text,"Readable bare text");
  assert_eq!(parse("<head><meta property='og:title' content='OG title'></head><body><p>Body</p></body>").unwrap().title.as_deref(),Some("OG title"));
 }
}
