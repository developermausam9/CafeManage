-- supabase_operations_schema.sql
-- Run this in your Supabase SQL Editor

-- 1. Suppliers Table
CREATE TABLE public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES public.cafes(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    company TEXT,
    total_payable NUMERIC DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Purchase Invoices Table
CREATE TABLE public.purchase_invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES public.cafes(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    product_id UUID REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL,
    purchase_price NUMERIC NOT NULL,
    total_cost NUMERIC NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Expenses Table
CREATE TABLE public.expenses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES public.cafes(id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    amount NUMERIC NOT NULL,
    description TEXT,
    date TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Customer Dues Table
CREATE TABLE public.customer_dues (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES public.cafes(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    total_due NUMERIC DEFAULT 0.0,
    last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Due Payments Table (for tracking individual payments)
CREATE TABLE public.due_payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES public.cafes(id) ON DELETE CASCADE,
    due_id UUID REFERENCES public.customer_dues(id) ON DELETE CASCADE,
    amount_paid NUMERIC NOT NULL,
    payment_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. Inventory Movements Table (optional but requested for audit trails)
CREATE TABLE public.inventory_movements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES public.cafes(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id) ON DELETE CASCADE,
    movement_type TEXT NOT NULL, -- 'in' (purchase), 'out' (sale), 'adjustment'
    quantity INTEGER NOT NULL,
    reference_id UUID, -- order_id or purchase_invoice_id
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ENABLE ROW LEVEL SECURITY (RLS)
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_dues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.due_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;

-- CREATE RLS POLICIES
-- Policy: Restrict access by cafe_id for authenticated users (Staff)

-- Suppliers
CREATE POLICY "Users can view suppliers for their cafe" 
ON public.suppliers FOR SELECT USING (cafe_id IN (SELECT cafe_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Owners and Admins can insert suppliers" 
ON public.suppliers FOR INSERT WITH CHECK (cafe_id IN (SELECT cafe_id FROM public.profiles WHERE id = auth.uid() AND role IN ('owner', 'admin')));

CREATE POLICY "Owners and Admins can update suppliers" 
ON public.suppliers FOR UPDATE USING (cafe_id IN (SELECT cafe_id FROM public.profiles WHERE id = auth.uid() AND role IN ('owner', 'admin')));

-- Purchase Invoices
CREATE POLICY "Users can view purchase invoices for their cafe" 
ON public.purchase_invoices FOR SELECT USING (cafe_id IN (SELECT cafe_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Owners and Admins can insert purchase invoices" 
ON public.purchase_invoices FOR INSERT WITH CHECK (cafe_id IN (SELECT cafe_id FROM public.profiles WHERE id = auth.uid() AND role IN ('owner', 'admin')));

-- Expenses
CREATE POLICY "Users can view expenses for their cafe" 
ON public.expenses FOR SELECT USING (cafe_id IN (SELECT cafe_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Owners and Admins can insert expenses" 
ON public.expenses FOR INSERT WITH CHECK (cafe_id IN (SELECT cafe_id FROM public.profiles WHERE id = auth.uid() AND role IN ('owner', 'admin')));

-- Customer Dues
CREATE POLICY "Cashiers and Admins can access customer dues" 
ON public.customer_dues FOR ALL USING (cafe_id IN (SELECT cafe_id FROM public.profiles WHERE id = auth.uid() AND role IN ('owner', 'admin', 'cashier')));

-- Due Payments
CREATE POLICY "Cashiers and Admins can insert due payments" 
ON public.due_payments FOR ALL USING (cafe_id IN (SELECT cafe_id FROM public.profiles WHERE id = auth.uid() AND role IN ('owner', 'admin', 'cashier')));

-- Inventory Movements
CREATE POLICY "All staff can insert inventory movements (sales)" 
ON public.inventory_movements FOR INSERT WITH CHECK (cafe_id IN (SELECT cafe_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "All staff can view inventory movements" 
ON public.inventory_movements FOR SELECT USING (cafe_id IN (SELECT cafe_id FROM public.profiles WHERE id = auth.uid()));
