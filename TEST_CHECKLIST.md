# ShopKeep test checklist
Tick each box. Write what you saw next to any failure.

## A. Automated backend test (done: 27/27 passed against a mock MTN API)
`cd backend && npm install && node test/e2e.mjs`  Re-run after every backend change.

## B. MTN sandbox setup (once)
- [ ] MTN MoMo developer portal: subscribe to Collections, copy the primary subscription key into MTN_SUB_KEY
- [ ] Create an API user and key (POST /v1_0/apiuser, then /v1_0/apiuser/{id}/apikey) and put them in .env
- [ ] .env: MTN_ENV=sandbox, MTN_CURRENCY=EUR, PUBLIC_URL = your HTTPS address; backend running on HTTPS
- [ ] App: apiBase and appKey in lib/data.dart match the server
- [ ] Sandbox test numbers (confirm in MTN docs): any number succeeds; 46733123450 fails; 46733123451 rejected; 46733123452 times out

## C. Create a shop (phone 1, admin)
- [ ] First launch shows "Set up your shop"; PIN under 6 digits is refused
- [ ] Admin lands on Today with 5 tabs including Manage
- [ ] Add 2 products (cost, price, stock 10); Stock shows 10; Today lists none as low
- [ ] Add a customer with a phone number; add an expense; Today profit goes down by it

## D. Sell with MoMo (phone 1)
- [ ] Sell 2 items, Mobile money, MTN, a sandbox success number: "Waiting for payment" card appears
- [ ] Within ~10 seconds it disappears; sale counts in Today sales and profit; stock fell by 2
- [ ] Sale to the failing number: card appears, then clears; stock goes back; no revenue
- [ ] Airplane mode, sell by MoMo: saved as unpaid; reconnect, Send request works
- [ ] Cash sale: receipt sheet opens; WhatsApp and SMS open the right apps with the text filled in

## E. Staff on a second phone (or a second browser profile)
- [ ] Admin: Manage > Staff > Add staff (name, phone, 4-digit PIN)
- [ ] Phone 2 fresh install: "Already have a shop? Log in", number typed with a leading 0, correct PIN: shop loads
- [ ] Staff sees Today (sales only, no profit), Sell, Stock (no Add/Edit), Customers; no Manage tab
- [ ] Staff sells; within 2 minutes the sale shows on the admin's phone and stock matches
- [ ] Wrong PIN 5 times: "Too many wrong tries"
- [ ] Admin switches staff off: staff's next sync stops and a new login is refused

## F. Offline and stock
- [ ] Both phones offline, each sells the same item once; both online: stock fell by 2 on both
- [ ] Phone 2 offline for a day of sales, then online: all sales appear on phone 1, "to sync" counter reaches 0
- [ ] Two shops cannot register the same phone number (red message on Today)

## G. Web (PWA) and low-end phones
- [ ] `flutter build web --release --pwa-strategy=offline-first`; open on phone Chrome, Add to Home screen
- [ ] After one online visit, airplane mode: app opens, sells, records expenses
- [ ] Release APK size and cold start time on the cheapest phone you have

## H. New: lockout, printing, barcode, monthly
- [ ] 5 wrong PINs on one phone: "Try again in N min"; correct PIN is refused during lockout; works again after 15 min or after a correct login elsewhere; survives app restart
- [ ] Cash sale > Print: pick the paired printer once; receipt prints; second print needs no picking; printer off: clear message, list offered again
- [ ] Reports > Monthly shows 6 bars, January data not mixed into December
- [ ] Stock > edit item > scan icon fills the barcode; Sell > scan icon adds that item; unknown code says "Add it in Stock"
- [ ] USB/Bluetooth scanner into the Sell search box adds the item on Enter

## I. Sales history
- [ ] History icon (top bar) opens Sales; sales grouped Today / Yesterday / dates, each day showing its paid total
- [ ] Filters All / Cash / Mobile money / Not paid; search by item name and by customer phone
- [ ] Tap a sale: items, method, customer, who served; "Receipt" opens print / WhatsApp / SMS (reprint works days later)
- [ ] Staff login sees only their own sales; admin sees everyone's
- [ ] Admin refunds a paid sale: status Refunded, struck through, Today profit drops, stock goes back; second device shows the same after sync
- [ ] Failed / cancelled MoMo sales appear under "Not paid" and never count in the day total

## J. Server rules and CSV export
- [ ] `node test/e2e.mjs` passes 45/45
- [ ] Staff phone: Waiting for payment has no "Customer paid cash" button; admin phone does
- [ ] Staff cannot refund (no button; a forced request is refused by the server)
- [ ] Manage > Export for accountant: Sales, This month > link > Download opens the file; opens in Excel with columns tidy and item names with commas intact
- [ ] Totals check: sum of "Line revenue" equals the Sales figure in Reports for the same period
- [ ] Refunded sale appears with 0.00 revenue; unpaid, failed and cancelled sales are absent
- [ ] Expenses export matches the Expenses list
- [ ] Offline: Create link says changes have not reached the server, instead of exporting stale data
- [ ] Link stops working after 15 minutes

## K. Credit, cancel rule, profit and loss
- [ ] `node test/e2e.mjs` passes 57/57
- [ ] Sell > Pay later: choose a customer, sale recorded, stock falls, receipt says "ON CREDIT"; with no customers it asks you to add one
- [ ] Customers shows "Owes GH₵x" (largest debt first); Today shows "Customers owe you"
- [ ] Customer screen: Record payment (cannot exceed balance); balance drops; history lists sale and payment; Remind queues an SMS/WhatsApp
- [ ] Credit sale counts in Today sales and profit on the day sold; recording the payment later does NOT change profit
- [ ] Sales history: "On credit" filter and label; staff phone can sell on credit and record a payment but cannot edit it
- [ ] MoMo sale where the customer pays at the same moment you tap Cancel: app says "already paid" and marks it paid
- [ ] Export > Profit & loss > Last 6 months opens in Excel; net profit = sales - cost of goods - expenses; matches Reports for a single month
