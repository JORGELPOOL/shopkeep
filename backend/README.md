# ShopKeep backend (starter)
`cp .env.example .env`, fill it in, then `npm install && npm start`. Needs Node 20+ and HTTPS (MTN callbacks and the PWA require it).
Endpoints: POST /sync, POST /payments/momo, GET /payments/momo/:ref, POST /webhooks/mtn.
MTN sandbox: create an API user and key in the MTN MoMo developer portal (Collections product), put them in .env, test with sandbox numbers.
Going live: switch MTN_BASE, MTN_ENV, MTN_CURRENCY=GHS and use production keys.

## Shops and staff devices
Each shop has an id and secret created on the admin's phone; the first sync claims it. Staff log in on a new phone through POST /auth/login (5 wrong PINs locks that number for 15 minutes), then the app downloads the shop with GET /pull. Data is stored per shop in data.json.

## Rules enforced on the server
Staff can create sales, but cannot edit a finished sale, refund, or mark a MoMo sale paid unless the gateway confirmed that exact amount once. Only the admin can refund (paid sales only). Staff stock moves are limited to selling (out) and cancelling (back in).
## CSV export
POST /export/link (admin) returns a 15-minute link to /export/sales.csv or /export/expenses.csv. Set PUBLIC_URL to your real HTTPS address.

## Credit sales, stricter cancel, profit and loss
Credit ("pay later") sales are revenue on the day sold; a customer's balance is credit sales minus payments recorded (collections). Staff can create credit sales and payments but not change them afterwards. A sale cannot be cancelled once the gateway reports the customer paid (server checks with the gateway first). /export/pnl.csv gives a month-by-month profit and loss.
