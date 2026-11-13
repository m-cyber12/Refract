/* Explicit address-only prototype: no background listener, page injection,
 * storage, network, telemetry, clipboard write or automatic app launch. */
(() => {
  'use strict';
  const load = document.getElementById('load');
  const share = document.getElementById('share');
  const address = document.getElementById('address');
  const status = document.getElementById('status');
  let selected = null;
  let selectionVersion = 0;
  let sharing = false;

  function acceptable(value) {
    if (typeof value !== 'string' || value.length === 0 || value.length > 8192 || /[\s\u0000-\u001f\u007f\\]/u.test(value)) return false;
    try {
      const parsed = new URL(value);
      const authority = value.split('://')[1]?.split(/[/?#]/u)[0] ?? '';
      return /^(http|https):\/\//iu.test(value) && (parsed.protocol === 'http:' || parsed.protocol === 'https:') && !!parsed.hostname && !authority.includes('@') && !parsed.username && !parsed.password;
    } catch (_) { return false; }
  }

  load.addEventListener('click', async () => {
    if (load.disabled) return;
    selectionVersion++;
    selected = null; address.value = ''; share.disabled = true; status.textContent = '';
    load.disabled = true;
    try {
      const tabs = await browser.tabs.query({ active: true, currentWindow: true });
      const value = tabs.length === 1 ? tabs[0].url : null;
      if (!acceptable(value)) { status.textContent = 'This address is unavailable or unsupported. No content was shared.'; return; }
      selected = value;
      address.value = value;
      share.disabled = sharing || typeof navigator.share !== 'function';
      status.textContent = typeof navigator.share !== 'function' ? 'System sharing is unavailable here. You can select and copy the displayed address manually.' : 'Review the displayed address before sharing.';
    } catch (_) { status.textContent = 'The browser did not provide an address. No content was shared.'; }
    finally { load.disabled = false; }
  });

  share.addEventListener('click', () => {
    if (selected === null || share.disabled || sharing || typeof navigator.share !== 'function') return;
    const version = selectionVersion;
    sharing = true;
    share.disabled = true;
    // Call directly from the click handler so transient activation is preserved.
    const finish = (message) => {
      sharing = false;
      share.disabled = selected === null || typeof navigator.share !== 'function';
      // A result for an earlier address must not describe a later selection.
      if (version === selectionVersion) status.textContent = message;
    };
    try {
      const result = navigator.share({ url: selected });
      Promise.resolve(result).then(() => finish('The system handled the share request. Check the selected app; no library save is implied.'))
        .catch(() => finish('Share was cancelled or unavailable. No library save is implied. You can select and copy the displayed address manually.'));
    } catch (_) { finish('System sharing is unavailable. You can select and copy the displayed address manually.'); }
  });
})();
