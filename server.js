import express from 'express';
import fs from 'node:fs';
import crypto from 'node:crypto';

const env = process.env;
const app = express();
app.use(express.json());

// Tiny JSON store so this runs anywhere. Swap for Postgres before real volume.
const FILE = './data.json';
const db = fs.existsSync(FILE) ? JSON.parse(fs.readFileSync(FILE, 'utf8')) : { rows: {}, payments: {} };
db.shops ??= {}; // { [shopId]: { secret, seq, rows: { box: { id: { row, seq } } } } }
db.fails ??= {};
const save = () => { fs.writeFileSync(FILE + '.tmp', JSON.stringify(db)); fs.renameSync(FILE + '.tmp', FILE); }; // atomic: a crash never leaves half a file

// What each role may write. Staff can sell and add customers; only the admin changes prices, accounts and expenses.
const WRITE = { admin: ['products', 'customers', 'sales', 'expenses', 'users', 'moves', 'collections'], staff: ['sales', 'customers', 'moves', 'collections'] };
const same = (a = '', b = '') => a.length === b.length && crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));
const appKeyOk = (req) => same(req.get('x-api-key') ?? '', env.APP_KEY ?? '!');
const th = (t) => crypto.createHash('sha256').update(t).digest('hex'); // tokens are stored hashed

// Each person has their own token. The first /sync for a new shop id claims it for the admin's phone.
// Role comes from the user's row on the SERVER every request, so deactivating someone cuts access at once.
const auth = (req, res, next) => {
  if (!appKeyOk(req)) return res.sendStatus(401);
  const id = req.get('x-shop-id'), token = req.get('x-token');
  if (!id || !token) return res.sendStatus(401);
  if (!db.shops[id] && req.method === 'POST' && req.path === '/sync') db.shops[id] = { seq: 0, rows: {}, tokens: { [th(token)]: {} } };
  const shop = db.shops[id], t = shop?.tokens[th(token)];
  if (!t) return res.sendStatus(401);
  let role = 'admin', uid = null;
  if (t.uid) {
    const u = shop.rows.users?.[t.uid]?.row;
    if (!u || u.active === false) return res.sendStatus(401);
    role = u.role; uid = t.uid;
  }
  Object.assign(req, { shop, shopId: id, role, uid });
  next();
};

const msisdn = (p) => { const d = String(p).replace(/\D/g, ''); return d.startsWith('233') ? d : '233' + d.replace(/^0/, ''); };

// ---------------- MTN MoMo Collection ----------------
const MTN = { base: env.MTN_BASE, env: env.MTN_ENV || 'sandbox', cur: env.MTN_CURRENCY || 'GHS' };
let tok = { v: null, exp: 0 };

async function mtnToken() {
  if (tok.v && Date.now() < tok.exp) return tok.v;
  const r = await fetch(`${MTN.base}/collection/token/`, { method: 'POST', headers: {
    Authorization: 'Basic ' + Buffer.from(`${env.MTN_API_USER}:${env.MTN_API_KEY}`).toString('base64'),
    'Ocp-Apim-Subscription-Key': env.MTN_SUB_KEY } });
  if (!r.ok) throw new Error('MTN token failed ' + r.status);
  const j = await r.json();
  tok = { v: j.access_token, exp: Date.now() + (j.expires_in - 60) * 1000 };
  return tok.v;
}

const mtn = {
  async request(ref, phone, amount) {
    const r = await fetch(`${MTN.base}/collection/v1_0/requesttopay`, { method: 'POST', headers: {
      Authorization: `Bearer ${await mtnToken()}`, 'X-Reference-Id': ref, 'X-Target-Environment': MTN.env,
      'X-Callback-Url': `${env.PUBLIC_URL}/webhooks/mtn`,
      'Ocp-Apim-Subscription-Key': env.MTN_SUB_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ amount: String(amount), currency: MTN.cur, externalId: ref,
        payer: { partyIdType: 'MSISDN', partyId: MTN.env === 'sandbox' ? String(phone).replace(/\D/g, '') : msisdn(phone) }, payerMessage: 'Shop payment', payeeNote: 'ShopKeep sale' }) });
    return r.status === 202;
  },
  async status(ref) {
    const r = await fetch(`${MTN.base}/collection/v1_0/requesttopay/${ref}`, { headers: {
      Authorization: `Bearer ${await mtnToken()}`, 'X-Target-Environment': MTN.env, 'Ocp-Apim-Subscription-Key': env.MTN_SUB_KEY } });
    if (!r.ok) return 'pending';
    const s = (await r.json()).status;
    return s === 'SUCCESSFUL' ? 'paid' : s === 'PENDING' ? 'pending' : 'failed';
  },
};

// Telecel Cash and AirtelTigo Money: implement request()/status() with the same shape
// (direct integrations or an aggregator), then they work in the app with no app changes.
const notReady = { request: async () => { throw Object.assign(new Error('not integrated'), { code: 501 }); }, status: async () => 'pending' };
const providers = { mtn, telecel: notReady, airteltigo: notReady };

const EXPIRE_MS = 10 * 60 * 1000; // stop waiting after 10 minutes so the app can restock

async function refresh(ref) {
  const p = db.payments[ref];
  if (!p || p.status !== 'pending') return p;
  p.status = await providers[p.network].status(ref);
  if (p.status === 'pending' && Date.now() - p.at > EXPIRE_MS) p.status = 'failed';
  save();
  return p;
}

app.post('/payments/momo', auth, async (req, res) => {
  const { network, phone, amount } = req.body;
  const provider = providers[network];
  if (!provider || !phone || !(amount > 0)) return res.status(400).json({ error: 'bad request' });
  const ref = crypto.randomUUID();
  try {
    if (!(await provider.request(ref, phone, amount))) return res.status(502).json({ error: 'gateway rejected request' });
  } catch (e) { return res.status(e.code || 502).json({ error: e.message }); }
  db.payments[ref] = { shop: req.shopId, network, phone, amount, status: 'pending', at: Date.now() };
  save();
  res.json({ ref });
});

app.get('/payments/momo/:ref', auth, async (req, res) => {
  const p = db.payments[req.params.ref]?.shop === req.shopId ? await refresh(req.params.ref) : null;
  p ? res.json({ status: p.status }) : res.sendStatus(404);
});

// MTN calls this when the customer approves or declines. We never trust the body:
// we re-check the payment with MTN using our own credentials.
app.post('/webhooks/mtn', async (req, res) => {
  const ref = req.body?.externalId;
  if (ref && db.payments[ref]) await refresh(ref).catch(() => {});
  res.sendStatus(200);
});

// ---------------- Notifications: SMS (Arkesel) + WhatsApp (Meta Cloud API) ----------------
async function sendSms(to, text) {
  const r = await fetch('https://sms.arkesel.com/api/v2/sms/send', { method: 'POST',
    headers: { 'api-key': env.ARKESEL_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ sender: env.SMS_SENDER || 'ShopKeep', message: text, recipients: [msisdn(to)] }) });
  if (!r.ok) throw new Error('sms ' + r.status);
}

// Free-form WhatsApp text only delivers inside the customer's 24h window.
// For receipts and reminders to cold contacts, register an approved template and switch to type "template".
async function sendWhatsApp(to, text) {
  const r = await fetch(`https://graph.facebook.com/v20.0/${env.WA_PHONE_ID}/messages`, { method: 'POST',
    headers: { Authorization: `Bearer ${env.WA_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ messaging_product: 'whatsapp', to: msisdn(to), type: 'text', text: { body: text } }) });
  if (!r.ok) throw new Error('whatsapp ' + r.status);
}

async function notify({ phone, message, channels = ['sms'] }) {
  let ok = false;
  if (channels.includes('sms') && env.ARKESEL_KEY) { try { await sendSms(phone, message); ok = true; } catch (e) { console.error(e.message); } }
  if (channels.includes('whatsapp') && env.WA_TOKEN) { try { await sendWhatsApp(phone, message); ok = true; } catch (e) { console.error(e.message); } }
  return ok;
}

// ---------------- Rules the app cannot bypass ----------------
// Sale fields staff may never change once a sale exists.
const FIXED = ['total', 'items', 'method', 'network', 'phone', 'ts', 'staff', 'device'];

/** Returns an error string, or null if this write is allowed. `old` is the stored version (if any). */
function check(role, box, row, old, shop, shopId) {
  if (box === 'moves' && role !== 'admin') {
    const id = String(row.id), d = Number(row.delta);
    if (id.startsWith('sale:') && d < 0) return null;   // selling takes stock out
    if (id.startsWith('undo:') && d > 0) return null;   // cancelling a sale puts it back
    return 'staff can only record sales and cancellations';
  }
  if (box === 'collections') return role !== 'admin' && old ? 'staff cannot change a recorded payment' : null;
  if (box !== 'sales') return null;
  if (row.status === 'refunded' && old?.status !== 'refunded' && old?.status !== 'paid') return 'only paid sales can be refunded';
  if (row.status === 'cancelled' && db.payments[old?.ref]?.status === 'paid') return 'the customer already paid; mark the sale as paid instead';
  if (role === 'admin') return null;
  if (!old) return ['paid', 'pending', 'credit'].includes(row.status) ? null : 'new sales must be paid, pending or on credit';
  if (old.status !== 'pending') return 'staff cannot change a finished sale';
  if (FIXED.some((k) => JSON.stringify(row[k]) !== JSON.stringify(old[k]))) return 'staff cannot edit sale details';
  if (!['pending', 'paid', 'failed', 'cancelled'].includes(row.status)) return 'not allowed';
  const pay = db.payments[old.ref];
  if (row.status === 'paid') {
    // Staff can only settle a MoMo sale when the gateway itself confirms this exact amount, once.
    const ok = old.method === 'momo' && pay?.status === 'paid' && pay.shop === shopId && Number(pay.amount) === Number(old.total);
    const reused = Object.values(shop.rows.sales ?? {}).some((e) => e.row.id !== row.id && e.row.ref === old.ref && e.row.status === 'paid');
    if (!ok || reused) return 'payment not confirmed by the gateway';
  }
  if (row.status === 'failed' && pay?.status !== 'failed') return 'gateway has not reported a failure';
  return null;
}

// ---------------- Sync ----------------
const phoneTaken = (phone, shopId) => Object.entries(db.shops).some(([id, sh]) =>
  id !== shopId && Object.values(sh.rows.users ?? {}).some((e) => e.row.phone === phone));

app.post('/sync', auth, async (req, res) => {
  const { box, row } = req.body || {};
  if (!box || !row) return res.sendStatus(400);
  if (box === 'notify') return (await notify(row)) ? res.sendStatus(200) : res.sendStatus(502); // 502 = app retries
  if (!WRITE[req.role]?.includes(box)) return res.sendStatus(403);
  if (box === 'users' && phoneTaken(row.phone, req.shopId)) return res.sendStatus(409); // number belongs to another shop
  if (box === 'sales' && row.status === 'cancelled') { // ask the gateway first so a payment made a moment ago is not missed
    const o = req.shop.rows.sales?.[row.id]?.row;
    if (o?.ref) await refresh(o.ref).catch(() => {});
  }
  const verdict = check(req.role, box, row, req.shop.rows[box]?.[row.id]?.row, req.shop, req.shopId);
  if (verdict) return res.status(403).json({ error: verdict });
  const rows = (req.shop.rows[box] ??= {});
  const old = rows[row.id]?.row;
  if (!old || old.updated <= row.updated) rows[row.id] = { row, seq: ++req.shop.seq }; // last write wins
  save();
  res.sendStatus(200);
});

// Changes since the app's last pull. Counters are server-side, so wrong phone clocks cannot hide rows.
// Staff never receive expenses, and only get their own account row (others' PIN hashes stay with the admin).
app.get('/pull', auth, (req, res) => {
  const since = Number(req.query.since) || 0, out = {};
  for (const [box, rows] of Object.entries(req.shop.rows)) {
    if (req.role !== 'admin' && box === 'expenses') continue;
    let list = Object.values(rows).filter((e) => e.seq > since).map((e) => e.row);
    if (box === 'users' && req.role !== 'admin') list = list.filter((u) => u.id === req.uid);
    if (list.length) out[box] = list;
  }
  res.json({ rows: out, now: req.shop.seq });
});

// Sign in on a new phone. 5 wrong PINs lock the number for 15 minutes (kept in the data file, survives restarts).
app.post('/auth/login', (req, res) => {
  if (!appKeyOk(req)) return res.sendStatus(401);
  const phone = msisdn(req.body?.phone ?? ''), pin = req.body?.pin;
  if (!phone || !pin) return res.sendStatus(400);
  const f = db.fails[phone] ?? { n: 0, until: 0 };
  if (Date.now() < f.until) return res.sendStatus(429);
  for (const [id, shop] of Object.entries(db.shops)) {
    const users = Object.values(shop.rows.users ?? {}).map((e) => e.row);
    const u = users.find((x) => x.phone === phone && x.active !== false);
    if (u && same(u.pin, pin)) {
      delete db.fails[phone];
      const token = crypto.randomBytes(24).toString('hex');
      const mine = Object.keys(shop.tokens).filter((k) => shop.tokens[k].uid === u.id);
      if (mine.length >= 5) delete shop.tokens[mine[0]]; // keep the 5 newest phones per person
      shop.tokens[th(token)] = { uid: u.id };
      save();
      return res.json({ shopId: id, token, role: u.role, shop: users.find((x) => x.role === 'admin')?.shop });
    }
  }
  f.n += 1;
  if (f.n >= 5) { f.n = 0; f.until = Date.now() + 15 * 60 * 1000; }
  db.fails[phone] = f;
  save();
  res.sendStatus(401);
});

// ---------------- CSV export for the accountant ----------------
// The app asks for a short-lived link (admin only), then opens it. Works the same on Android and web.
const esc = (v) => { const x = String(v ?? ''); return /[",\n\r]/.test(x) ? `"${x.replace(/"/g, '""')}"` : x; };
const csv = (rows) => '\uFEFF' + rows.map((r) => r.map(esc).join(',')).join('\r\n') + '\r\n'; // BOM so Excel reads accents
const m2 = (n) => Number(n || 0).toFixed(2);
const inRange = (ts, from, to) => { const d = String(ts).slice(0, 10); return d >= from && d <= to; };

// One row per item sold. Only paid and refunded sales appear; refunded lines show 0.00 revenue,
// so adding up the revenue column gives the true figure.
function salesCsv(shop, from, to) {
  const out = [['Receipt', 'Date', 'Time', 'Status', 'Payment method', 'Network', 'Customer phone', 'Served by', 'Item', 'Qty', 'Unit price', 'Unit cost', 'Line revenue', 'Line profit']];
  const sales = Object.values(shop.rows.sales ?? {}).map((e) => e.row)
    .filter((x) => ['paid', 'credit', 'refunded'].includes(x.status) && inRange(x.ts, from, to)).sort((a, b) => (a.ts < b.ts ? -1 : 1));
  for (const x of sales) {
    const counts = x.status !== 'refunded';
    for (const it of x.items ?? []) {
      out.push([String(x.id).slice(-5).toUpperCase(), x.ts.slice(0, 10), x.ts.slice(11, 16), x.status, x.method === 'cash' ? 'Cash' : x.method === 'credit' ? 'Credit (pay later)' : 'Mobile money',
        x.network ?? '', x.phone ?? '', x.staff ?? '', it.name, it.qty, m2(it.price), m2(it.cost),
        m2(counts ? it.price * it.qty : 0), m2(counts ? (it.price - it.cost) * it.qty : 0)]);
    }
  }
  return csv(out);
}

function expensesCsv(shop, from, to) {
  const out = [['Date', 'Time', 'Description', 'Amount']];
  Object.values(shop.rows.expenses ?? {}).map((e) => e.row).filter((x) => inRange(x.ts, from, to))
    .sort((a, b) => (a.ts < b.ts ? -1 : 1)).forEach((x) => out.push([x.ts.slice(0, 10), x.ts.slice(11, 16), x.desc, m2(x.amount)]));
  return csv(out);
}

// Profit and loss by month. Revenue counts paid + credit sales on the day of sale (credit is revenue when sold).
function pnlCsv(shop, from, to) {
  let [y, mo] = from.slice(0, 7).split('-').map(Number);
  const [ey, em] = to.slice(0, 7).split('-').map(Number), months = [];
  while ((y < ey || (y === ey && mo <= em)) && months.length < 24) { months.push(`${y}-${String(mo).padStart(2, '0')}`); if (++mo > 12) { mo = 1; y++; } }
  const bucket = () => Object.fromEntries(months.map((k) => [k, 0]));
  const rev = bucket(), cogs = bucket(), cash = bucket(), momo = bucket(), credit = bucket(), refunds = bucket(), coll = bucket(), expTotal = bucket(), cats = {};
  for (const e of Object.values(shop.rows.sales ?? {})) {
    const x = e.row, k = String(x.ts).slice(0, 7);
    if (!(k in rev)) continue;
    if (x.status === 'refunded') { refunds[k] += Number(x.total); continue; }
    if (x.status !== 'paid' && x.status !== 'credit') continue;
    rev[k] += Number(x.total);
    (x.method === 'cash' ? cash : x.method === 'credit' ? credit : momo)[k] += Number(x.total);
    for (const it of x.items ?? []) cogs[k] += it.cost * it.qty;
  }
  for (const e of Object.values(shop.rows.collections ?? {})) { const k = String(e.row.ts).slice(0, 7); if (k in coll) coll[k] += Number(e.row.amount); }
  for (const e of Object.values(shop.rows.expenses ?? {})) {
    const x = e.row, k = String(x.ts).slice(0, 7);
    if (!(k in expTotal)) continue;
    expTotal[k] += Number(x.amount);
    const name = String(x.desc ?? 'Other').trim() || 'Other';
    (cats[name] ??= bucket())[k] += Number(x.amount);
  }
  const sum = (o) => months.reduce((a, k) => a + o[k], 0);
  const line = (label, o) => [label, ...months.map((k) => m2(o[k])), m2(sum(o))];
  const diff = (a, b) => Object.fromEntries(months.map((k) => [k, a[k] - b[k]]));
  const gross = diff(rev, cogs), net = diff(gross, expTotal);
  const pct = [ 'Gross margin %', ...months.map((k) => (rev[k] ? ((gross[k] / rev[k]) * 100).toFixed(1) : '0.0')), (sum(rev) ? ((sum(gross) / sum(rev)) * 100).toFixed(1) : '0.0')];
  const owed = Object.values(shop.rows.sales ?? {}).filter((e) => e.row.status === 'credit').reduce((a, e) => a + Number(e.row.total), 0)
    - Object.values(shop.rows.collections ?? {}).reduce((a, e) => a + Number(e.row.amount), 0);
  const out = [['Profit and loss', ...months, 'Total'], line('Sales revenue', rev), line('  Cash', cash), line('  Mobile money', momo), line('  On credit', credit),
    line('Cost of goods sold', cogs), line('Gross profit', gross), pct, [],
    ['Expenses'], ...Object.keys(cats).sort().map((n) => line('  ' + n, cats[n])), line('Total expenses', expTotal), [],
    line('Net profit', net), [],
    ['Memo (not in profit)'], line('Refunds given', refunds), line('Customer debt payments received', coll),
    ['Customers still owe you (as of this export)', ...months.map(() => ''), m2(owed)]];
  return csv(out);
}

const links = new Map(); // token -> { shopId, type, from, to, exp }
app.post('/export/link', auth, (req, res) => {
  if (req.role !== 'admin') return res.sendStatus(403);
  const { type, from, to } = req.body ?? {}, day = /^\d{4}-\d{2}-\d{2}$/;
  if (!['sales', 'expenses', 'pnl'].includes(type) || !day.test(from) || !day.test(to)) return res.sendStatus(400);
  for (const [k, v] of links) if (v.exp < Date.now()) links.delete(k);
  const token = crypto.randomBytes(18).toString('hex');
  links.set(token, { shopId: req.shopId, type, from, to, exp: Date.now() + 15 * 60 * 1000 });
  res.json({ url: `${env.PUBLIC_URL}/export/${type}.csv?t=${token}` });
});

app.get(['/export/sales.csv', '/export/expenses.csv', '/export/pnl.csv'], (req, res) => {
  const type = req.path.includes('expenses') ? 'expenses' : req.path.includes('pnl') ? 'pnl' : 'sales', l = links.get(String(req.query.t));
  if (!l || l.exp < Date.now() || l.type !== type) return res.status(404).send('This link has expired. Create a new one in the app.');
  res.set({ 'Content-Type': 'text/csv; charset=utf-8', 'Content-Disposition': `attachment; filename="${type}-${l.from}-to-${l.to}.csv"` });
  res.send({ sales: salesCsv, expenses: expensesCsv, pnl: pnlCsv }[type](db.shops[l.shopId], l.from, l.to));
});

app.listen(env.PORT || 3000, () => console.log('ShopKeep backend up'));
