'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const script = fs.readFileSync(path.join(root, 'popup.js'), 'utf8');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));

function setup(value, shareAvailable = true) {
  const nodes = Object.fromEntries(['load', 'share', 'address', 'status'].map(id => [id, {
    value: '', textContent: '', disabled: id === 'share', handlers: {},
    addEventListener(event, handler) { this.handlers[event] = handler; },
  }]));
  const calls = { query: 0, share: [] };
  const browser = { tabs: { query: async () => { calls.query++; return [{ url: value }]; } } };
  const navigator = shareAvailable ? { share: item => { calls.share.push(item); return Promise.resolve(); } } : {};
  vm.runInNewContext(script, { document: { getElementById: id => nodes[id] }, browser, navigator, URL, Promise });
  return { nodes, calls };
}

test('manifest asks for active tab only; no background, injection, storage or network permission', () => {
  assert.deepEqual(manifest.permissions, ['activeTab']);
  for (const key of ['background', 'content_scripts', 'host_permissions', 'optional_permissions']) assert.equal(manifest[key], undefined);
  assert.doesNotMatch(script, /\b(fetch|XMLHttpRequest|localStorage|sessionStorage)\s*\(/);
});

test('does nothing before explicit click and shares only the reviewed address', async () => {
  const { nodes, calls } = setup('https://public.example/path?token=secret#fragment');
  assert.equal(calls.query, 0); assert.equal(calls.share.length, 0);
  await nodes.load.handlers.click();
  assert.equal(calls.query, 1); assert.equal(nodes.address.value, 'https://public.example/path?token=secret#fragment');
  assert.equal(nodes.share.disabled, false); assert.equal(calls.share.length, 0);
  nodes.share.handlers.click(); await Promise.resolve();
  assert.equal(calls.share.length, 1); assert.equal(calls.share[0].url, nodes.address.value);
  assert.deepEqual(Object.keys(calls.share[0]), ['url']);
});

test('rejects unsupported, credential-bearing and malformed addresses without sharing', async () => {
  for (const value of ['about:config', 'https://user:pass@public.example/', 'https://@public.example/', 'http://bad\\@host/', 'https://public.example/hello world', '', 'x'.repeat(8193), null]) {
    const { nodes, calls } = setup(value); await nodes.load.handlers.click(); nodes.share.handlers.click();
    assert.equal(nodes.address.value, ''); assert.equal(nodes.share.disabled, true); assert.equal(calls.share.length, 0);
  }
});

test('missing native sharing offers manual selection but never writes clipboard', async () => {
  const { nodes, calls } = setup('https://public.example/a', false);
  await nodes.load.handlers.click(); nodes.share.handlers.click();
  assert.equal(nodes.address.value, 'https://public.example/a'); assert.equal(nodes.share.disabled, true);
  assert.match(nodes.status.textContent, /copy.*manually/i); assert.equal(calls.share.length, 0);
});

test('loading a new invalid address clears the earlier one', async () => {
  let current = 'https://public.example/';
  const nodes = Object.fromEntries(['load', 'share', 'address', 'status'].map(id => [id, { value: '', textContent: '', disabled: id === 'share', handlers: {}, addEventListener(e, h) { this.handlers[e] = h; } }]));
  let sends = 0;
  vm.runInNewContext(script, { document: { getElementById: id => nodes[id] }, browser: { tabs: { query: async () => [{ url: current }] } }, navigator: { share: () => { sends++; } }, URL, Promise });
  await nodes.load.handlers.click(); current = 'about:blank'; await nodes.load.handlers.click(); nodes.share.handlers.click();
  assert.equal(nodes.address.value, ''); assert.equal(sends, 0);
});
