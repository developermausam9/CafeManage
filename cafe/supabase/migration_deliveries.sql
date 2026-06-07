-- Create deliveries table
CREATE TABLE IF NOT EXISTS public.deliveries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES public.cafes(id) ON DELETE CASCADE,
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    customer_name TEXT NOT NULL,
    customer_phone TEXT NOT NULL,
    delivery_address TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'preparing', 'out_for_delivery', 'delivered', 'cancelled'
    driver_name TEXT,
    driver_phone TEXT,
    delivery_charge NUMERIC(10,2) DEFAULT 50.00,
    grand_total NUMERIC(10,2) NOT NULL DEFAULT 0,
    payment_method TEXT DEFAULT 'cash', -- 'cash', 'qr', 'card'
    payment_status TEXT DEFAULT 'pending', -- 'pending', 'paid'
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.deliveries ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "deliveries isolate" ON public.deliveries;
DROP POLICY IF EXISTS "Allow all actions for deliveries for authenticated users" ON public.deliveries;
DROP POLICY IF EXISTS "Allow public insert access to deliveries" ON public.deliveries;
DROP POLICY IF EXISTS "Allow public read access to deliveries" ON public.deliveries;
DROP POLICY IF EXISTS "Allow public update access to deliveries" ON public.deliveries;

-- Create RLS Policies
CREATE POLICY "Allow all actions for deliveries for authenticated users" 
ON public.deliveries FOR ALL TO authenticated 
USING (cafe_id = get_user_cafe_id()) 
WITH CHECK (cafe_id = get_user_cafe_id());

CREATE POLICY "Allow public insert access to deliveries" 
ON public.deliveries FOR INSERT TO anon 
WITH CHECK (true);

CREATE POLICY "Allow public read access to deliveries" 
ON public.deliveries FOR SELECT TO anon 
USING (true);

CREATE POLICY "Allow public update access to deliveries" 
ON public.deliveries FOR UPDATE TO anon 
USING (true);

-- Create Indexes
CREATE INDEX IF NOT EXISTS idx_deliveries_status ON public.deliveries(status);
CREATE INDEX IF NOT EXISTS idx_deliveries_cafe_id ON public.deliveries(cafe_id);
