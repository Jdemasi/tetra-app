# CLAUDE.md — Tetra Job-Cost App

Map of the app for AI sessions. Regenerated 2026-08-31 from `index.html` @ **12,381 lines**.
Everything below was read out of the source, not remembered. Line numbers drift after edits —
always `grep` for the function name, don't trust the number.

---

## 0. Standing rules for every session

- Joe uploads the **current** `index.html` at session start. Work from that file only. If it
  isn't there, ask before editing.
- Edit **surgically**. `grep` for the function first. Reuse existing helpers
  (`companyDocIdentity`, `withCompany`, `createPODraft`, `navigate`, `toast`, `esc`, `fmt`).
  Don't rebuild what works.
- `node --check` the inline JS after every edit. Never hand over code that won't parse.
  (Extract script blocks: the app JS is the 2nd `<script>` with no `src`, ~621 KB.)
- Say **explicitly** if a change needs new SQL, and write it as a separate `.sql` migration.
- Remind Joe to hard-refresh after deploy.
- Don't build the deferred items (§11) unless asked.
- End any code-changing session with a one-block changelog entry to paste into §12.

---

## 1. Stack & deploy

| Piece | Detail |
|---|---|
| App | Single-file `index.html`, vanilla JS, no build step, no framework |
| Companion | `assets.js` — per the comment above its `<script>` tag, defines `ST120_BLANK_B64` (blank fillable ST-120.1 PDF) and `ST120_SIG_B64` (Joe's signature PNG). Not verified directly — the file was not in this session. |
| Backend | Supabase (Postgres + Auth + Storage), client `db` created at line ~1051 |
| Deploy | GitHub → Vercel, `https://tetra-app-seven.vercel.app/` |
| Email/inbox | Microsoft Graph via MSAL browser popup |

**Eagerly loaded** (in `<head>`): `@supabase/supabase-js@2`, `xlsx@0.18.5` (SheetJS), both from jsDelivr.

**Lazily loaded** — each is idempotent; the multi-CDN ones try mirrors in order:

| Loader | Library | Global |
|---|---|---|
| `ensureTesseract` | tesseract.js 5.0.4 | `Tesseract` |
| `ensurePDFjs` | pdf.js 3.11.174 (+worker) | `pdfjsLib` |
| `ensureMSAL` | @azure/msal-browser — jsDelivr `2.38.4` → alcdn.msauth.net **`2.38.1`** → unpkg `2.38.4` | `msal` |
| `ensureHtml2Pdf` | html2pdf.js 0.10.1 | `html2pdf` |
| `ensurePdfLib` | pdf-lib 1.17.1 (jsDelivr → unpkg) | `PDFLib` |
| `ensureDocx` | docx 9.0.3 (jsDelivr → unpkg → docx 8.5.0) | `docx` |

`loadScriptFrom(src)` is the shared `<script>`-injection promise helper.

**Constants**: `STORAGE_BUCKET='tetra-files'`, `GRAPH_CONFIG` (clientId / tenantId / redirectUri /
scopes `Mail.Send,Mail.ReadWrite,Mail.Read` / `sendFrom:'me'`), `INBOX_SCAN_WINDOW_DAYS=60`,
`INBOX_SCAN_CAP=300`, `INBOX_SCAN_MAX_PAGES=200`, `CONF` confidence levels
(`HIGH=90, MED_HIGH=75, MED=60, LOW=40, GUESS=20`).

---

## 2. Multi-company model — read this before touching any query

Three companies share one Supabase DB, distinguished **only by `company_id` (UUID)**:
Tetra Mechanical, Tetra Fire Protection, JDM Piping & Design.

> **JDM's name contains an `&`.** Never match a company with `like 'JDM%'` or any name string.
> Use `company_id` or `companyDocIdentity()`. As of this writing no such name-match exists in
> the code for data scoping — keep it that way.

```js
function withCompany(query) {
  if (state.activeCompanyId) return query.eq('company_id', state.activeCompanyId);
  return query;
}
function activeCompany() {
  return (state.companies || []).find(c => c.id === state.activeCompanyId) || null;
}
```

`companyDocIdentity()` is the single letterhead source for every generated document. Returns
`{ name, addr1, city, state, zip, phone, email, logo, cityStateZip (getter), addrOneLine (getter) }`.
Logo resolves `activeCompany().logo_b64` → `getTetraLogoDataURL()` (hidden `#tetra-logo-src` img
from assets.js). **Every field falls back to Tetra Mechanical's own values**, so an incomplete
company row silently renders Tetra Mechanical letterhead on a JDM document.

**Company-scoped tables** (have `company_id`, queried through `withCompany`):
`projects, purchases, purchase_orders, invoices, labor_entries, phases, project_budgets,
cost_line_items, change_orders, pay_applications, lien_waivers, checks, invoice_reminders,
project_subs, invoice_inbox_queue`

**Global / shared rosters** (no `company_id`, deliberately shared across all three):
`employees, vendors, subcontractors, cost_codes, companies, app_settings, sov_line_items,
pay_app_line_items`

---

## 3. Data model

Table → columns the app actually reads/writes. `*` = soft-deleted via `deleted_at`.

| Table | Columns |
|---|---|
| `companies` | `id, name, color, logo_b64, address, city, state, zip, phone, email, active` |
| `projects` * | `id, company_id, job_number, job_name, client, status, date_started, base_contract, approved_cos, retainage_pct, payment_terms, burden_rate, project_name_full, project_address, owner_name, general_contractor, gc_contact_name, gc_contact_email, gc_contact_phone, gc_address, contract_for, contract_date, site_contact, tax_exempt, coa_number, prime_contract_date, contract_pdf_url, created_at, deleted_at` |
| `phases` | `id, company_id, project_id, phase_name, status, budgeted_hours, phase_budget, sort_order` |
| `project_budgets` | `project_id, company_id, category, budgeted_amount` — unique `(project_id, category)`, upserted |
| `cost_line_items` | `id, company_id, project_id, item_name, budgeted_amount, created_at` |
| `purchases` * | `id, company_id, project_id, phase_id, vendor, invoice_number, invoice_date, po_number, po_id, cost_code, category, po_amount, paid_amount, terms_days, status, notes, payment_reference, pdf_url, deleted_at` |
| `purchase_orders` * | `id, company_id, project_id, phase_id, po_number, vendor, description, cost_code, committed_amount, invoiced_amount, paid_amount, issue_date, expected_date, status, invoice_number, po_type, notes, pdf_url, deleted_at` |
| `labor_entries` * | `id, company_id, project_id, phase_id, employee_id, employee_name, role, week_ending, st_hours, ot15_hours, ot2_hours, st_rate, created_at, deleted_at` |
| `employees` | `id, name, role, st_rate, effective_date, active` |
| `vendors` | `id, name, contact_name, phone, email, address, payment_terms, default_cost_code, is_1099, w9_on_file, is_subcontractor, notes, active, approved` |
| `subcontractors` | `id, company_name, contact_name, contact_email, contact_phone, trade, coi_expiry, gl_expiry, wc_expiry, license_number, active` |
| `project_subs` | `project_id, company_id, subcontractor_id, contract_amount, status` |
| `cost_codes` | `id, code, name/description` |
| `invoices` * | `id, company_id, project_id, invoice_number, invoice_date, description, bill_to, billed_amount, retainage_pct, paid_amount, terms_days, status, notes, pdf_url, created_at, deleted_at, payment_date` — `payment_date` added 2026-08-31 by `migrations/2026-08-31_add_payment_date.sql`; see §10.11 |
| `change_orders` | `id, company_id, project_id, co_number, description, amount, co_type, status, submitted_date, approved_date, pdf_url, created_at` |
| `sov_line_items` | `id, project_id, item_number, description, scheduled_value, sort_order` |
| `pay_applications` | `id, company_id, project_id, app_number, period_ending, submitted_date, total_scheduled_value, previous_billed, current_billed, total_completed, retainage_pct, retainage_amount, net_payment_due, balance_to_finish, payment_terms, paid_amount, status, notes` |
| `pay_app_line_items` | `id, pay_app_id, project_id, item_number, sort_order, description, scheduled_value, previous_pct, previous_amount, current_pct, current_amount, total_completed, total_pct, balance_to_finish, retainage` — **all `_pct` columns are stored as fractions** (`thisPct / 100`), not whole percents |
| `lien_waivers` | `id, company_id, project_id, waiver_type, subtype, party_type, party_name, amount, through_date, received_date, payment_ref, check_id, status, created_at` |
| `checks` * | `id, company_id, check_number, check_date, payee, amount, memo, purchase_id, voided, deleted_at` |
| `invoice_reminders` | `invoice_id, company_id, stage, days_overdue` |
| `invoice_inbox_queue` | see §7 |
| `app_settings` | `key, value` — keys in use: `active_company_id`, `inbox_last_scan` |

**Status vocabularies** (exact strings — the UI builds CSS classes from them):

| Entity | Values |
|---|---|
| project | `Active`, `Complete`, `On Hold`, `Bidding` |
| phase | `Not Started`, (in-progress/complete states) |
| purchase (AP) | `Pending`, `Approved`, `Paid`, `Overdue` |
| purchase order | `Draft`, `Open`, `Ordered`, `Received`, `Invoiced`, `Closed`, `Cancelled` |
| invoice (AR) | `Pending`, `Paid`, `Partial`, `Overdue` |
| change order | `Pending`, `Submitted`, `Approved`, `Rejected` |
| pay application | `Draft`, `Submitted`, `Approved`, `Paid` |
| lien waiver | `Pending`, `Received`, `Executed` |
| inbox queue | `pending`, `confirmed`, `filed_as_po`, `dismissed` (lowercase!) |

**Storage** — one bucket, `tetra-files`. Path convention from `buildFilePath(project, category, keyParts, filename)`:
`<job_number>-<job_name>/<category>/<key>_<unix_ts>.<ext>`, e.g.
`2601-Edenwald/purchase_orders/PO-2002_Nefco_1715812345.pdf`. Null project → `_shop/`.
Reads go through `getFileURL` (1-hour signed URL) or `fetchStoredFileBase64` (for email attachments).

---

## 4. Global state & startup

```js
let state = { view:'dashboard', projects:[], activeProject:null, activeModule:null,
              employees:[], phases:[], purchases:[], laborEntries:[], invoices:[],
              companies:[], activeCompanyId:null };
```

Added dynamically, so they don't exist until first touched: `showCompletedJobs`, `projectPOs`,
`costCodes`, `allPOs`, `vendors`, `allSubs`, `checks`, `orderedByNames`.

**Startup order** — `bootstrapAuth()` is the last statement in the file:

1. `bootstrapAuth()` → `db.auth.getSession()`. Session → hide `#login-overlay`, `init()`. No session → show overlay.
2. `doLogin()` → `signInWithPassword` → `init()`.
3. `init()` → `loadCompanies()` **first** (so `activeCompanyId` exists before any `withCompany`
   query) → load `projects` (company-scoped, `deleted_at is null`) → load `employees` (global) →
   `renderSidebarProjects()` → `renderCompanySwitcher()` → `renderDashboard()`.
4. `loadCompanies()` restores `app_settings.active_company_id`; falls back to the first company
   matching `/tetra mechanical/i`, else the first row.
5. `switchCompany(id)` persists the choice, resets `activeProject/activeModule/view`, reloads projects, re-renders.
6. `doLogout()` → `signOut()` → `location.reload()` (no in-memory teardown).

**Routing**: `navigate(view, projectId=null, module=null)` sets state, toggles sidebar classes,
calls `render()`. `render()` is a flat if/else chain on `state.view`, then on `state.activeModule`
when `view==='project'`. **Adding a view means editing three places**: `render()`,
`updateBreadcrumb()`, and the sidebar markup / `renderSidebarProjects()`.

**Shared helpers**: `$(id)`, `fmt` (whole-dollar), `fmtD` (2-decimal), `fmtPct`, `today()` (YYYY-MM-DD),
`toast(msg, type)` (2.8 s), `openModal`/`closeModal` (`closeModal` special-cases `modal-purchase` to
tear down the inbox split-PDF view), `clearForm(ids)`, `esc(s)`.

**Attach-UI family** (`renderAttachUI`, `handleAttachUpload`, `setAttachIndicatorAttached`,
`setAttachIndicatorEmpty`, `resetAttachIndicator`, `getPendingAttachFile`, `clearPendingAttachFile`):
stashes the picked `File` on the modal element as `_pendingAttachFile`; the `save*` function
uploads it. Used by `modal-invoice` (`inv-attach`), `modal-po` (`po-attach`), `modal-co` (`co-attach`).
`modal-purchase` has its own hand-rolled indicator instead.

---

## 5. Views

**Sidebar order** — Dashboards: Portfolio, Dashboard, Collections, Waivers, WIP Schedule, AR Aging,
Customer AR, AP Aging · Logs: PO Log, AP Master, Invoice Inbox, AR Master, Change Order Log,
Subcontractors · Jobs (dynamic + New Project) · Setup: Employees, Vendors, Checks, Trash, Sign Out.

| View key | Render fn | What it shows |
|---|---|---|
| `dashboard` | `renderDashboard` | Company KPIs: contract value, billed/paid, cost, active jobs, estimated profit |
| `portfolio` | `renderPortfolio` | Cross-company rollup — **deliberately bypasses `withCompany`** |
| `collections` | `renderCollections` | Overdue AR worklist with aging-stage badges → reminder emails |
| `waivers` | `renderWaiversOutstanding` | Lien waivers still `Pending` across all jobs |
| `wip` | `renderWIP` | WIP schedule: earned vs billed vs cost, over/under-billing |
| `ar-aging` | `renderARaging` | AR buckets (Current / 1-30 / 31-60 / 61-90+) from `computeARRows()` |
| `customer-ar` | `renderCustomerAR` | Same AR data grouped by customer, for statements |
| `ap-aging` | `renderAPAging` → `renderAPAgingView` | Unpaid vendor bills, days aging |
| `employees` | `renderEmployees` | Employee roster |
| `vendors` | `renderVendors` | Vendor list + cost codes + purchase history |
| `checks` | `renderChecks` | Check register (voided shown dimmed/struck) |
| `trash` | `renderTrash` | Soft-deleted rows, restore / permanent delete |
| `master-pos` | `renderMasterPOs` | All POs, all jobs |
| `master-ap` | `renderMasterAP` → `renderMasterAPView` | All vendor invoices |
| `master-inbox` | `renderInvoiceInbox` | Invoice Inbox (§7) |
| `master-ar` | `renderMasterAR` → `renderMasterARView` | All client invoices / pay apps |
| `master-cos` | `renderMasterCOs` → `renderMasterCOsView` | All change orders |
| `master-subs` | `renderMasterSubs` | Sub roster + COI expiry status |

**Per-project modules** (sidebar order — note `profit` sits before `pos`/`subs`):

| Module | Render fn | What it shows |
|---|---|---|
| `setup` (default) | `renderJobSetup` | Job/contract header, GC info, tax-exempt + ST-120 fields |
| `purchases` | `renderPurchases` | Job AP: vendor bills → phase / cost code / PO |
| `labor` | `renderLabor` | ST/OT1.5/OT2 hours per employee, burdened cost |
| `cos` | `renderChangeOrders` | Job CO log + Approved/Pending/Rejected totals |
| `invoices` | `renderInvoices` | Manual client invoices |
| `payapps` | `renderPayApps` | AIA G702/G703 pay applications |
| `phases` | `renderPhaseBreakdown` | Phase budgets/hours vs actuals |
| `bva` | `renderBVA` | Budget vs Actual by category |
| `profit` | `renderProfit` | Full job profit & cost report |
| `pos` | `renderPOs` | Job purchase orders |
| `subs` | `renderSubs` | Subs assigned to this job (`project_subs` ⋈ `subcontractors`) |
| `liens` | `renderLiens` | Job lien waivers |

**Modals** (`id` → open / save / delete):

| Modal | Open | Save | Delete |
|---|---|---|---|
| `modal-project` | `btn-new-project`, `editProject` | `saveProject` | `deleteProject` |
| `modal-phase` | `openAddPhase`, `editPhase` | `savePhase` | `deletePhase` / `deletePhaseFromModal` |
| `modal-purchase` | `openNewPurchase`, `editPurchase` | `savePurchase` | `deletePurchase` / `deletePurchaseFromModal` |
| `modal-labor` | `openNewLabor`, `openEditLabor` | `saveLabor` | `deleteLaborEntry` / `deleteLaborFromModal` |
| `modal-invoice` | `openNewInvoice`, `openEditInvoice` | `saveInvoice` | `deleteClientInvoice` / `…FromModal` |
| `modal-co` | `openNewCO`, `openEditCO` | `saveCO` | `deleteCO` / `deleteCOFromModal` |
| `modal-po` | `openNewPO`, `openEditPO` | `savePO` | `deletePO` / `deletePOFromModal` |
| `modal-sov` | `openAddSOVItem`, `editSOVItem` | `saveSOVItem` | `deleteSOVItem` / `…FromModal` |
| `modal-lien` | `openNewLien`, `openEditLien` | `saveLien` | `deleteLien` |
| `modal-employee` | `openNewEmployee`, `openEditEmployee` | `saveEmployee` | `deleteEmployeeFromModal` |
| `modal-vendor` | `openNewVendor`, `openEditVendor` | `saveVendor` | `deleteVendorFromModal` |
| `modal-sub` | `openNewSub`, `editSub` | `saveSub` | `deleteSub` |
| `modal-assign-sub` | `openAssignSub` | `saveAssignSub` | — |
| `modal-check` | `openManualCheck`, `openEditCheck` | `onCheckModalSave` → `saveCheckEdit` / `saveAndPrintManualCheck` | `deleteCheck` |
| `modal-pay` | `openPayPurchase` | `savePayPurchase` | — |
| `modal-ar-pay` | `openARPayment` | `saveARPayment` | — |
| `modal-import` | `openImport` | `confirmImport` | — |
| `modal-import-pos` | `openImportPOs` | `confirmImportPOs` | — |
| `modal-generate-po` | `openGeneratePO` | (generates a doc) | — |
| `modal-st120` | `openST120Generator` | (generates a PDF) | — |
| `modal-job-picker` | `promptForJobThenOpen` | `confirmJobPicker` | — |
| `modal-inbox-pdf` | `viewInboxPdf` | read-only | — |

**Badges**: `.badge` + one of `b-paid` (green), `b-pending` (blue), `b-overdue` (red),
`b-partial` (amber), `b-active`, `b-complete`, `b-hold`, `b-notstarted`. Usually built inline as
`` `badge b-${status.toLowerCase().replace(' ','')}` ``.

**Quick-add** (`toggleQuickAdd`): `quickAddPO`→`openNewPO`, `quickAddInvoice`→`openNewPurchase`
(an AP bill, despite the label), `quickAddPayApp`→`openNewInvoice`, `quickAddCO`→`openNewCO`.
Only `quickAddPayApp` and `quickAddCO` fall back to `promptForJobThenOpen` → `modal-job-picker` →
`confirmJobPicker` when there's no active job and more than one project; `quickAddPO` and
`quickAddInvoice` always open their modal directly and let you pick the job (or Shop) inside it.

**Trash / soft delete**: `TRASH_TYPES` covers `projects, purchase_orders, invoices, purchases,
labor_entries`. `restoreItem` nulls `deleted_at`. `permanentDeleteItem` requires typing `DELETE`,
removes the attached file, and for `projects` cascades a hard delete across 13 child tables.

---

## 6. Imports

| Flow | Accepts | Creates |
|---|---|---|
| `openImport` → `handleImportFile` → `parseEstimate` → `parseResidentialEstimate` / `parseIndustrialEstimate` → `showImportPreview` → `confirmImport` | `.xlsx` only | `phases` rows (budget = hours × burden, or flat $) |
| `openImportPOs` → `parseImportPOs` → `confirmImportPOs` | `.xlsx`, `.xls`, `.csv` | `purchase_orders` rows; resolves `job_number` → `project_id` |
| `openSOVImport` | `.xlsx` only | **Replaces** all `sov_line_items` for the project (delete + insert, behind a confirm) |

`parseEstimate` branches: an `Estimate` sheet with no "Bid Breakdown" sheet → industrial; otherwise residential.

---

## 7. Invoice Inbox (Microsoft Graph)

Newest and most intricate subsystem. Reads vendor-invoice PDFs out of the accounting mailbox,
parses them, and queues them for one-click logging.

**Auth**: `ensureMSAL` → `getGraphToken` (`acquireTokenSilent`, falls back to `loginPopup`).
`primeMSAL` warms this up when the PO modal opens. `graphMessagesBase()` returns `/me/messages`
(or `/users/{sendFrom}/messages`). **No folder scoping** — it queries the whole mailbox filtered
only by `receivedDateTime`; `hasAttachments` is filtered client-side because Graph rejects
`$orderby` when it doesn't match the filter field.

**Scan** — `scanInvoiceInbox(incremental)`, guarded by `_inboxScanRunning`:

1. Loads **all POs across all companies** (not `withCompany`) into `state.allPOs` — the shared
   mailbox receives invoices for all three companies, so routing must see every PO number.
2. Captures `scanStartedAt` **before** listing, so mail arriving mid-scan is caught next time.
3. Incremental uses `app_settings.inbox_last_scan`; full scan uses the 60-day window.
4. **Dedupe key**: `graph_message_id + '|' + graph_attachment_id`, both as an in-memory `Set`
   and as the upsert `onConflict` target.
5. Per PDF attachment: fetch bytes → `extractTextFromPdfBytes` → `parseInvoiceText` → row,
   plus filename fallbacks for PO # and invoice #.
6. A resolved PO backfills `matched_po_id`, `matched_project_id`, `matched_cost_code`, vendor,
   and **`company_id`** — this is the cross-company auto-routing point.
7. Advances `inbox_last_scan`, re-renders.

**`invoice_inbox_queue` row**: `graph_message_id, graph_attachment_id, email_subject, email_from,
email_received_at, attachment_name, status, parsed_vendor, parsed_invoice_number, parsed_invoice_date,
parsed_amount_due, parsed_amount_paid, parsed_is_paid, parsed_payment_terms, parsed_po_number,
parsed_confidence, parsed_full, matched_po_id, matched_project_id, matched_cost_code, company_id,
error_note, confirmed_at`. **PDF bytes are never stored** — re-fetched from Graph on demand.

**Review**: `renderInboxQueueList` lists only `status='pending'`. `looksLikeStatement` badges likely
statements. `viewInboxPdf` / `editInboxRowSplit` show the PDF beside the form.
`findPossibleDuplicate` checks `purchases` on vendor+invoice#, else vendor+PO#+amount within $0.01 — **warns, doesn't block**.

**`confirmInboxRow(queueId, quick)`** — the important one:
1. If `row.company_id !== state.activeCompanyId`, **switches active company first**.
2. `quick` needs `matched_po_id + parsed_vendor + parsed_amount_due`, else downgrades to the form.
3. Duplicate found → force `quick=false` + `confirm()`.
4. Opens the **normal** `openNewPurchase` modal (no forked logic), prefills from `parsed_*`, applies
   known-vendor defaults, selects the PO and fires its `onchange`, tags `_inboxQueueId`, and loads
   the PDF into `_pendingFile` so `savePurchase`'s normal upload path attaches it.
5. **The queue write happens inside `savePurchase`** — it sets `status='confirmed'`, `confirmed_at`
   only after the `purchases` row saves. Nothing is written to the queue before that.

`fileInboxRowAsPO` attaches the PDF to `purchase_orders.pdf_url` instead and sets `status='filed_as_po'`
(no cost logged). `dismissInboxRow` sets `status='dismissed'`.

**Outlook drafts** (never sends): `createPODraft` POSTs a draft with a rendered PDF +
optional extra attachments; `poHtmlToPdfBase64` rasterizes HTML via html2pdf at scale 2;
`createDraftWithPdf` takes ready bytes; `emailFinishedPackage` uploads Joe's signed subcontract PDF
(grabs the token **before** the file picker — a file dialog consumes the click gesture MSAL needs; 3 MB guard).

---

## 8. PDF extraction & invoice parsing

`extractTextFromPdfBytes` tries the pdf.js text layer; if < 50 chars total it falls back to
per-page Tesseract OCR. Returns `{ text, usedOCR }`. `readInvoiceFile` (purchase modal) duplicates
this logic inline; `readPOQuoteFile` does the same for vendor quotes on a PO (only fills empty fields).

`parseInvoiceText(text, filename, knownPOs)` runs strategies in order, each writing through `upd()`,
which **only overwrites a field if the new confidence is higher**:

| Step | Sets | Heuristic |
|---|---|---|
| `step_detectVendor` | vendor | substring match vs `VENDOR_SIGNALS` (NIS, Nefco, Ideal Supply, Airweld +aliases, Cassone, United Rentals, Mayer Malbin, Core & Main, Shaw Supply, Mobile Steam, FW Webb) |
| `step_NISRules` | amount_due, invoice_number | **NIS only** — `AMOUNT DUE: $…` (last), `INVOICE {6-8 digits} ORDER NUMBER` |
| `step_IdealRules` | amount_due, invoice_date | **Ideal only** — `Amount Due: $…` (last), stacked date/number header |
| `step_AirweldRules` | date, invoice#, po#, amount | **Airweld only** — 3-cell header; PO # is the first 4 digits of "CUS P/O #" before "NET n" (they concatenate their own ref); total = tax-inclusive last currency |
| `step_labeledValues` | invoice#, date, amount | general labeled-field regexes, OCR-tolerant date labels |
| `step_POAnchored` | po_number, job_number, cost_code | anchored to "Customer Order Number"/"PO Number", format `NNNN-NNNN-NN[N]` |
| `step_POFuzzyMatch` | po_number | scans for any real PO from `knownPOs`, bare or as leading 4 digits of a longer run |
| `step_topOfPageDate` | invoice_date | fallback: first 200 chars → first 600 → any bare ISO date |
| `step_largestCurrency` | amount_due | safety net: largest `$n.nn` anywhere |
| `step_stackedLabels` | amount_due | Nefco-style `SUBTOTAL … AMOUNT DUE n1 n2 n3 n4` → last number |
| `step_paymentTerms` | payment_terms | NET 15/30/45/60, COD/CASH → 0, default 30 |
| `step_paymentReceipt` | is_paid, amount_paid | `PAYMENT RECEIPT` / `Amount Received` → mark paid |
| `step_vendorContact` | phone, email, address | for new-vendor prefill; excludes Tetra's own address/email and FAX lines |
| `step_salesTax` | sales_tax | conservative; feeds `maybeWarnTaxOnExemptJob` (non-blocking warning on tax-exempt jobs) |

Only **NIS, Ideal Supply, Airweld** get dedicated rules — the others just get name detection.

---

## 9. Generated documents

| Generator | Mechanism | Contents |
|---|---|---|
| `generatePayAppPDF` | print window | 4 pages: Billing Summary, **AIA G702**, **G703** continuation, Conditional Partial (or Final) Waiver |
| `printVoucherCheck` | print window | QuickBooks 3-part MICR voucher (3.5" face + two stubs) |
| `buildARInvoice` / `printARInvoice` / `emailARInvoice` | HTML → print or html2pdf→Graph draft | single-line invoice, retainage, payments, Net-n terms; email attaches the linked pay-app PDF too |
| `buildCustomerStatement` / `print…` / `email…` / `emailCustomerPackage` | same | aging table + open items; the "package" bundles the statement + one PDF per open invoice |
| `generateInboundWaiver` | print window | Conditional Partial/Final waiver a sub owes Tetra |
| `generateST120` / `buildST120Bytes` | **pdf-lib** | fills `ST120_BLANK_B64` form fields, embeds `ST120_SIG_B64` on p.2, flattens, downloads |
| `generateSubcontractPackage` | **docx 9.0.3** | PO cover + Master Subcontract Agreement (blanks highlighted) + Exhibit A Work Order + Addendum + Insurance Request → `.docx` for Joe to edit, PDF, then `emailFinishedPackage` |
| `generatePODocument(mode)` | print window or Graph draft | two templates by `docType`: material ordering form vs formal equipment/subcontract contract; attaches ST-120.1 on tax-exempt jobs |
| `exportBondingWIP` | **SheetJS** | WIP schedule .xlsx with number formats/merges |
| `exportAPAgingCSV` | plain Blob | AP aging rows per current filters |

**Technique summary** — print-window for anything Joe prints; html2pdf only when Graph needs real
bytes; pdf-lib only for ST-120.1; docx only for the subcontract package; SheetJS for WIP.

**Pay app math**: per line `thisAmt = scheduled_value * thisPct/100` (the stored `*_pct` columns
are that fraction, not the whole number shown in the UI);
`retainageAmt = totalThis * retPct/100`; `netPaymentDue = totalThis - retainageAmt`;
`totalComplete = prevBilled + totalThis`; `balance = contract - totalComplete`.
`prevBilled`/`prevRetainage` carry forward from the prior pay app's stored totals.
`retPct` defaults from `project.retainage_pct` (fallback 5), editable per app.

**Checks**: `nextCheckNumber` = max `check_number` ever used for that company (including voided,
so numbers are never reused) + 1, else 1001. The manual-check modal's **Payee Address** box is
*not* stored on the `checks` row — on save, `persistPayeeAddress` writes it to the **`vendors`**
roster instead (fills a blank address silently; confirms before replacing a different one;
creates the vendor if the payee is unknown). `openManualCheck` wires `chk-payee`'s `onblur` to
pull a known payee's address back out, so it round-trips. `printVendorCheck` (check written from
an invoice) never uses that box — it reads `vendors.address` directly. `voidCheck` keeps the number; `deleteCheck` only works
on already-voided checks and frees the number. Alignment nudges persist to **`localStorage`** under
`checkAlign_{companyId}` — per browser, not in Supabase.

---

## 10. Gotchas & known rough edges

1. ~~**`vendors` has no `company_id`, but two queries filter it by one.**~~ **FIXED 2026-08-31.**
   `printVendorCheck` and `reprintCheck` wrapped their address lookup in `withCompany(...)`;
   since vendor rows are never inserted with a `company_id`, that matched nothing whenever a
   company was active and **the payee address printed blank on every check**. Both now query
   `vendors` unfiltered and match with `ilike` instead of `eq` (a casing difference between
   `purchases.vendor` and `vendors.name` caused the same blank-address symptom). Comments at
   both sites warn against re-adding `withCompany`. **The rule: never company-filter `vendors`,
   `subcontractors`, `employees`, or `cost_codes` — they are global rosters (§2).**
2. **`companyDocIdentity()` falls back to Tetra Mechanical for every field.** An incomplete
   Tetra Fire or JDM company row renders Tetra Mechanical letterhead with no warning.
3. **Pay-app prior-period linkage is by `description` text match**, not by ID
   (`prevMap[li.description] = li`). Renaming an SOV line loses its prior-billed history.
4. **`openSOVImport` is destructive** — it deletes every existing `sov_line_items` row for the
   project before inserting. Only a `confirm()` stands between a mis-click and a wiped SOV.
5. **The bid-breakdown importer matches `/tetra/i`** to tell self-perform rows from sub rows
   (~lines 6880, 6910). A JDM-branded estimate sheet would mis-classify its own self-perform rows.
   Not a tenancy leak, but a correctness bug if that importer is used for JDM.
6. **`master-inbox` sidebar button is missing its closing `</button>`** in the markup.
7. **`quickAddInvoice` opens `openNewPurchase`** (an AP bill) and **`quickAddPayApp` opens
   `openNewInvoice`** — the menu labels don't match the functions. Working as built, confusing to read.
8. **Adding a view needs three edits**: `render()`, `updateBreadcrumb()`, and the sidebar markup.
9. `confirm()` / `prompt()` / `alert()` are used for destructive confirmations throughout —
   fine in the browser, but they block if anything ever automates this page.
10. Check alignment lives in `localStorage`, so it's lost on a new browser or machine.
11. **AR payment dates are only stored inside `notes` strings.** `invoices` has no
    `payment_date` column — writes to it were removed on 2026-07-20 (commit `8fadf65`)
    and replaced with an appended note, e.g.
    `notes: 'Pay Application #7 [Received 12500.00 on 2026-07-18]'`, and in
    `saveARPayment`/`savePayPurchase` via the `noteLine` pattern
    `[Received 1234.00 on 2026-07-18 via Check ref 1042]`. Consequence: **you cannot
    query, sort, or report on when a payment was received** — it's unparsed text.
    If payment-date reporting is ever wanted, that's a new `payment_date` column plus
    a migration, not a code change. (The pre-fix copy of the app survives in the repo
    as `Index.html`, capital I — dead file, safe to delete.)

---

## 11. Deferred — do not build unless Joe asks

Parked pending a real first user/hire:

- **Field portal** — mobile time entry / photos for crews
- **Role-based access** — everything today runs as a single Supabase auth user
- **Onboarding** — new-company / new-user setup flow

---

## 12. Changelog

<!-- newest first; one block per code-changing session -->

### 2026-08-31 — SECURITY: storage bucket was world-readable
Audited the live project using only the publishable key that ships inside
`index.html`. **Every database table correctly refused anonymous reads and inserts**
(`42501` row-level-security violations). **Storage did not.** An anonymous request
could list the bucket root (`2600-Patterson_Houses`, `2601-Edenwald`,
`2602-Good_Samaritan_Hospital`, `_shop`), walk into `contracts/`,
`purchase_orders/`, `invoices/`, and download files — a `HEAD` on one contract
returned `200` with `content-length: 1029997`. Everything the app files away
(signed contracts, vendor invoices, pay apps, lien waivers, ST-120.1s) was
downloadable by anyone. Fix written as `migrations/2026-08-31_lock_down_storage.sql`:
diagnose existing `storage.objects` policies, set the bucket private, drop the
permissive policy, add `authenticated`-only select/insert/update/delete.
**Making the repo private does not help** — the key is served to every visitor of
the live site; policies are the control, not secrecy. Also found **public signup is
enabled** (`disable_signup: false`), so anyone can create an account; whether that
grants data access depends on whether the table policies say `authenticated`
broadly. **Closed 2026-09-01** — `disable_signup: true`, verified from outside the
app against `/auth/v1/settings`. Email stays enabled as a provider (that is Joe's own
login); what is off is self-service account creation. New users are added by hand
under Authentication → Users. *No app code changed by this entry.*

### 2026-08-31 — payment_date restored as a real column
AR payment dates lived only inside `notes` strings, so they couldn't be queried,
sorted, or charted (the §10.11 gap). Added `payment_date` to `invoices` and
`pay_applications` via `migrations/2026-08-31_add_payment_date.sql`, which also
backfills from the existing `[Received … on YYYY-MM-DD …]` and `Paid: $… on …`
note formats and reports how many rows it recovered. Code now writes it at all
five payment sites: both branches of `saveARPayment`, the mirrored `PAY-APP-`
invoice row in each, and `markPayAppPaid`'s pay-app stamp. The notes line is
unchanged, so nothing that reads notes breaks. New helper
`saveTolerantOfMissingColumn(run, row, col)` wraps each write: on `42703` /
`PGRST204` it drops the column and retries once with a console warning, so
**deploy order doesn't matter** — this is deliberate, because the original
2026-07-20 incident was exactly this write failing and the field being deleted
from the code instead of added to the schema. Any *other* database error still
surfaces normally rather than being retried. `node --check` clean; the helper's
five branches unit-tested in isolation.

**Migration run 2026-09-01.** Backfill recovered 1 of 4 paid invoices; the other
three (`1001`, `657`, `649-1`) have `notes = NULL` — they were marked Paid before
the app recorded dates at all, so nothing exists to parse. Left null pending manual
entry from bank records. `pay_applications` had one row, unpaid, nothing to recover.
Reporting is complete from 2026-09-01 forward.

### 2026-08-31 — Payee address typed on a check now persists
The **Payee Address** box on the Write-a-Check modal (`chk-payee-addr`) was read by
`saveAndPrintManualCheck`, handed to `printVoucherCheck`, and then discarded — it was never
written to any table, so a typed address vanished after one printout and the box came back
empty every time. Added `persistPayeeAddress(payee, address)` (~just above `openManualCheck`),
called after the `checks` row saves: matches the payee against `vendors` by `ilike`, fills a
blank `address` silently, `confirm()`s before replacing a different one, and inserts a new
vendor row (`approved/active`, Net 30) when the payee isn't on the roster — same auto-add
behaviour `savePurchase` already has for invoices. Refreshes `state.vendors` after. Also wired
`chk-payee` `onblur` in `openManualCheck` to pull a known payee's address back into the box
(fills only when blank, never overwrites typing). Every failure path is non-fatal — a vendor
write can never block recording or printing a check. No SQL: `vendors.address` already exists
(verified against the live PostgREST schema). ~45 lines; `node --check` clean; the helper's six
branches unit-tested in isolation.

### 2026-08-31 — Fix blank payee address on printed checks
`printVendorCheck` (~9886) and `reprintCheck` (~10103) looked up the vendor address with
`withCompany(db.from('vendors').select('address').eq('name', pu.vendor))`. `vendors` is a
global roster with no `company_id`, so that filter matched nothing and every check printed
with an empty address block — the #10 double-window envelope showed blank. Dropped
`withCompany` at both sites and switched `eq` → `ilike` so a casing difference between
`purchases.vendor` and `vendors.name` can't reproduce the same symptom. Added comments at
both sites so the filter isn't re-added. No SQL, no schema change. 2 code lines + 5 comment
lines; `node --check` clean. Closes §10.1.

### 2026-08-31 — CLAUDE.md regenerated; repo duplicate resolved
No code changes. Rebuilt this map from `index.html` @ 12,381 lines after the previous CLAUDE.md
went missing from project knowledge. Documented the data model, company scoping, all 18 views and
12 project modules, the Graph invoice-inbox pipeline, the invoice parser strategy chain, and the
document generators. Logged 10 gotchas in §10 — the vendor-address-on-checks bug (§10.1) is a real
defect that was found while mapping, not yet fixed.

Also diffed the repo's two index files. `Index.html` (capital I, 12,384 lines, commit
`5e3888d`, 19:01 Jul 20) differs from the live `index.html` (12,381 lines, `8fadf65`,
19:23 Jul 20) by exactly 4 lines — the capital copy still writes a `payment_date`
column that doesn't exist. It is the older, pre-fix upload; safe to delete. Recorded
the `payment_date` finding as §10.11.
