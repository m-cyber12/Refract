//! Pure, fail-closed planning checks for a future user-initiated web fetch.
//!
//! These checks do NOT perform DNS, connect, follow redirects, or constitute an
//! SSRF boundary on their own. A transport must validate and pin every resolved
//! address, disable proxies/automatic redirects, authenticate TLS against the
//! requested hostname, and reapply this policy on every hop before use.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use url::{Host, Url};

use crate::validate_source_url;

/// No actual request is authorized by this value: callers still need explicit
/// per-request approval, validated DNS and a pinned, appropriately configured
/// transport. Fragments are never sent to the server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FetchTarget {
    url: Url,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FetchPolicyError {
    InvalidUrl,
    ForbiddenHost,
    EmptyResolution,
    ForbiddenAddress,
    TooManyAddresses,
    TooManyRedirects,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RequestApprovals {
    /// Required for every unencrypted request, not just the first hop.
    pub confirm_http: bool,
    /// Required when a redirect changes host or effective port. Conservative:
    /// related subdomains are not assumed to have the same owner.
    pub confirm_destination_change: bool,
}

impl FetchTarget {
    pub fn parse(input: &str) -> Result<Self, FetchPolicyError> {
        validate_source_url(input).map_err(|_| FetchPolicyError::InvalidUrl)?;
        let mut url = Url::parse(input).map_err(|_| FetchPolicyError::InvalidUrl)?;
        match url.host().ok_or(FetchPolicyError::InvalidUrl)? {
            Host::Domain(domain) => {
                let domain = domain.trim_end_matches('.');
                if domain.is_empty()
                    || !domain.contains('.')
                    || ["localhost", "local", "internal", "home", "lan", "test", "invalid", "example", "onion"]
                        .iter().any(|suffix| domain == *suffix || domain.ends_with(&format!(".{suffix}")))
                {
                    return Err(FetchPolicyError::ForbiddenHost);
                }
            }
            Host::Ipv4(ip) if !public_v4(ip) => return Err(FetchPolicyError::ForbiddenAddress),
            Host::Ipv6(ip) if !public_v6(ip) => return Err(FetchPolicyError::ForbiddenAddress),
            _ => {}
        }
        url.set_fragment(None);
        Ok(Self { url })
    }

    pub fn url(&self) -> &Url { &self.url }

    /// Relative and absolute Location values are parsed and validated, but never
    /// followed here. Redirect chains are capped independently of consent.
    pub fn redirect(&self, location: &str, redirects_so_far: usize) -> Result<Self, FetchPolicyError> {
        if redirects_so_far >= 5 { return Err(FetchPolicyError::TooManyRedirects); }
        if location.len() > 8192 || location.chars().any(|c| c.is_whitespace() || c.is_control() || c == '\\') {
            return Err(FetchPolicyError::InvalidUrl);
        }
        // Check authority before URL normalization can erase empty userinfo.
        let authority = if let Some(rest) = location.strip_prefix("//") {
            Some(rest)
        } else {
            location.split_once("://").map(|(_, rest)| rest)
        };
        if authority.is_some_and(|rest| rest.split(['/', '?', '#']).next().unwrap_or("").contains('@')) {
            return Err(FetchPolicyError::InvalidUrl);
        }
        let joined = self.url.join(location).map_err(|_| FetchPolicyError::InvalidUrl)?;
        Self::parse(joined.as_str())
    }

    pub fn required_approvals(&self, previous: Option<&Self>) -> RequestApprovals {
        RequestApprovals {
            confirm_http: self.url.scheme() == "http",
            confirm_destination_change: previous.is_some_and(|p| {
                p.url.host() != self.url.host() || p.url.port_or_known_default() != self.url.port_or_known_default()
            }),
        }
    }

    /// Reject the entire DNS answer if any address is non-public. The eventual
    /// connection must use one of these exact validated addresses: resolving the
    /// hostname again, or allowing a proxy to resolve it, defeats this check.
    pub fn validate_addresses(&self, addresses: &[IpAddr]) -> Result<(), FetchPolicyError> {
        if addresses.is_empty() { return Err(FetchPolicyError::EmptyResolution); }
        if addresses.len() > 32 { return Err(FetchPolicyError::TooManyAddresses); }
        if addresses.iter().any(|ip| !public_address(*ip)) { return Err(FetchPolicyError::ForbiddenAddress); }
        // A literal address cannot be replaced with an unrelated resolution.
        let literal = match self.url.host() {
            Some(Host::Ipv4(ip)) => Some(IpAddr::V4(ip)),
            Some(Host::Ipv6(ip)) => Some(IpAddr::V6(ip)),
            _ => None,
        };
        if literal.is_some_and(|ip| addresses.iter().any(|candidate| *candidate != ip)) {
            return Err(FetchPolicyError::ForbiddenAddress);
        }
        Ok(())
    }
}

/// Deliberately conservative. Special-purpose, documentation, transition and
/// multicast ranges are blocked even where an exception might be routable.
pub fn public_address(ip: IpAddr) -> bool {
    match ip { IpAddr::V4(ip) => public_v4(ip), IpAddr::V6(ip) => public_v6(ip) }
}

fn public_v4(ip: Ipv4Addr) -> bool {
    let [a, b, c, _] = ip.octets();
    !(a == 0 || a == 10 || a == 127 || a >= 224
        || (a == 100 && (64..=127).contains(&b))
        || (a == 169 && b == 254)
        || (a == 172 && (16..=31).contains(&b))
        || (a == 192 && (b == 0 || b == 168 || (b == 88 && c == 99)))
        || (a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100)))
        || (a == 203 && b == 0 && c == 113))
}

fn public_v6(ip: Ipv6Addr) -> bool {
    let s = ip.segments();
    // Only globally allocated 2000::/3, minus IETF special allocations,
    // documentation, 6to4 and other transition mechanisms. IPv4-mapped and
    // compatible forms are therefore rejected rather than unwrapped.
    (s[0] & 0xe000) == 0x2000
        && !(s[0] == 0x2001 && (s[1] <= 0x01ff || s[1] == 0x0db8))
        && s[0] != 0x2002
        && !(s[0] == 0x3fff && (s[1] & 0xf000) == 0)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn target(s: &str) -> FetchTarget { FetchTarget::parse(s).unwrap() }
    fn ip(s: &str) -> IpAddr { s.parse().unwrap() }

    #[test]
    fn address_ranges_and_ambiguous_numeric_hosts_fail_closed() {
        for value in ["127.0.0.1", "10.1.2.3", "100.64.0.1", "169.254.169.254", "172.31.2.3", "192.168.1.1", "192.0.2.1", "198.18.0.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255", "::1", "::ffff:8.8.8.8", "fc00::1", "fe80::1", "2001:db8::1", "2002:0808:0808::1"] {
            assert!(!public_address(ip(value)), "{value}");
        }
        assert!(public_address(ip("8.8.8.8")));
        assert!(public_address(ip("2606:4700:4700::1111")));
        for value in ["http://127.1/", "http://0x7f000001/", "https://localhost./", "https://foo.local/", "https://user:pw@public.com/", "https://public.com\\@evil.com/"] {
            assert!(FetchTarget::parse(value).is_err(), "{value}");
        }
    }

    #[test]
    fn all_addresses_must_be_safe_and_literal_must_match() {
        let host = target("https://public.com/a");
        assert_eq!(host.validate_addresses(&[]), Err(FetchPolicyError::EmptyResolution));
        assert_eq!(host.validate_addresses(&[ip("8.8.8.8"), ip("127.0.0.1")]), Err(FetchPolicyError::ForbiddenAddress));
        assert_eq!(host.validate_addresses(&vec![ip("8.8.8.8"); 33]), Err(FetchPolicyError::TooManyAddresses));
        assert!(host.validate_addresses(&[ip("8.8.8.8"), ip("2606:4700:4700::1111")]).is_ok());
        assert_eq!(target("https://8.8.8.8/").validate_addresses(&[ip("1.1.1.1")]), Err(FetchPolicyError::ForbiddenAddress));
    }

    #[test]
    fn redirects_require_new_host_or_port_confirmation_and_http_each_time() {
        let start = target("https://public.com/a#secret");
        assert_eq!(start.url().fragment(), None);
        let same = start.redirect("/next", 0).unwrap();
        assert_eq!(same.required_approvals(Some(&start)), RequestApprovals { confirm_http: false, confirm_destination_change: false });
        let changed = same.redirect("http://other.com/page", 1).unwrap();
        assert_eq!(changed.required_approvals(Some(&same)), RequestApprovals { confirm_http: true, confirm_destination_change: true });
        let second_http = changed.redirect("/again", 2).unwrap();
        assert!(second_http.required_approvals(Some(&changed)).confirm_http);
        assert!(start.redirect("https://127.0.0.1/", 0).is_err());
        assert!(start.redirect("//user@public.com/", 0).is_err());
        assert!(start.redirect("https://@public.com/", 0).is_err());
        assert!(start.redirect("https://public.com:8443/", 0).unwrap().required_approvals(Some(&start)).confirm_destination_change);
        assert_eq!(start.redirect("/loop", 5), Err(FetchPolicyError::TooManyRedirects));
    }
}
