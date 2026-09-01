-- ============================================================================
-- 2026-08-31  SECURITY: lock down the tetra-files storage bucket
-- ============================================================================
-- WHY THIS EXISTS
--
-- Verified on 2026-08-31 against the live project, using ONLY the publishable
-- key that is embedded in index.html (and therefore public to anyone who
-- visits the app or reads the GitHub repo):
--
--   * Every DATABASE table correctly refused anonymous reads and inserts.
--     (insert attempts returned 42501 "new row violates row-level security".)
--
--   * STORAGE did not. An anonymous request could:
--       - list the bucket root:  2600-Patterson_Houses, 2601-Edenwald,
--                                2602-Good_Samaritan_Hospital, _shop
--       - walk into subfolders:  contracts/, purchase_orders/, invoices/ ...
--       - and DOWNLOAD a file:   GET /storage/v1/object/tetra-files/<path>
--                                returned 200 with a 1,029,997-byte contract.
--
-- So the database is locked and the filing cabinet is open. Everything the app
-- stores as a file -- signed contracts, vendor invoices, pay applications, lien
-- waivers, ST-120.1 certificates -- is currently downloadable by anyone.
--
-- IMPORTANT: making the GitHub repo private does NOT fix this. The key is
-- served inside index.html to every visitor of the live site. The fix is the
-- policies below, not secrecy.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- STEP 1 (diagnostic) -- run this FIRST and read the output.
-- It shows which policies currently exist on storage. You are looking for any
-- policy whose "roles" includes anon / public, or whose USING clause is `true`.
-- ---------------------------------------------------------------------------
select policyname, roles, cmd, qual, with_check
from   pg_policies
where  schemaname = 'storage' and tablename = 'objects'
order  by policyname;

-- Also confirm whether the bucket itself is flagged public:
select id, name, public from storage.buckets where id = 'tetra-files';


-- ---------------------------------------------------------------------------
-- STEP 2 -- make the bucket private.
-- A public bucket serves /object/public/... to the world with no key at all.
-- ---------------------------------------------------------------------------
update storage.buckets set public = false where id = 'tetra-files';


-- ---------------------------------------------------------------------------
-- STEP 3 -- drop the over-permissive policies STEP 1 revealed.
--
-- Uncomment and edit to match the exact policy names STEP 1 printed. Supabase's
-- default quick-start policies are usually named something like the examples
-- below. DO NOT run these blindly -- use the real names from STEP 1.
-- ---------------------------------------------------------------------------
-- drop policy if exists "Enable read access for all users"  on storage.objects;
-- drop policy if exists "Public Access"                     on storage.objects;
-- drop policy if exists "Give anon users access to tetra-files" on storage.objects;


-- ---------------------------------------------------------------------------
-- STEP 4 -- allow signed-in users only.
--
-- The app runs as a single authenticated Supabase user, so "authenticated" is
-- the right scope. Anonymous visitors get nothing; the app keeps working
-- unchanged because it only touches storage after login.
-- ---------------------------------------------------------------------------
alter table storage.objects enable row level security;

create policy "tetra_files_auth_select"
  on storage.objects for select to authenticated
  using (bucket_id = 'tetra-files');

create policy "tetra_files_auth_insert"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'tetra-files');

create policy "tetra_files_auth_update"
  on storage.objects for update to authenticated
  using (bucket_id = 'tetra-files')
  with check (bucket_id = 'tetra-files');

create policy "tetra_files_auth_delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'tetra-files');


-- ---------------------------------------------------------------------------
-- STEP 5 -- verify the hole is closed.
--
-- Run this in a terminal, or paste the URL in a private browser window.
-- BEFORE the fix it returned 200 and the file. AFTER, it must return 400/403.
--
--   curl -s -o /dev/null -w '%{http_code}\n' \
--     -H "apikey: <the publishable key from index.html>" \
--     "https://mvwsmywudyvxfunyqkxt.supabase.co/storage/v1/object/tetra-files/2600-Patterson_Houses/contracts/Contract_1779288422660.pdf"
--
-- Then sign in to the app and open a stored PDF from a job to confirm the app
-- itself still works. Signed URLs (getFileURL) are unaffected by these policies.
-- ---------------------------------------------------------------------------
