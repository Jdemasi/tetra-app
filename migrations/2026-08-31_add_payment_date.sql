-- ============================================================================
-- 2026-08-31  Add payment_date to invoices and pay_applications
-- ============================================================================
-- WHY
--
-- When money comes in, the app records the date only inside a notes string:
--     invoices.notes        -> "... [Received 12500.00 on 2026-07-18 via Check ref 1042]"
--     pay_applications.notes-> "... [Received 12500.00 on 2026-07-18 via ACH]"
--
-- That is readable but not queryable, so there is no way to ask "what came in
-- last month" or chart cash receipts. This adds a real date column.
--
-- HISTORY -- read before assuming this is new work. On 2026-07-20 the app DID
-- write payment_date, the column did not exist, the writes failed, and someone
-- removed the field (commit 8fadf65) rather than adding the column. This
-- migration is the other half of that fix. Running it makes those writes valid.
--
-- ORDER OF OPERATIONS
--   1. Run this migration.
--   2. Then deploy the matching index.html.
-- Deploying the code first is safe (it degrades and logs a console warning),
-- but running the SQL first is cleaner.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- STEP 1 -- add the columns. Nullable: historic rows genuinely have no date.
-- ---------------------------------------------------------------------------
alter table public.invoices          add column if not exists payment_date date;
alter table public.pay_applications  add column if not exists payment_date date;


-- ---------------------------------------------------------------------------
-- STEP 2 -- backfill from the notes text written since July.
--
-- Matches the "on YYYY-MM-DD" inside the "[Received ... on <date> ...]" note.
-- Only touches rows that are still null and whose note actually parses, so it
-- is safe to re-run. Rows with several receipts take the LAST date mentioned,
-- which is the most recent payment.
-- ---------------------------------------------------------------------------
update public.invoices
set    payment_date = (
         select (regexp_matches(notes, 'on (\d{4}-\d{2}-\d{2})', 'g'))[1]::date
         order  by 1 desc limit 1)
where  payment_date is null
  and  notes ~ 'Received .* on \d{4}-\d{2}-\d{2}';

update public.pay_applications
set    payment_date = (
         select (regexp_matches(notes, 'on (\d{4}-\d{2}-\d{2})', 'g'))[1]::date
         order  by 1 desc limit 1)
where  payment_date is null
  and  notes ~ 'Received .* on \d{4}-\d{2}-\d{2}';

-- Older pay apps used a different wording: "Paid: $1234.00 on 2026-07-18"
update public.pay_applications
set    payment_date = (regexp_match(notes, 'Paid: \$?[\d,.]+ on (\d{4}-\d{2}-\d{2})'))[1]::date
where  payment_date is null
  and  notes ~ 'Paid: \$?[\d,.]+ on \d{4}-\d{2}-\d{2}';


-- ---------------------------------------------------------------------------
-- STEP 3 -- check what the backfill recovered before you rely on it.
-- ---------------------------------------------------------------------------
select 'invoices' as tbl,
       count(*)                                        as total,
       count(payment_date)                             as with_date,
       count(*) filter (where paid_amount > 0
                          and payment_date is null)    as paid_but_no_date
from   public.invoices where deleted_at is null
union all
select 'pay_applications',
       count(*), count(payment_date),
       count(*) filter (where paid_amount > 0 and payment_date is null)
from   public.pay_applications;

-- Anything left in paid_but_no_date was paid before the notes convention
-- existed. Fill those by hand if the history matters; otherwise leave them --
-- reporting from here forward will be complete either way.
