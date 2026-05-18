-- ============================================================
-- TETRA MECHANICAL SERVICES — COMPLETE DATABASE SCHEMA
-- Run this once on a fresh Supabase project
-- All tables, columns, indexes, and RLS policies included
-- ============================================================

-- COMPANIES
CREATE TABLE IF NOT EXISTS companies (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  short_name TEXT,
  address TEXT,
  city TEXT,
  state TEXT,
  zip TEXT,
  phone TEXT,
  email TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PROJECTS
CREATE TABLE IF NOT EXISTS projects (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID REFERENCES companies(id),
  job_number TEXT NOT NULL,
  job_name TEXT NOT NULL,
  client TEXT,
  status TEXT DEFAULT 'Active',
  date_started DATE,
  base_contract NUMERIC(12,2) DEFAULT 0,
  approved_cos NUMERIC(12,2) DEFAULT 0,
  retainage_pct NUMERIC(5,2) DEFAULT 5,
  payment_terms INT DEFAULT 30,
  burden_rate NUMERIC(8,2) DEFAULT 160,
  gc_name TEXT,
  gc_address TEXT,
  gc_city TEXT,
  gc_state TEXT,
  gc_zip TEXT,
  gc_contact TEXT,
  owner_name TEXT,
  architect TEXT,
  contract_date DATE,
  contract_for TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- COST CODES
CREATE TABLE IF NOT EXISTS cost_codes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  description TEXT,
  category TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- VENDORS
CREATE TABLE IF NOT EXISTS vendors (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT,
  payment_terms INT DEFAULT 30,
  credit_limit NUMERIC(12,2),
  account_number TEXT,
  approved BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- EMPLOYEES
CREATE TABLE IF NOT EXISTS employees (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  role TEXT,
  st_rate NUMERIC(8,2) DEFAULT 0,
  address TEXT,
  city TEXT,
  state TEXT,
  zip TEXT,
  effective_date DATE,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- EMPLOYEE COMPANIES (shared across companies)
CREATE TABLE IF NOT EXISTS employee_companies (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  employee_id UUID REFERENCES employees(id),
  company_id UUID REFERENCES companies(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PROJECT BUDGETS (category level: Labor, Materials, Subs, Equipment)
CREATE TABLE IF NOT EXISTS project_budgets (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  budgeted_amount NUMERIC(12,2) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(project_id, category)
);

-- COST LINE ITEMS (Tooling, Bond, Contingency, Design)
CREATE TABLE IF NOT EXISTS cost_line_items (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  item_name TEXT NOT NULL,
  budgeted_amount NUMERIC(12,2) DEFAULT 0,
  actual_amount NUMERIC(12,2) DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PHASES
CREATE TABLE IF NOT EXISTS phases (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  phase_name TEXT NOT NULL,
  status TEXT DEFAULT 'Not Started',
  budgeted_hours NUMERIC(8,2) DEFAULT 0,
  phase_budget NUMERIC(12,2) DEFAULT 0,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PURCHASE ORDERS
CREATE TABLE IF NOT EXISTS purchase_orders (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  company_id UUID REFERENCES companies(id),
  po_number TEXT NOT NULL,
  vendor TEXT,
  description TEXT,
  cost_code TEXT,
  committed_amount NUMERIC(12,2) DEFAULT 0,
  invoiced_amount NUMERIC(12,2) DEFAULT 0,
  paid_amount NUMERIC(12,2) DEFAULT 0,
  issue_date DATE,
  expected_date DATE,
  status TEXT DEFAULT 'Open',
  invoice_number TEXT,
  phase_id UUID REFERENCES phases(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PURCHASES (invoices received / AP)
CREATE TABLE IF NOT EXISTS purchases (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  phase_id UUID REFERENCES phases(id) ON DELETE SET NULL,
  po_id UUID REFERENCES purchase_orders(id) ON DELETE SET NULL,
  vendor TEXT,
  invoice_number TEXT,
  invoice_date DATE,
  po_number TEXT,
  cost_code TEXT,
  category TEXT,
  po_amount NUMERIC(12,2) DEFAULT 0,
  paid_amount NUMERIC(12,2) DEFAULT 0,
  terms_days INT DEFAULT 30,
  status TEXT DEFAULT 'Pending',
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- LABOR ENTRIES
CREATE TABLE IF NOT EXISTS labor_entries (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  phase_id UUID REFERENCES phases(id) ON DELETE SET NULL,
  employee_id UUID REFERENCES employees(id),
  employee_name TEXT,
  role TEXT,
  week_ending DATE,
  st_hours NUMERIC(6,2) DEFAULT 0,
  ot15_hours NUMERIC(6,2) DEFAULT 0,
  ot2_hours NUMERIC(6,2) DEFAULT 0,
  st_rate NUMERIC(8,2) DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- CHANGE ORDERS
CREATE TABLE IF NOT EXISTS change_orders (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  co_number TEXT,
  description TEXT,
  amount NUMERIC(12,2) DEFAULT 0,
  co_type TEXT DEFAULT 'Addition',
  status TEXT DEFAULT 'Pending',
  submitted_date DATE,
  approved_date DATE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- INVOICES (AR — billing to clients)
CREATE TABLE IF NOT EXISTS invoices (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  invoice_number TEXT,
  invoice_date DATE,
  billed_amount NUMERIC(12,2) DEFAULT 0,
  paid_amount NUMERIC(12,2) DEFAULT 0,
  retainage_pct NUMERIC(5,2) DEFAULT 0,
  payment_date DATE,
  terms_days INT DEFAULT 30,
  status TEXT DEFAULT 'Pending',
  description TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- SOV LINE ITEMS (Schedule of Values per job)
CREATE TABLE IF NOT EXISTS sov_line_items (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  item_number TEXT,
  description TEXT NOT NULL,
  scheduled_value NUMERIC(12,2) DEFAULT 0,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PAY APPLICATIONS
CREATE TABLE IF NOT EXISTS pay_applications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  app_number INT NOT NULL,
  period_ending DATE,
  submitted_date DATE,
  payment_terms INT DEFAULT 30,
  retainage_pct NUMERIC(5,2) DEFAULT 5,
  status TEXT DEFAULT 'Draft',
  total_scheduled_value NUMERIC(12,2) DEFAULT 0,
  previous_billed NUMERIC(12,2) DEFAULT 0,
  current_billed NUMERIC(12,2) DEFAULT 0,
  total_completed NUMERIC(12,2) DEFAULT 0,
  retainage_amount NUMERIC(12,2) DEFAULT 0,
  net_payment_due NUMERIC(12,2) DEFAULT 0,
  balance_to_finish NUMERIC(12,2) DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PAY APPLICATION LINE ITEMS
CREATE TABLE IF NOT EXISTS pay_app_line_items (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pay_app_id UUID REFERENCES pay_applications(id) ON DELETE CASCADE,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  item_number INT,
  description TEXT,
  scheduled_value NUMERIC(12,2) DEFAULT 0,
  previous_pct NUMERIC(6,4) DEFAULT 0,
  previous_amount NUMERIC(12,2) DEFAULT 0,
  current_pct NUMERIC(6,4) DEFAULT 0,
  current_amount NUMERIC(12,2) DEFAULT 0,
  total_completed NUMERIC(12,2) DEFAULT 0,
  total_pct NUMERIC(6,4) DEFAULT 0,
  balance_to_finish NUMERIC(12,2) DEFAULT 0,
  retainage NUMERIC(12,2) DEFAULT 0,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- SUBCONTRACTORS
CREATE TABLE IF NOT EXISTS subcontractors (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  trade TEXT,
  contact_name TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  coi_expiry DATE,
  w9_on_file BOOLEAN DEFAULT false,
  approved BOOLEAN DEFAULT true,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PROJECT SUBS (subcontractors assigned to projects)
CREATE TABLE IF NOT EXISTS project_subs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  subcontractor_id UUID REFERENCES subcontractors(id),
  contract_amount NUMERIC(12,2) DEFAULT 0,
  paid_to_date NUMERIC(12,2) DEFAULT 0,
  status TEXT DEFAULT 'Active',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- LIEN WAIVERS
CREATE TABLE IF NOT EXISTS lien_waivers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  subcontractor_id UUID REFERENCES subcontractors(id),
  pay_app_id UUID REFERENCES pay_applications(id),
  waiver_type TEXT DEFAULT 'Conditional Partial',
  amount NUMERIC(12,2) DEFAULT 0,
  through_date DATE,
  received_date DATE,
  status TEXT DEFAULT 'Pending',
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PO SEQUENCES (auto-numbering)
CREATE TABLE IF NOT EXISTS po_sequences (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID REFERENCES companies(id),
  project_id UUID REFERENCES projects(id),
  last_sequence INT DEFAULT 2019,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- INTERCOMPANY TRANSACTIONS
CREATE TABLE IF NOT EXISTS intercompany_transactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  from_company_id UUID REFERENCES companies(id),
  to_company_id UUID REFERENCES companies(id),
  project_id UUID REFERENCES projects(id),
  amount NUMERIC(12,2) DEFAULT 0,
  description TEXT,
  transaction_date DATE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- EMAIL INBOX LOG
CREATE TABLE IF NOT EXISTS email_inbox_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id TEXT,
  sender TEXT,
  subject TEXT,
  received_at TIMESTAMPTZ,
  classified_as TEXT,
  linked_po_id UUID REFERENCES purchase_orders(id),
  linked_project_id UUID REFERENCES projects(id),
  processed BOOLEAN DEFAULT false,
  raw_data JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- ROW LEVEL SECURITY — allow all (single tenant app)
-- ============================================================
DO $$ 
DECLARE t TEXT;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'companies','projects','cost_codes','vendors','employees',
    'employee_companies','project_budgets','cost_line_items','phases',
    'purchase_orders','purchases','labor_entries','change_orders',
    'invoices','sov_line_items','pay_applications','pay_app_line_items',
    'subcontractors','project_subs','lien_waivers','po_sequences',
    'intercompany_transactions','email_inbox_log'
  ]) LOOP
    EXECUTE 'ALTER TABLE '||t||' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS allow_all ON '||t;
    EXECUTE 'CREATE POLICY allow_all ON '||t||' FOR ALL USING (true) WITH CHECK (true)';
  END LOOP;
END $$;

-- ============================================================
-- MISSING COLUMNS (safe to run on existing database)
-- ============================================================
ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS invoice_number TEXT;
ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS invoiced_amount NUMERIC(12,2) DEFAULT 0;
ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES companies(id);
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS po_id UUID REFERENCES purchase_orders(id);
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS cost_code TEXT;
ALTER TABLE purchases ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS payment_terms INT DEFAULT 30;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS retainage_pct NUMERIC(5,2) DEFAULT 5;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS gc_name TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS gc_address TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS gc_city TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS gc_state TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS gc_zip TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS gc_contact TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS owner_name TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS architect TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS contract_date DATE;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS contract_for TEXT;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES companies(id);
ALTER TABLE projects ADD COLUMN IF NOT EXISTS approved_cos NUMERIC(12,2) DEFAULT 0;
ALTER TABLE pay_applications ADD COLUMN IF NOT EXISTS submitted_date DATE;
ALTER TABLE pay_applications ADD COLUMN IF NOT EXISTS payment_terms INT DEFAULT 30;
ALTER TABLE pay_applications ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE phases ADD COLUMN IF NOT EXISTS phase_budget NUMERIC(12,2) DEFAULT 0;

SELECT 'Schema complete — all tables and columns ready' as status;
