-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Custom Types
CREATE TYPE user_role AS ENUM ('owner', 'admin', 'cashier', 'waiter', 'kitchen');
CREATE TYPE order_type AS ENUM ('dine_in', 'takeaway', 'delivery');
CREATE TYPE order_status AS ENUM ('pending', 'kitchen', 'completed', 'cancelled');
CREATE TYPE payment_method AS ENUM ('cash', 'qr', 'card', 'due', 'mixed');
CREATE TYPE stock_action AS ENUM ('in', 'out', 'adjustment');

-- Tables

CREATE TABLE cafes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    pan_vat_number TEXT,
    phone TEXT,
    address TEXT,
    logo_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    cafe_id UUID REFERENCES cafes(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role user_role NOT NULL,
    phone TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES cafes(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES cafes(id) ON DELETE CASCADE NOT NULL,
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    cost_price NUMERIC(10,2) DEFAULT 0,
    stock_quantity INTEGER DEFAULT 0,
    is_available BOOLEAN DEFAULT TRUE,
    image_url TEXT,
    is_stock_tracked BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE inventory_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES cafes(id) ON DELETE CASCADE NOT NULL,
    product_id UUID REFERENCES products(id) ON DELETE CASCADE NOT NULL,
    profile_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    action stock_action NOT NULL,
    quantity INTEGER NOT NULL,
    supplier_name TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE tables (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES cafes(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    is_occupied BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES cafes(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    phone TEXT,
    total_due NUMERIC(10,2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES cafes(id) ON DELETE CASCADE NOT NULL,
    bill_number SERIAL,
    table_id UUID REFERENCES tables(id) ON DELETE SET NULL,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    waiter_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    cashier_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    type order_type NOT NULL,
    status order_status DEFAULT 'pending',
    subtotal NUMERIC(10,2) NOT NULL DEFAULT 0,
    discount NUMERIC(10,2) NOT NULL DEFAULT 0,
    tax_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    service_charge NUMERIC(10,2) NOT NULL DEFAULT 0,
    grand_total NUMERIC(10,2) NOT NULL DEFAULT 0,
    payment_method payment_method,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE NOT NULL,
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    product_name TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,
    total_price NUMERIC(10,2) NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE expenses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES cafes(id) ON DELETE CASCADE NOT NULL,
    profile_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    category TEXT NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    description TEXT,
    date DATE DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE due_payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES cafes(id) ON DELETE CASCADE NOT NULL,
    customer_id UUID REFERENCES customers(id) ON DELETE CASCADE NOT NULL,
    cashier_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    amount NUMERIC(10,2) NOT NULL,
    payment_method payment_method NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE activity_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cafe_id UUID REFERENCES cafes(id) ON DELETE CASCADE NOT NULL,
    profile_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE settings (
    cafe_id UUID PRIMARY KEY REFERENCES cafes(id) ON DELETE CASCADE NOT NULL,
    tax_percentage NUMERIC(5,2) DEFAULT 13.00,
    service_charge_percentage NUMERIC(5,2) DEFAULT 10.00,
    receipt_footer_message TEXT,
    printer_mac_address TEXT,
    language TEXT DEFAULT 'en',
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS Setup

ALTER TABLE cafes ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE due_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION get_user_cafe_id() RETURNS UUID AS $$
    SELECT cafe_id FROM profiles WHERE id = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER;

-- Generic Isolation Policies
CREATE POLICY "Cafes isolate" ON cafes FOR SELECT USING (id = get_user_cafe_id());
CREATE POLICY "Profiles isolate" ON profiles FOR ALL USING (cafe_id = get_user_cafe_id());
CREATE POLICY "Categories isolate" ON categories FOR ALL USING (cafe_id = get_user_cafe_id());
CREATE POLICY "Products isolate" ON products FOR ALL USING (cafe_id = get_user_cafe_id());
CREATE POLICY "Inventory Logs isolate" ON inventory_logs FOR ALL USING (cafe_id = get_user_cafe_id());
CREATE POLICY "Tables isolate" ON tables FOR ALL USING (cafe_id = get_user_cafe_id());
CREATE POLICY "Customers isolate" ON customers FOR ALL USING (cafe_id = get_user_cafe_id());
CREATE POLICY "Orders isolate" ON orders FOR ALL USING (cafe_id = get_user_cafe_id());
CREATE POLICY "Order items isolate" ON order_items FOR ALL USING ((SELECT cafe_id FROM orders WHERE orders.id = order_items.order_id) = get_user_cafe_id());
CREATE POLICY "Expenses isolate" ON expenses FOR ALL USING (cafe_id = get_user_cafe_id());
CREATE POLICY "Due Payments isolate" ON due_payments FOR ALL USING (cafe_id = get_user_cafe_id());
CREATE POLICY "Activity logs isolate" ON activity_logs FOR ALL USING (cafe_id = get_user_cafe_id());
CREATE POLICY "Settings isolate" ON settings FOR ALL USING (cafe_id = get_user_cafe_id());

-- Basic Seed Data
-- Run this after setting up a user manually in Supabase auth, or adapt for tests.
/*
INSERT INTO cafes (id, name, address) VALUES ('d1e0c7a5-c350-48cf-9a99-b148c3b069d5', 'My Test Cafe', 'KTM, Nepal');
INSERT INTO settings (cafe_id) VALUES ('d1e0c7a5-c350-48cf-9a99-b148c3b069d5');
INSERT INTO categories (id, cafe_id, name) VALUES ('6d8ebba8-d9d3-4a0b-9309-8472506e1ce0', 'd1e0c7a5-c350-48cf-9a99-b148c3b069d5', 'Beverages');
INSERT INTO products (cafe_id, category_id, name, price, cost_price, stock_quantity) VALUES ('d1e0c7a5-c350-48cf-9a99-b148c3b069d5', '6d8ebba8-d9d3-4a0b-9309-8472506e1ce0', 'Americano', 150.00, 30.00, 100);
*/
