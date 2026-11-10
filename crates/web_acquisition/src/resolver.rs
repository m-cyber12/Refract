//! Bounded system-resolution workers. A timeout cannot interrupt the operating
//! system resolver; workers remain occupied until that lookup returns.
use std::{
    net::{IpAddr, ToSocketAddrs},
    sync::{atomic::{AtomicBool, Ordering}, mpsc::{self, SyncSender, TrySendError}, Arc, Mutex, OnceLock},
    thread,
    time::{Duration, Instant},
};

use content_compiler::fetch_policy::FetchTarget;
use crate::{check_approval, Approval, FetchError};

const MAX_WORKERS: usize = 2;
const MAX_QUEUED: usize = 4;
const DNS_TIMEOUT: Duration = Duration::from_secs(5);
pub(crate) const MAX_RESOLUTION_AGE: Duration = Duration::from_secs(10);

/// Single-use capability: cannot be constructed or modified outside this crate.
/// It binds approval, the original URL and the validated DNS answer together.
pub struct ResolvedRequest {
    pub(crate) target: FetchTarget,
    pub(crate) addresses: Vec<IpAddr>,
    pub(crate) resolved_at: Instant,
}

struct Job {
    host: String,
    port: u16,
    cancelled: Arc<AtomicBool>,
    reply: SyncSender<Result<Vec<IpAddr>, ()>>,
}

type Lookup = dyn Fn(&str, u16) -> Result<Vec<IpAddr>, ()> + Send + Sync + 'static;
struct Resolver { sender: SyncSender<Job> }

impl Resolver {
    fn new(lookup: Arc<Lookup>) -> Self {
        let (sender, receiver) = mpsc::sync_channel::<Job>(MAX_QUEUED);
        let receiver = Arc::new(Mutex::new(receiver));
        for _ in 0..MAX_WORKERS {
            let (receiver, lookup) = (Arc::clone(&receiver), Arc::clone(&lookup));
            // Failure to spawn leaves a bounded queue; requests fail by timeout.
            let _ = thread::Builder::new().name("refract-dns".into()).spawn(move || loop {
                let Ok(lock) = receiver.lock() else { break };
                let Ok(job) = lock.recv() else { break };
                drop(lock);
                if job.cancelled.load(Ordering::Acquire) { continue; }
                let result = lookup(&job.host, job.port);
                if !job.cancelled.load(Ordering::Acquire) { let _ = job.reply.send(result); }
            });
        }
        Self { sender }
    }

    fn lookup(&self, host: String, port: u16, timeout: Duration) -> Result<Vec<IpAddr>, FetchError> {
        let (reply, receiver) = mpsc::sync_channel(1);
        let cancelled = Arc::new(AtomicBool::new(false));
        let job = Job { host, port, cancelled: Arc::clone(&cancelled), reply };
        match self.sender.try_send(job) {
            Ok(()) => {},
            Err(TrySendError::Full(_)) => return Err(FetchError::ResolverBusy),
            Err(TrySendError::Disconnected(_)) => return Err(FetchError::ResolutionFailed),
        }
        match receiver.recv_timeout(timeout) {
            Ok(Ok(addresses)) => Ok(addresses),
            Ok(Err(())) | Err(mpsc::RecvTimeoutError::Disconnected) => Err(FetchError::ResolutionFailed),
            Err(mpsc::RecvTimeoutError::Timeout) => {
                cancelled.store(true, Ordering::Release);
                Err(FetchError::ResolutionTimedOut)
            }
        }
    }
}

fn global_resolver() -> &'static Resolver {
    static RESOLVER: OnceLock<Resolver> = OnceLock::new();
    RESOLVER.get_or_init(|| Resolver::new(Arc::new(|host, port| {
        // Take one past the policy limit so oversized answers fail closed.
        (host, port).to_socket_addrs().map(|entries| entries.take(33).map(|addr| addr.ip()).collect()).map_err(|_| ())
    })))
}

/// Approve this specific request before any DNS query; validate every returned
/// address and issue a short-lived single-use capability for the pinned request.
/// OS DNS may disclose the hostname to configured resolvers. This is not a
/// standalone UI consent flow, and active OS lookups cannot be cancelled.
pub fn resolve_one(target: &FetchTarget, previous: Option<&FetchTarget>, approval: Approval) -> Result<ResolvedRequest, FetchError> {
    resolve_with(global_resolver(), target, previous, approval, DNS_TIMEOUT)
}

fn resolve_with(resolver: &Resolver, target: &FetchTarget, previous: Option<&FetchTarget>, approval: Approval, timeout: Duration) -> Result<ResolvedRequest, FetchError> {
    check_approval(target, previous, approval)?;
    let host = target.url().host_str().ok_or(FetchError::ResolutionFailed)?;
    let port = target.url().port_or_known_default().ok_or(FetchError::ResolutionFailed)?;
    // URL's IPv6 host string may have brackets. IP literals require no DNS.
    let literal = host.trim_start_matches('[').trim_end_matches(']').parse::<IpAddr>().ok();
    let addresses = match literal {
        Some(ip) => vec![ip],
        None => resolver.lookup(host.to_owned(), port, timeout)?,
    };
    target.validate_addresses(&addresses).map_err(FetchError::Policy)?;
    Ok(ResolvedRequest { target: target.clone(), addresses, resolved_at: Instant::now() })
}

#[cfg(test)]
mod tests {
    use super::*;
    use content_compiler::fetch_policy::FetchPolicyError;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn target() -> FetchTarget { FetchTarget::parse("https://public.com/path").unwrap() }
    fn approval() -> Approval { Approval { request: true, http: false, destination_change: false } }
    fn ip(s: &str) -> IpAddr { s.parse().unwrap() }

    #[test]
    fn approval_precedes_dns_and_mixed_answers_are_blocked() {
        let calls = Arc::new(AtomicUsize::new(0));
        let counter = Arc::clone(&calls);
        let resolver = Resolver::new(Arc::new(move |_, _| { counter.fetch_add(1, Ordering::SeqCst); Ok(vec![ip("8.8.8.8"), ip("10.0.0.1")]) }));
        assert!(matches!(resolve_with(&resolver, &target(), None, Approval::default(), Duration::from_secs(1)), Err(FetchError::ApprovalRequired)));
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        assert!(matches!(resolve_with(&resolver, &target(), None, approval(), Duration::from_secs(1)), Err(FetchError::Policy(FetchPolicyError::ForbiddenAddress))));
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn literals_are_checked_without_resolver_and_success_binds_addresses() {
        let resolver = Resolver::new(Arc::new(|_, _| panic!("must not look up literals")));
        let request = resolve_with(&resolver, &FetchTarget::parse("https://8.8.8.8/").unwrap(), None, approval(), Duration::from_secs(1)).unwrap();
        assert_eq!(request.addresses, vec![ip("8.8.8.8")]);
        let resolver = Resolver::new(Arc::new(|_, _| Ok(vec![ip("8.8.8.8"), ip("1.1.1.1")])));
        let request = resolve_with(&resolver, &target(), None, approval(), Duration::from_secs(1)).unwrap();
        assert_eq!(request.addresses, vec![ip("8.8.8.8"), ip("1.1.1.1")]);
        assert_eq!(request.target, target());
    }

    #[test]
    fn subsequent_hops_reresolve_and_reject_changed_answers() {
        let calls = Arc::new(AtomicUsize::new(0));
        let counter = Arc::clone(&calls);
        let resolver = Resolver::new(Arc::new(move |_, _| {
            if counter.fetch_add(1, Ordering::SeqCst) == 0 { Ok(vec![ip("8.8.8.8")]) }
            else { Ok(vec![ip("127.0.0.1")]) }
        }));
        let initial = target();
        assert!(resolve_with(&resolver, &initial, None, approval(), Duration::from_secs(1)).is_ok());
        let redirect = initial.redirect("/next", 0).unwrap();
        assert!(matches!(resolve_with(&resolver, &redirect, Some(&initial), approval(), Duration::from_secs(1)), Err(FetchError::Policy(FetchPolicyError::ForbiddenAddress))));
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn timeout_skips_queued_work_and_concurrency_is_bounded() {
        let (started, starts) = mpsc::channel();
        let (release, releases) = mpsc::channel::<()>();
        let releases = Arc::new(Mutex::new(releases));
        let calls = Arc::new(AtomicUsize::new(0));
        let counter = Arc::clone(&calls);
        let resolver = Arc::new(Resolver::new(Arc::new(move |_, _| {
            counter.fetch_add(1, Ordering::SeqCst);
            started.send(()).unwrap();
            releases.lock().unwrap().recv().unwrap();
            Ok(vec![ip("8.8.8.8")])
        })));
        let mut running = Vec::new();
        for _ in 0..MAX_WORKERS {
            let resolver = Arc::clone(&resolver);
            running.push(thread::spawn(move || resolver.lookup("public.com".into(), 443, Duration::from_millis(200))));
        }
        for _ in 0..MAX_WORKERS { starts.recv_timeout(Duration::from_secs(2)).unwrap(); }
        // No worker available: the queued request times out without starting.
        assert_eq!(resolver.lookup("public.com".into(), 443, Duration::from_millis(20)), Err(FetchError::ResolutionTimedOut));
        for task in running { assert_eq!(task.join().unwrap(), Err(FetchError::ResolutionTimedOut)); }
        for _ in 0..MAX_WORKERS { release.send(()).unwrap(); }
        // A later job on the same pool acts as a barrier: cancelled queued
        // work must be skipped rather than invoking the resolver.
        let barrier_resolver = Arc::clone(&resolver);
        let barrier = thread::spawn(move || barrier_resolver.lookup("public.com".into(), 443, Duration::from_secs(2)));
        starts.recv_timeout(Duration::from_secs(1)).unwrap();
        release.send(()).unwrap();
        assert!(barrier.join().unwrap().is_ok());
        assert_eq!(calls.load(Ordering::SeqCst), MAX_WORKERS + 1);
    }
}
