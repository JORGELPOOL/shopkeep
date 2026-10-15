// Backend end-to-end test against a mock MTN API. Run: node test/e2e.mjs   (from backend/)
import { spawn } from 'node:child_process';
import http from 'node:http';
import crypto from 'node:crypto';
const hp = (pin, phone) => crypto.createHash('sha256').update(`shopkeep:${phone}:${pin}`).digest('hex');

const st = {}; // mock MTN: reference -> status
const mock = http.createServer((q, r) => { q.resume(); q.on('end', () => {
  const send = (c, o) => { r.writeHead(c, { 'content-type': 'application/json' }); r.end(JSON.stringify(o ?? {})); };
  const u = q.url;
  if (u.startsWith('/collection/token')) return send(200, { access_token: 't', expires_in: 3600 });
  if (u === '/collection/v1_0/requesttopay' && q.method === 'POST') { st[q.headers['x-reference-id']] = 'PENDING'; return send(202); }
  if (u.startsWith('/_set/')) { const [, , id, s] = u.split('/'); st[id] = s; return send(200); }
  const m = u.match(/requesttopay\/(.+)$/); return m ? send(200, { status: st[m[1]] }) : send(404);
}); }).listen(4010);

const srv = spawn('node', ['server.js'], { stdio: 'inherit', env: { ...process.env, PORT: '3001', APP_KEY: 'k', MTN_BASE: 'http://localhost:4010',
  MTN_ENV: 'sandbox', MTN_CURRENCY: 'EUR', MTN_API_USER: 'u', MTN_API_KEY: 'k', MTN_SUB_KEY: 's', PUBLIC_URL: 'http://x' } });
await new Promise((r) => setTimeout(r, 800));

const call = async (method, path, { token, shop = 'shopA', body, key = 'k' } = {}) => {
  const r = await fetch('http://localhost:3001' + path, { method, body: body && JSON.stringify(body), headers: { 'content-type': 'application/json',
    ...(key ? { 'x-api-key': key } : {}), ...(token ? { 'x-shop-id': shop, 'x-token': token } : {}) } });
  let j = null; try { j = await r.json(); } catch {}
  return { s: r.status, j };
};
let pass = 0, fail = 0;
const t = (n, ok) => { console.log((ok ? 'PASS ' : 'FAIL ') + n); ok ? pass++ : fail++; };
const sync = (token, box, row, shop) => call('POST', '/sync', { token, shop, body: { box, row } });
const A = '233240000001', S = '233240000002', ADM = 'admintoken', ts = (n) => `2026-10-07T10:00:0${n}`;

t('missing API key is refused', (await call('GET', '/pull', { key: null })).s === 401);
const pf = await fetch('http://localhost:3001/sync', { method: 'OPTIONS' });
t('browser preflight (CORS) is answered', pf.status === 204 && (pf.headers.get('access-control-allow-headers') ?? '').includes('x-token'));
t('admin claims shop with first sync', (await sync(ADM, 'users', { id: 'u1', name: 'Ama', phone: A, role: 'admin', pin: hp('123456', A), shop: 'Ama Pharmacy', updated: ts(0) })).s === 200);
t('admin adds product', (await sync(ADM, 'products', { id: 'p1', name: 'Paracetamol', price: 5, cost: 3, updated: ts(0) })).s === 200);
t('admin adds expense', (await sync(ADM, 'expenses', { id: 'e1', desc: 'Rent', amount: 100, ts: ts(0), updated: ts(0) })).s === 200);
t('admin adds staff', (await sync(ADM, 'users', { id: 'u2', name: 'Kofi', phone: S, role: 'staff', pin: hp('1234', S), active: true, updated: ts(1) })).s === 200);

const bad = await call('POST', '/auth/login', { body: { phone: '0240000002', pin: hp('9999', S) } });
t('staff login with wrong PIN is refused', bad.s === 401);
const login = await call('POST', '/auth/login', { body: { phone: '0240000002', pin: hp('1234', S) } }); // typed with leading 0
t('staff login works, role=staff, shop name returned', login.s === 200 && login.j.role === 'staff' && login.j.shop === 'Ama Pharmacy');
const K = login.j.token;

t('staff can record a sale', (await sync(K, 'sales', { id: 's1', total: 5, status: 'paid', items: [], updated: ts(2) })).s === 200);
t('staff can record a stock move', (await sync(K, 'moves', { id: 'sale:s1:p1', pid: 'p1', delta: -1, updated: ts(2) })).s === 200);
t('staff cannot change products', (await sync(K, 'products', { id: 'p1', price: 1, updated: ts(3) })).s === 403);
t('staff cannot write users (no self-promotion)', (await sync(K, 'users', { id: 'u2', role: 'admin', phone: S, updated: ts(3) })).s === 403);
t('staff cannot write expenses', (await sync(K, 'expenses', { id: 'e2', amount: 1, updated: ts(3) })).s === 403);

const sp = (await call('GET', '/pull?since=0', { token: K })).j.rows;
t('staff pull: has sales/products, no expenses', sp.sales && sp.products && !sp.expenses);
t('staff pull: only own account row', sp.users.length === 1 && sp.users[0].id === 'u2');
const ap = (await call('GET', '/pull?since=0', { token: ADM })).j.rows;
t('admin pull: has expenses and all users', ap.expenses && ap.users.length === 2);
t('pull since=now returns nothing new', Object.keys((await call('GET', `/pull?since=${(await call('GET', '/pull?since=0', { token: ADM })).j.now}`, { token: ADM })).j.rows).length === 0);

t('other shop cannot reuse a phone number (409)', (await sync('tokB', 'users', { id: 'x1', phone: A, role: 'admin', pin: 'h', updated: ts(0) }, 'shopB')).s === 409);

const pay = await call('POST', '/payments/momo', { token: K, body: { network: 'mtn', phone: '0240000003', amount: 10 } });
t('MoMo request accepted, returns ref', pay.s === 200 && !!pay.j.ref);
const ref = pay.j.ref;
t('status is pending before customer approves', (await call('GET', `/payments/momo/${ref}`, { token: K })).j.status === 'pending');
t('another shop cannot read this payment', (await call('GET', `/payments/momo/${ref}`, { token: 'tokB', shop: 'shopB' })).s === 404);
await fetch(`http://localhost:4010/_set/${ref}/SUCCESSFUL`, { method: 'POST' });
t('status becomes paid after approval', (await call('GET', `/payments/momo/${ref}`, { token: K })).j.status === 'paid');
const ref2 = (await call('POST', '/payments/momo', { token: K, body: { network: 'mtn', phone: '0240000003', amount: 5 } })).j.ref;
await fetch(`http://localhost:4010/_set/${ref2}/FAILED`, { method: 'POST' });
t('declined payment reports failed', (await call('GET', `/payments/momo/${ref2}`, { token: K })).j.status === 'failed');
await fetch(`http://localhost:3001/webhooks/mtn`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ externalId: 'nope' }) });
t('webhook with unknown ref is harmless', true);
t('Telecel is honestly "not integrated" (501)', (await call('POST', '/payments/momo', { token: K, body: { network: 'telecel', phone: '0240000003', amount: 5 } })).s === 501);

// ---- sale and stock rules ----
const sale = (o) => ({ method: 'momo', network: 'mtn', phone: '0240000003', ts: '2026-10-07T10:00:06', staff: 'Kofi', device: 'd1', total: 10, items: [], ...o });
t('staff creates a pending MoMo sale', (await sync(K, 'sales', sale({ id: 'sp1', status: 'pending', ref, updated: ts(6) }))).s === 200);
t('staff settles it once the gateway says paid', (await sync(K, 'sales', sale({ id: 'sp1', status: 'paid', ref, updated: ts(7) }))).s === 200);
await sync(K, 'sales', sale({ id: 'sp2', status: 'pending', ref: 'not-a-real-ref', updated: ts(6) }));
t('staff cannot mark an unconfirmed MoMo sale paid', (await sync(K, 'sales', sale({ id: 'sp2', status: 'paid', ref: 'not-a-real-ref', updated: ts(7) }))).s === 403);
await sync(K, 'sales', sale({ id: 'sp3', status: 'pending', ref, updated: ts(6) }));
t('one payment cannot settle a second sale', (await sync(K, 'sales', sale({ id: 'sp3', status: 'paid', ref, updated: ts(7) }))).s === 403);
t('staff cannot edit a finished sale', (await sync(K, 'sales', { ...sale({ id: 'sp1', status: 'paid', ref, updated: ts(8) }), total: 1 })).s === 403);
t('staff cannot refund', (await sync(K, 'sales', sale({ id: 'sp1', status: 'refunded', ref, updated: ts(8) }))).s === 403);
t('admin can refund a paid sale', (await sync(ADM, 'sales', sale({ id: 'sp1', status: 'refunded', ref, updated: ts(8) }))).s === 200);
t('admin cannot refund an unpaid sale', (await sync(ADM, 'sales', sale({ id: 'sp2', status: 'refunded', ref: 'not-a-real-ref', updated: ts(8) }))).s === 403);
t('staff cannot write refund stock moves', (await sync(K, 'moves', { id: 'refund:sp1:p1', pid: 'p1', delta: 1, updated: ts(8) })).s === 403);
t('staff cannot add stock through a sale move', (await sync(K, 'moves', { id: 'sale:sx:p1', pid: 'p1', delta: 5, updated: ts(8) })).s === 403);
t('staff cannot cancel a sale the customer already paid for', (await sync(K, 'sales', sale({ id: 'sp3', status: 'cancelled', ref, updated: ts(8) }))).s === 403);
t('staff can cancel a sale with no confirmed payment', (await sync(K, 'sales', sale({ id: 'sp2', status: 'cancelled', ref: 'not-a-real-ref', updated: ts(9) }))).s === 200);

// ---- CSV export ----
const cash = (o) => sale({ method: 'cash', network: null, phone: '', staff: 'Ama', ref: null, ...o });
const X = [{ pid: 'p1', name: 'X', qty: 1, price: 7, cost: 2 }];
await sync(ADM, 'sales', cash({ id: 'sx1', status: 'paid', total: 10, ts: '2026-10-07T11:30:00', updated: ts(9), items: [{ pid: 'p1', name: 'Para, "500mg"', qty: 2, price: 5, cost: 3 }] }));
await sync(ADM, 'sales', cash({ id: 'sx2', status: 'paid', total: 7, ts: '2026-10-07T12:00:00', updated: ts(9), items: X }));
await sync(ADM, 'sales', cash({ id: 'sx2', status: 'refunded', total: 7, ts: '2026-10-07T12:00:00', updated: '2026-10-07T10:01:00', items: X }));
// ---- credit sales and debt payments ----
const cr1 = cash({ id: 'sc1', status: 'credit', method: 'credit', customerId: 'c1', phone: '0240000004', staff: 'Kofi', total: 20, ts: '2026-10-07T13:00:00', updated: ts(9), items: [{ pid: 'p1', name: 'Y', qty: 2, price: 10, cost: 4 }] });
t('staff can sell on credit', (await sync(K, 'sales', cr1)).s === 200);
t('staff cannot edit a credit sale', (await sync(K, 'sales', { ...cr1, total: 1, updated: '2026-10-07T10:02:00' })).s === 403);
t('staff can record a debt payment', (await sync(K, 'collections', { id: 'col1', customerId: 'c1', amount: 5, ts: '2026-10-07T14:00:00', updated: ts(9) })).s === 200);
t('staff cannot change a recorded payment', (await sync(K, 'collections', { id: 'col1', customerId: 'c1', amount: 500, ts: '2026-10-07T14:00:00', updated: '2026-10-07T10:02:00' })).s === 403);
const q = { type: 'sales', from: '2026-10-01', to: '2026-10-31' };
const getCsv = async (body) => { const l = await call('POST', '/export/link', { token: ADM, body }); const u = new URL(l.j.url); return fetch('http://localhost:3001' + u.pathname + u.search); };
const lk = await call('POST', '/export/link', { token: ADM, body: q });
t('admin gets an export link', lk.s === 200 && lk.j.url.includes('/export/sales.csv?t='));
t('staff cannot create export links', (await call('POST', '/export/link', { token: K, body: q })).s === 403);
const cr = await getCsv(q), bytes = new Uint8Array(await cr.clone().arrayBuffer()), csvText = await cr.text();
t('CSV is an attachment with a BOM for Excel', bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF && (cr.headers.get('content-disposition') ?? '').includes('attachment'));
t('CSV quotes commas and quotes correctly', csvText.includes('"Para, ""500mg"""'));
t('paid line shows revenue 10.00 and profit 4.00', csvText.split('\r\n').find((l) => l.includes('Para')).endsWith(',10.00,4.00'));
t('refunded line shows 0.00 revenue and profit', csvText.split('\r\n').find((l) => l.includes(',X,')).endsWith(',0.00,0.00'));
t('a different month returns no sale rows', !(await (await getCsv({ ...q, from: '2026-11-01', to: '2026-11-30' })).text()).includes('Para'));
t('credit sale appears in the sales CSV with revenue', csvText.split('\r\n').find((l) => l.includes(',Y,')).includes('Credit (pay later)') && csvText.split('\r\n').find((l) => l.includes(',Y,')).endsWith(',20.00,12.00'));
const pn = await (await getCsv({ type: 'pnl', from: '2026-10-01', to: '2026-10-31' })).text();
const pl = (label) => pn.split('\r\n').find((l) => l.startsWith(label));
t('P&L revenue counts paid and credit sales', pl('Sales revenue').endsWith(',30.00,30.00'));
t('P&L splits revenue on credit', pl('  On credit').endsWith(',20.00,20.00'));
t('P&L cost of goods and expenses', pl('Cost of goods sold').endsWith(',14.00,14.00') && pl('Total expenses').endsWith(',100.00,100.00'));
t('P&L net profit = revenue - costs - expenses', pl('Net profit').endsWith(',-84.00,-84.00'));
t('P&L lists customer debt still owed', pl('Customers still owe you').endsWith(',15.00'));
t('export link with a bad token is refused', (await fetch('http://localhost:3001/export/sales.csv?t=bad')).status === 404);

let last; for (let i = 0; i < 6; i++) last = await call('POST', '/auth/login', { body: { phone: '0249999999', pin: 'x' } });
t('6th wrong attempt on a number is locked (429)', last.s === 429);

await sync(ADM, 'users', { id: 'u2', name: 'Kofi', phone: S, role: 'staff', pin: hp('1234', S), active: false, updated: ts(5) });
t('deactivated staff token stops working at once', (await call('GET', '/pull?since=0', { token: K })).s === 401);
t('deactivated staff cannot log in again', (await call('POST', '/auth/login', { body: { phone: S, pin: hp('1234', S) } })).s === 401);

console.log(`\n${pass} passed, ${fail} failed`);
srv.kill(); mock.close();
import('node:fs').then((f) => { f.rmSync('data.json', { force: true }); process.exit(fail ? 1 : 0); });
