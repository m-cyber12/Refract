//! In-memory redirect/approval state machine. No UI, staging or persistence.
use content_compiler::fetch_policy::{FetchPolicyError, FetchTarget};
use crate::{check_approval, fetch_one, resolve_one, Approval, FetchError, FetchResponse};
use uuid::Uuid;

/// Details to present for this exact request. The address may contain secrets;
/// it must not be logged or shown outside the explicit consent flow.
#[derive(Clone)]
pub struct PendingApproval {
    pub ticket: Uuid,
    pub address: String,
    pub requires_http_confirmation: bool,
    pub requires_destination_confirmation: bool,
}

/// Completed bytes are held only in memory until taken, cancelled or dropped.
pub struct FetchedHtml {
    pub requested_address: String,
    pub final_address: String,
    pub bytes: Vec<u8>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum SessionError {
    InvalidTarget(FetchPolicyError),
    NotAwaitingApproval,
    StaleApproval,
    ApprovalRequired,
    NotFailed,
    NotComplete,
    Fetch(FetchError),
}

#[derive(Debug, PartialEq, Eq)]
pub enum Progress { AwaitingApproval, Complete }

struct Pending {
    target: FetchTarget,
    previous: Option<FetchTarget>,
    redirects: usize,
    ticket: Uuid,
}

enum State {
    Awaiting(Pending),
    Failed(Pending),
    Complete(FetchedHtml),
    Busy,
    Closed,
}

pub struct FetchSession {
    requested: FetchTarget,
    state: State,
}

impl FetchSession {
    /// Constructing a session does not resolve, fetch or persist anything.
    pub fn new(address: &str) -> Result<Self, SessionError> {
        let target = FetchTarget::parse(address).map_err(SessionError::InvalidTarget)?;
        Ok(Self { requested: target.clone(), state: State::Awaiting(Pending { target, previous: None, redirects: 0, ticket: Uuid::new_v4() }) })
    }

    pub fn pending(&self) -> Option<PendingApproval> {
        let State::Awaiting(pending) = &self.state else { return None };
        let needs = pending.target.required_approvals(pending.previous.as_ref());
        Some(PendingApproval { ticket: pending.ticket, address: pending.target.url().as_str().to_owned(),
            requires_http_confirmation: needs.confirm_http, requires_destination_confirmation: needs.confirm_destination_change })
    }

    /// Blocking operation. Never call on the UI thread. Same-destination HTTPS
    /// redirects are followed under the initial request approval, with fresh DNS
    /// for each hop. Any HTTP or destination change requires a new approval.
    pub fn advance(&mut self, ticket: Uuid, approval: Approval) -> Result<Progress, SessionError> {
        self.advance_with(ticket, approval, |target, previous, approval| {
            let request = resolve_one(target, previous, approval)?;
            fetch_one(request)
        })
    }

    fn advance_with<F>(&mut self, ticket: Uuid, approval: Approval, mut request: F) -> Result<Progress, SessionError>
    where F: FnMut(&FetchTarget, Option<&FetchTarget>, Approval) -> Result<FetchResponse, FetchError> {
        let State::Awaiting(pending) = &self.state else { return Err(SessionError::NotAwaitingApproval) };
        if pending.ticket != ticket { return Err(SessionError::StaleApproval); }
        check_approval(&pending.target, pending.previous.as_ref(), approval).map_err(|_| SessionError::ApprovalRequired)?;
        let State::Awaiting(mut pending) = std::mem::replace(&mut self.state, State::Busy) else { unreachable!() };
        let mut hop_approval = approval;
        loop {
            match request(&pending.target, pending.previous.as_ref(), hop_approval) {
                Err(error) => { self.state = State::Failed(pending); return Err(SessionError::Fetch(error)); }
                Ok(FetchResponse::Html(bytes)) => {
                    self.state = State::Complete(FetchedHtml { requested_address: self.requested.url().as_str().to_owned(), final_address: pending.target.url().as_str().to_owned(), bytes });
                    return Ok(Progress::Complete);
                }
                Ok(FetchResponse::Redirect(location)) => {
                    let next = match pending.target.redirect(&location, pending.redirects) {
                        Ok(next) => next,
                        Err(error) => { self.state = State::Failed(pending); return Err(SessionError::Fetch(FetchError::Policy(error))); }
                    };
                    let requirements = next.required_approvals(Some(&pending.target));
                    let previous = pending.target;
                    pending = Pending { target: next, previous: Some(previous), redirects: pending.redirects + 1, ticket: pending.ticket };
                    if requirements.confirm_http || requirements.confirm_destination_change {
                        pending.ticket = Uuid::new_v4();
                        self.state = State::Awaiting(pending);
                        return Ok(Progress::AwaitingApproval);
                    }
                    // Only same-destination HTTPS is covered by the current
                    // approval; a new resolution is still mandatory.
                    hop_approval = Approval { request: true, http: false, destination_change: false };
                }
            }
        }
    }

    /// Failures never retry automatically. A retry issues a new ticket and requires
    /// a new explicit approval, including HTTP/destination confirmation as needed.
    pub fn retry(&mut self) -> Result<(), SessionError> {
        if !matches!(self.state, State::Failed(_)) { return Err(SessionError::NotFailed); }
        let ticket = Uuid::new_v4();
        let State::Failed(mut pending) = std::mem::replace(&mut self.state, State::Closed) else { unreachable!() };
        pending.ticket = ticket;
        self.state = State::Awaiting(pending);
        Ok(())
    }

    pub fn result(&self) -> Option<&FetchedHtml> {
        if let State::Complete(result) = &self.state { Some(result) } else { None }
    }

    pub fn take_result(&mut self) -> Result<FetchedHtml, SessionError> {
        if !matches!(self.state, State::Complete(_)) { return Err(SessionError::NotComplete); }
        let State::Complete(result) = std::mem::replace(&mut self.state, State::Closed) else { unreachable!() };
        Ok(result)
    }

    /// Drops retained in-memory result/state. It cannot interrupt a running
    /// blocking request; active cancellation requires separate integration work.
    pub fn cancel(&mut self) { self.state = State::Closed; }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;

    fn yes() -> Approval { Approval { request: true, http: false, destination_change: false } }
    fn make_session() -> FetchSession { FetchSession::new("https://public.com/start#fragment").unwrap() }
    fn run(session: &mut FetchSession, ticket: Uuid, approval: Approval, outputs: &mut VecDeque<Result<FetchResponse, FetchError>>, seen: &mut Vec<String>) -> Result<Progress, SessionError> {
        session.advance_with(ticket, approval, |target, _, _| { seen.push(target.url().as_str().to_owned()); outputs.pop_front().expect("unexpected request") })
    }

    #[test]
    fn same_destination_redirects_follow_and_preserve_original_bytes() {
        let mut session = make_session(); let ticket = session.pending().unwrap().ticket;
        let bytes = b"\xef\xbb\xbf<p>source</p>".to_vec();
        let mut outputs = VecDeque::from([Ok(FetchResponse::Redirect("/next".into())), Ok(FetchResponse::Html(bytes.clone()))]);
        let mut seen = Vec::new();
        assert_eq!(run(&mut session, ticket, yes(), &mut outputs, &mut seen), Ok(Progress::Complete));
        assert_eq!(seen, vec!["https://public.com/start", "https://public.com/next"]);
        let result = session.take_result().unwrap();
        assert_eq!(result.requested_address, "https://public.com/start");
        assert_eq!(result.final_address, "https://public.com/next");
        assert_eq!(result.bytes, bytes);
        assert!(matches!(session.take_result(), Err(SessionError::NotComplete)));
    }

    #[test]
    fn redirects_pause_before_new_destination_and_stale_approvals_fail() {
        let mut session = make_session(); let first = session.pending().unwrap().ticket;
        let mut seen = Vec::new(); let mut outputs = VecDeque::from([Ok(FetchResponse::Redirect("http://other.com/private?token=x".into()))]);
        assert_eq!(run(&mut session, first, yes(), &mut outputs, &mut seen), Ok(Progress::AwaitingApproval));
        assert_eq!(seen.len(), 1);
        let pending = session.pending().unwrap();
        assert!(pending.requires_destination_confirmation && pending.requires_http_confirmation);
        assert_ne!(first, pending.ticket);
        assert_eq!(run(&mut session, first, yes(), &mut outputs, &mut seen), Err(SessionError::StaleApproval));
        assert_eq!(run(&mut session, pending.ticket, yes(), &mut outputs, &mut seen), Err(SessionError::ApprovalRequired));
        assert_eq!(seen.len(), 1);
        outputs.push_back(Ok(FetchResponse::Html(b"ok".to_vec())));
        assert_eq!(run(&mut session, pending.ticket, Approval { request: true, http: true, destination_change: true }, &mut outputs, &mut seen), Ok(Progress::Complete));
        assert_eq!(seen.len(), 2);
    }

    #[test]
    fn http_redirect_needs_new_confirmation_even_on_same_host() {
        let mut session = FetchSession::new("http://public.com/a").unwrap();
        let first = session.pending().unwrap().ticket;
        let mut seen = Vec::new(); let mut outputs = VecDeque::from([Ok(FetchResponse::Redirect("/b".into()))]);
        assert_eq!(run(&mut session, first, Approval { request: true, http: true, destination_change: false }, &mut outputs, &mut seen), Ok(Progress::AwaitingApproval));
        let next = session.pending().unwrap();
        assert!(next.requires_http_confirmation);
        assert!(!next.requires_destination_confirmation);
        assert_eq!(seen.len(), 1);
    }

    #[test]
    fn failure_requires_new_ticket_and_explicit_retry() {
        let mut session = make_session(); let first = session.pending().unwrap().ticket;
        let mut seen = Vec::new(); let mut outputs = VecDeque::from([Err(FetchError::RequestFailed)]);
        assert_eq!(run(&mut session, first, yes(), &mut outputs, &mut seen), Err(SessionError::Fetch(FetchError::RequestFailed)));
        assert!(session.pending().is_none());
        assert_eq!(run(&mut session, first, yes(), &mut outputs, &mut seen), Err(SessionError::NotAwaitingApproval));
        session.retry().unwrap();
        let next = session.pending().unwrap().ticket; assert_ne!(first, next);
        assert_eq!(run(&mut session, first, yes(), &mut outputs, &mut seen), Err(SessionError::StaleApproval));
        outputs.push_back(Ok(FetchResponse::Html(b"ok".to_vec())));
        assert_eq!(run(&mut session, next, yes(), &mut outputs, &mut seen), Ok(Progress::Complete));
    }

    #[test]
    fn unsafe_redirects_and_redirect_loops_never_fetch_target() {
        let mut session = make_session(); let ticket = session.pending().unwrap().ticket;
        let mut seen = Vec::new(); let mut outputs = VecDeque::from([Ok(FetchResponse::Redirect("http://127.0.0.1/".into()))]);
        assert!(matches!(run(&mut session, ticket, yes(), &mut outputs, &mut seen), Err(SessionError::Fetch(FetchError::Policy(FetchPolicyError::ForbiddenAddress)))));
        assert_eq!(seen.len(), 1);
        let mut session = make_session(); let ticket = session.pending().unwrap().ticket;
        let mut seen = Vec::new(); let mut outputs: VecDeque<_> = (0..6).map(|_| Ok(FetchResponse::Redirect("/loop".into()))).collect();
        assert_eq!(run(&mut session, ticket, yes(), &mut outputs, &mut seen), Err(SessionError::Fetch(FetchError::Policy(FetchPolicyError::TooManyRedirects))));
        assert_eq!(seen.len(), 6);
    }

    #[test]
    fn reviewed_fetch_preview_survives_restart_and_saves_exact_original() {
        use personal_memory::{capture::{CaptureChoice, CaptureDraft, CaptureFormat}, Store};
        let dir = std::env::temp_dir().join(format!("refract-web-e2e-{}", Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let db = dir.join("library.db");
        let mut session = make_session();
        let id = Uuid::new_v4().to_string();
        let original = "\u{feff}<html><body><h1>Fixture</h1><p>Café 東京 1 &lt; 2.</p></body></html>".as_bytes().to_vec();
        let mut seen = Vec::new();
        let mut responses = VecDeque::from([Ok(FetchResponse::Redirect("/article".into())), Ok(FetchResponse::Html(original.clone()))]);
        let ticket = session.pending().unwrap().ticket;
        assert_eq!(run(&mut session, ticket, Approval::default(), &mut responses, &mut seen), Err(SessionError::ApprovalRequired));
        assert!(seen.is_empty());
        let mut store = Store::open(&db).unwrap();
        assert!(store.list_web_previews().unwrap().is_empty());
        assert!(store.list_items(10, 0).unwrap().is_empty());
        assert_eq!(run(&mut session, ticket, yes(), &mut responses, &mut seen), Ok(Progress::Complete));
        let result = session.take_result().unwrap();
        assert_eq!(result.final_address, "https://public.com/article");
        assert!(store.stage_web_preview(&id, &result.requested_address, &result.final_address, &result.bytes, 123, false).is_err());
        assert!(store.list_web_previews().unwrap().is_empty());
        store.stage_web_preview(&id, &result.requested_address, &result.final_address, &result.bytes, 123, true).unwrap();
        assert!(store.list_items(10, 0).unwrap().is_empty());
        drop(store);

        let mut store = Store::open(&db).unwrap();
        let staged = store.get_web_preview(&id).unwrap();
        assert_eq!(staged.html.as_bytes(), original);
        assert_eq!(staged.requested_url, "https://public.com/start");
        assert_eq!(staged.final_url, "https://public.com/article");
        let mut draft = CaptureDraft { format: CaptureFormat::Html, text: Some(staged.html), pdf_base64: None,
            source_url: Some(staged.final_url), review_hash: None, choice: CaptureChoice::Save, existing_id: None };
        let preview = store.capture_preview(&draft).unwrap();
        assert!(preview.excerpt.contains("Café 東京"));
        assert!(store.list_items(10, 0).unwrap().is_empty());
        // No durable save without the exact reviewed binding.
        assert!(store.capture_enqueue("web-reviewed-job-123456", &draft).is_err());
        draft.review_hash = Some(preview.review_hash);
        store.capture_enqueue("web-reviewed-job-123456", &draft).unwrap();
        drop(store);
        let mut store = Store::open(&db).unwrap();
        let job = store.capture_run("web-reviewed-job-123456").unwrap();
        assert_eq!(job.status, "completed");
        let item_id = job.result_item_id.unwrap();
        assert_eq!(std::fs::read(store.blob_dir.join(format!("{item_id}.original"))).unwrap(), original);
        assert_eq!(store.get_item(&item_id).unwrap().unwrap().source_url.as_deref(), Some("https://public.com/article"));
        assert_eq!(store.get_web_preview(&id).unwrap().html.as_bytes(), original);
        store.delete_web_preview(&id).unwrap();
        assert!(store.list_web_previews().unwrap().is_empty());
        assert_eq!(store.list_items(10, 0).unwrap().len(), 1);
        assert_eq!(std::fs::read(store.blob_dir.join(format!("{item_id}.original"))).unwrap(), original);
        drop(store);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn approvals_cannot_be_reused_in_another_session() {
        let first = make_session();
        let mut second = make_session();
        let mut seen = Vec::new(); let mut outputs = VecDeque::new();
        assert_eq!(run(&mut second, first.pending().unwrap().ticket, yes(), &mut outputs, &mut seen), Err(SessionError::StaleApproval));
        assert!(seen.is_empty());
    }

    #[test]
    fn cancel_discards_result_and_pending_approval() {
        let mut session = make_session(); session.cancel();
        assert!(session.pending().is_none());
        assert!(matches!(session.take_result(), Err(SessionError::NotComplete)));
        let mut completed = make_session(); let ticket = completed.pending().unwrap().ticket;
        let mut seen = Vec::new(); let mut outputs = VecDeque::from([Ok(FetchResponse::Html(b"private".to_vec()))]);
        assert_eq!(run(&mut completed, ticket, yes(), &mut outputs, &mut seen), Ok(Progress::Complete));
        completed.cancel();
        assert!(matches!(completed.take_result(), Err(SessionError::NotComplete)));
    }
}
