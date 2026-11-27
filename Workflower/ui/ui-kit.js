/* Workflower: the small tools of the interface: building DOM without innerHTML (everything from Snowflake is text, never markup),
   icons, the calls to the API, toasts and dialogs. The global WfKit. */
(function () {
  'use strict';

  var SVGNS = 'http://www.w3.org/2000/svg';

  function flatten(list, out) {
    list.forEach(function (x) { if (Array.isArray(x)) flatten(x, out); else out.push(x); });
    return out;
  }

  function applyAttrs(el, attrs) {
    if (!attrs) return;
    Object.keys(attrs).forEach(function (k) {
      var v = attrs[k];
      if (v === null || v === undefined || v === false) return;
      if (k === 'text') el.textContent = String(v);
      else if (k.slice(0, 2) === 'on' && typeof v === 'function') el.addEventListener(k.slice(2), v);
      else if (v === true) el.setAttribute(k, '');
      else el.setAttribute(k, String(v));
    });
  }

  function appendKids(el, kids) {
    flatten(kids, []).forEach(function (kid) {
      if (kid === null || kid === undefined || kid === false) return;
      el.appendChild(kid instanceof Node ? kid : document.createTextNode(String(kid)));
    });
  }

  /* h('div', {class: 'x', onclick: fn}, child, 'text', [more]): an HTML element. Text is always a text node. */
  function h(tag, attrs) {
    var el = document.createElement(tag);
    applyAttrs(el, attrs);
    appendKids(el, Array.prototype.slice.call(arguments, 2));
    return el;
  }

  /* The same for an SVG element. */
  function s(tag, attrs) {
    var el = document.createElementNS(SVGNS, tag);
    applyAttrs(el, attrs);
    appendKids(el, Array.prototype.slice.call(arguments, 2));
    return el;
  }

  /* ---- icons: shapes in a 16 x 16 box, drawn with a line, so that a state is a shape as well as a colour ---- */
  var ICONS = {
    error: ['<c 8 8 6.5>', 'M5.6 5.6l4.8 4.8M10.4 5.6l-4.8 4.8'],
    warning: ['M8 2.2l6.4 11.3H1.6z', 'M8 6.6v3.4M8 11.9v.3'],
    info: ['<c 8 8 6.5>', 'M8 7.2v4.3M8 4.7v.3'],
    check: ['M2.8 8.6l3.3 3.3 7.1-7.4'],
    cross: ['M3.8 3.8l8.4 8.4M12.2 3.8l-8.4 8.4'],
    skip: ['M2.5 8h7', 'M8.5 4.5L12.5 8l-4 3.5'],
    run: ['M5 3.2l7.2 4.8L5 12.8z'],
    clock: ['<c 8 8 6.5>', 'M8 4.4V8l2.6 1.6'],
    started: ['<c 8 8 5>'],
    suspended: ['<c 8 8 6>', 'M6.3 5.5v5M9.7 5.5v5'],
    pencil: ['M2.5 13.5l.8-3.2L10.8 2.8l2.4 2.4-7.5 7.5z'],
    when: ['M3 4h10M5 8h6M7 12h2']
  };

  function iconPaths(name, parent) {
    (ICONS[name] || ICONS.info).forEach(function (d) {
      var m = /^<c (\S+) (\S+) (\S+)>$/.exec(d);
      if (m) parent.appendChild(s('circle', { cx: m[1], cy: m[2], r: m[3] }));
      else parent.appendChild(s('path', { d: d }));
    });
    return parent;
  }

  /* An icon for HTML (aria-hidden: the word beside it says it). */
  function icon(name, cls) {
    var svg = s('svg', { class: 'icon ico ' + (cls || name), viewBox: '0 0 16 16', 'aria-hidden': 'true', focusable: 'false', fill: name === 'started' ? 'currentColor' : 'none',
      stroke: 'currentColor', 'stroke-width': '1.7', 'stroke-linecap': 'round', 'stroke-linejoin': 'round' });
    return iconPaths(name, svg);
  }

  /* An icon inside the canvas, at x, y with a size. */
  function iconAt(name, x, y, size, cls) {
    var g = s('g', { class: 'ico ' + (cls || ''), transform: 'translate(' + x + ',' + y + ') scale(' + (size / 16) + ')', fill: 'none',
      'stroke-width': '1.9', 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true' });
    return iconPaths(name, g);
  }

  /* ---- the calls to the API ---- */
  var SECRET = '';
  var meta = document.querySelector('meta[name="workflower-secret"]');
  if (meta) SECRET = meta.getAttribute('content') || '';
  var pending = 0;
  var busyListener = null;

  function busy(delta) {
    pending += delta;
    if (busyListener) busyListener(pending);
  }

  /* api('GET', '/api/graph', {query: {...}}) or api('POST', '/api/plan', {body: {...}}). Resolves to the parsed answer; a failed call
     rejects with an Error whose message is the server's text. quiet: true does not show "Working...". */
  async function api(method, path, opts) {
    var o = opts || {};
    var url = path;
    if (o.query) url += '?' + new URLSearchParams(o.query).toString();
    var init = { method: method, headers: { 'X-Workflower-Secret': SECRET } };
    if (o.body !== undefined) {
      init.headers['Content-Type'] = 'application/json';
      init.body = JSON.stringify(o.body);
    }
    if (!o.quiet) busy(1);
    try {
      var res;
      try { res = await fetch(url, init); }
      catch (e) { throw new Error('Cannot reach the Workflower server. Is it still running in PowerShell? (' + (e && e.message ? e.message : e) + ')'); }
      var text = await res.text();
      var data = null;
      try { data = text ? JSON.parse(text) : null; } catch (e) { data = null; }
      if (!res.ok) throw new Error(data && data.error ? String(data.error) : 'The server answered ' + res.status + (res.statusText ? ' ' + res.statusText : '') + '.');
      return data;
    } finally {
      if (!o.quiet) busy(-1);
    }
  }

  /* ---- toasts ---- */
  function toast(message, opts) {
    var o = opts || {};
    var kind = o.kind || 'info';
    var box = document.getElementById('toasts');
    if (!box) return null;
    while (box.children.length >= 5) box.removeChild(box.firstChild);
    var label = kind === 'error' ? 'Error. ' : kind === 'ok' ? 'Done. ' : '';
    var el = h('div', { class: 'toast ' + kind, role: kind === 'error' ? 'alert' : 'status' });
    var close = function () { if (el.parentNode) el.parentNode.removeChild(el); };
    el.appendChild(icon(kind === 'error' ? 'error' : kind === 'ok' ? 'check' : 'info'));
    el.appendChild(h('div', { class: 'msg' }, label ? h('span', { class: 'kind', text: label }) : null, String(message)));
    if (o.action) el.appendChild(h('button', { type: 'button', class: 'small', text: o.action.label, onclick: function () { close(); o.action.run(); } }));
    el.appendChild(h('button', { type: 'button', class: 'small', 'aria-label': 'Dismiss this message', text: 'Close', onclick: close }));
    box.appendChild(el);
    var ms = o.ms !== undefined ? o.ms : kind === 'error' ? 0 : o.action ? 12000 : 6000;
    if (ms) setTimeout(close, ms);
    return el;
  }

  /* ---- dialogs ---- */
  var confirmHook = null;
  function setConfirmHook(fn) { confirmHook = fn; }

  function waitClose(dlg) {
    return new Promise(function (resolve) {
      dlg.addEventListener('close', function () { resolve(dlg.returnValue); }, { once: true });
    });
  }

  /* askConfirm({title, body: text | node | [nodes], okLabel, danger}) -> Promise<boolean>. Esc and Cancel say no. */
  async function askConfirm(o) {
    if (confirmHook) return !!(await confirmHook(o));
    var dlg = document.getElementById('dlg-confirm');
    document.getElementById('dlg-confirm-title').textContent = o.title || 'Are you sure?';
    var body = document.getElementById('dlg-confirm-body');
    body.textContent = '';
    appendKids(body, [typeof o.body === 'string' ? h('p', { text: o.body }) : o.body]);
    var ok = document.getElementById('dlg-confirm-ok'), cancel = document.getElementById('dlg-confirm-cancel');
    ok.textContent = o.okLabel || 'OK';
    ok.className = o.danger ? 'danger' : 'primary';
    ok.onclick = function () { dlg.close('ok'); };
    cancel.onclick = function () { dlg.close('cancel'); };
    dlg.returnValue = '';
    var closed = waitClose(dlg);
    dlg.showModal();
    (o.danger ? cancel : ok).focus();
    return (await closed) === 'ok';
  }

  /* ---- files ---- */
  var downloadHook = null;
  function setDownloadHook(fn) { downloadHook = fn; }

  function download(fileName, text, type) {
    if (downloadHook) { downloadHook(fileName, text); return; }
    var blob = new Blob([text], { type: type || 'text/plain;charset=utf-8' });
    var url = URL.createObjectURL(blob);
    var a = h('a', { href: url, download: fileName });
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1500);
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (e) {
      var ta = h('textarea', { 'aria-hidden': 'true', style: 'position:fixed;left:-9999px;top:0' });
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (e2) { ok = false; }
      ta.remove();
      return ok;
    }
  }

  window.WfKit = {
    h: h, s: s, icon: icon, iconAt: iconAt, api: api, toast: toast, askConfirm: askConfirm, setConfirmHook: setConfirmHook,
    download: download, setDownloadHook: setDownloadHook, copyText: copyText, waitClose: waitClose,
    onBusy: function (fn) { busyListener = fn; }, appendKids: appendKids
  };
})();
