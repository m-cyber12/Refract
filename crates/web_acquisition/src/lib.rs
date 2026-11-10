//! Single-hop static HTML retrieval, not wired into the app.
//!
//! This layer accepts a previously resolved DNS answer, validates the entire
//! answer and pins the connection to those addresses. The caller must provide a
//! bounded DNS resolver, fresh resolution, explicit consent for each hop, and a
//! separate reviewed-save flow. No automatic redirects, cookies, proxies, retries,
//! scripts, subresources or persistence are performed here.

use content_compiler::fetch_policy::{FetchPolicyError, FetchTarget};
use reqwest::{blocking::Client, header, redirect::Policy, StatusCode};
use std::{io::Read, net::{IpAddr, SocketAddr}, time::Duration};

pub const MAX_HTML_BYTES: usize = 2 * 1024 * 1024;
const TIMEOUT: Duration = Duration::from_secs(30);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Debug, Clone, Copy, Default)]
pub struct Approval {
    /// Explicit request for this single hop. A redirect is a new hop.
    pub request: bool,
    /// Explicit approval for this HTTP request, even on a repeated HTTP hop.
    pub http: bool,
    /// Explicit approval for this redirect's changed host/effective port.
    pub destination_change: bool,
}

#[derive(Debug, PartialEq, Eq)]
pub enum FetchError {
    ApprovalRequired,
    Policy(FetchPolicyError),
    RequestFailed,
    HttpStatus(u16),
    InvalidRedirect,
    UnsupportedContent,
    TooLarge,
    InvalidText,
}

#[derive(Debug, PartialEq, Eq)]
pub enum FetchResponse {
    /// Raw response body bytes after HTTP transfer framing; not parsed or saved.
    Html(Vec<u8>),
    /// Untrusted Location header. The caller must apply FetchTarget::redirect,
    /// obtain any approvals, and freshly resolve/validate before another request.
    Redirect(String),
}

/// Perform exactly one request. `resolved` must be the freshly obtained complete
/// answer for the requested hostname; no DNS lookup or fallback is allowed here.
/// Never log errors or URLs: address queries and response content can be private.
pub fn fetch_one(
    target: &FetchTarget,
    previous: Option<&FetchTarget>,
    resolved: &[IpAddr],
    approval: Approval,
) -> Result<FetchResponse, FetchError> {
    let requirements = target.required_approvals(previous);
    if !approval.request || (requirements.confirm_http && !approval.http)
        || (requirements.confirm_destination_change && !approval.destination_change) {
        return Err(FetchError::ApprovalRequired);
    }
    target.validate_addresses(resolved).map_err(FetchError::Policy)?;
    send_pinned(target, resolved)
}

fn send_pinned(target: &FetchTarget, resolved: &[IpAddr]) -> Result<FetchResponse, FetchError> {
    let url = target.url();
    let host = url.host_str().ok_or(FetchError::RequestFailed)?;
    let port = url.port_or_known_default().ok_or(FetchError::RequestFailed)?;
    let addresses: Vec<_> = resolved.iter().map(|ip| SocketAddr::new(*ip, port)).collect();
    let client = Client::builder()
        .no_proxy()
        .no_gzip().no_brotli().no_deflate().no_zstd()
        .referer(false)
        .retry(reqwest::retry::never())
        .http1_only()
        .redirect(Policy::none())
        .connect_timeout(CONNECT_TIMEOUT)
        .timeout(TIMEOUT)
        .resolve_to_addrs(host, &addresses)
        .build().map_err(|_| FetchError::RequestFailed)?;
    let mut response = client.get(url.clone())
        .header(header::ACCEPT, "text/html")
        .header(header::ACCEPT_ENCODING, "identity")
        .send().map_err(|_| FetchError::RequestFailed)?;
    let status = response.status();
    if matches!(status, StatusCode::MOVED_PERMANENTLY | StatusCode::FOUND | StatusCode::SEE_OTHER | StatusCode::TEMPORARY_REDIRECT | StatusCode::PERMANENT_REDIRECT) {
        if response.headers().get_all(header::LOCATION).iter().count() != 1 {
            return Err(FetchError::InvalidRedirect);
        }
        let location = response.headers().get(header::LOCATION)
            .and_then(|value| value.to_str().ok())
            .filter(|value| !value.is_empty() && value.len() <= 8192)
            .ok_or(FetchError::InvalidRedirect)?;
        return Ok(FetchResponse::Redirect(location.to_owned()));
    }
    if status != StatusCode::OK { return Err(FetchError::HttpStatus(status.as_u16())); }
    if response.headers().get_all(header::CONTENT_ENCODING).iter().count() > 1
        || response.headers().get_all(header::CONTENT_TYPE).iter().count() != 1 {
        return Err(FetchError::UnsupportedContent);
    }
    if response.headers().get(header::CONTENT_ENCODING)
        .is_some_and(|value| !value.as_bytes().eq_ignore_ascii_case(b"identity")) {
        return Err(FetchError::UnsupportedContent);
    }
    let content_type = response.headers().get(header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok()).ok_or(FetchError::UnsupportedContent)?;
    let mut parts = content_type.split(';');
    if !parts.next().unwrap_or("").trim().eq_ignore_ascii_case("text/html") {
        return Err(FetchError::UnsupportedContent);
    }
    for part in parts {
        let (key, value) = part.trim().split_once('=').ok_or(FetchError::UnsupportedContent)?;
        if key.trim().eq_ignore_ascii_case("charset") {
            let charset = value.trim().trim_matches('"');
            if !charset.eq_ignore_ascii_case("utf-8") && !charset.eq_ignore_ascii_case("utf8") {
                return Err(FetchError::UnsupportedContent);
            }
        }
    }
    if response.content_length().is_some_and(|n| n > MAX_HTML_BYTES as u64) {
        return Err(FetchError::TooLarge);
    }
    let mut bytes = Vec::new();
    response.by_ref().take(MAX_HTML_BYTES as u64 + 1).read_to_end(&mut bytes)
        .map_err(|_| FetchError::RequestFailed)?;
    if bytes.len() > MAX_HTML_BYTES { return Err(FetchError::TooLarge); }
    let text = std::str::from_utf8(&bytes).map_err(|_| FetchError::InvalidText)?;
    if text.contains('\0') { return Err(FetchError::InvalidText); }
    Ok(FetchResponse::Html(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{io::{Read, Write}, net::{Ipv4Addr, TcpListener}, thread};

    // The production entry point rejects loopback. Only this fixture bypasses
    // that policy to test a local, isolated HTTP server and pinned resolution.
    fn fixture(response: Vec<u8>) -> (FetchTarget, thread::JoinHandle<String>) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        let target = FetchTarget::parse(&format!("http://public.com:{port}/path?token=private#fragment")).unwrap();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
            let mut request = Vec::new();
            loop {
                let mut buf = [0; 1024];
                let n = stream.read(&mut buf).unwrap();
                if n == 0 { break; }
                request.extend_from_slice(&buf[..n]);
                if request.windows(4).any(|w| w == b"\r\n\r\n") { break; }
            }
            let _ = stream.write_all(&response);
            String::from_utf8(request).unwrap()
        });
        (target, server)
    }
    fn local() -> [IpAddr; 1] { [IpAddr::V4(Ipv4Addr::LOCALHOST)] }

    #[test]
    fn approvals_and_private_addresses_fail_before_any_network() {
        let target = FetchTarget::parse("http://public.com/").unwrap();
        assert_eq!(fetch_one(&target, None, &local(), Approval::default()), Err(FetchError::ApprovalRequired));
        assert_eq!(fetch_one(&target, None, &local(), Approval { request: true, http: false, destination_change: false }), Err(FetchError::ApprovalRequired));
        assert_eq!(fetch_one(&target, None, &local(), Approval { request: true, http: true, destination_change: false }), Err(FetchError::Policy(FetchPolicyError::ForbiddenAddress)));
        let previous = FetchTarget::parse("https://other.com/").unwrap();
        assert_eq!(fetch_one(&target, Some(&previous), &local(), Approval { request: true, http: true, destination_change: false }), Err(FetchError::ApprovalRequired));
    }

    #[test]
    fn pinned_single_hop_preserves_bytes_and_does_not_send_fragment_or_credentials() {
        let body = b"\xef\xbb\xbf<p>hello</p>";
        let mut response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len()).into_bytes();
        response.extend_from_slice(body);
        let (target, server) = fixture(response);
        assert_eq!(send_pinned(&target, &local()), Ok(FetchResponse::Html(body.to_vec())));
        let request = server.join().unwrap().to_ascii_lowercase();
        assert!(request.starts_with("get /path?token=private http/1.1"));
        assert!(!request.contains("fragment"));
        assert!(!request.contains("cookie:"));
        assert!(!request.contains("authorization:"));
        assert!(!request.contains("referer:"));
        assert!(request.contains("accept-encoding: identity"));
    }

    #[test]
    fn redirect_is_returned_not_followed() {
        let (target, server) = fixture(b"HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1/secret\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_vec());
        assert_eq!(send_pinned(&target, &local()), Ok(FetchResponse::Redirect("http://127.0.0.1/secret".into())));
        server.join().unwrap();
    }

    #[test]
    fn unsupported_encoding_and_type_fail_closed() {
        for headers in ["Content-Type: text/html\r\nContent-Encoding: gzip", "Content-Type: application/pdf", "Content-Type: text/html; charset=iso-8859-1", "Content-Type: text/html\r\nContent-Type: application/pdf"] {
            let (target, server) = fixture(format!("HTTP/1.1 200 OK\r\n{headers}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").into_bytes());
            assert_eq!(send_pinned(&target, &local()), Err(FetchError::UnsupportedContent));
            server.join().unwrap();
        }
    }

    #[test]
    fn declared_and_streamed_over_limit_are_rejected() {
        let (target, server) = fixture(format!("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", MAX_HTML_BYTES + 1).into_bytes());
        assert_eq!(send_pinned(&target, &local()), Err(FetchError::TooLarge));
        server.join().unwrap();
        let mut response = b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n".to_vec();
        response.extend(vec![b'a'; MAX_HTML_BYTES + 1]);
        let (target, server) = fixture(response);
        assert_eq!(send_pinned(&target, &local()), Err(FetchError::TooLarge));
        server.join().unwrap();
    }
}
