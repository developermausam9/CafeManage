-- Migration V2: Hotel Booking System Enhancements
-- Adds billing fields to room_bookings and links orders to bookings

-- 1. Add new columns to room_bookings
ALTER TABLE room_bookings
  ADD COLUMN IF NOT EXISTS actual_checkin_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS actual_checkout_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS room_charge NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS food_orders_total NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS grand_total NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'cash',
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS confirmed_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS checked_in_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS checked_out_by UUID REFERENCES profiles(id) ON DELETE SET NULL;

-- 2. Add room_booking_id to orders table (links food orders to a booking)
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS room_booking_id UUID REFERENCES room_bookings(id) ON DELETE SET NULL;

-- 3. Create index for fast lookup
CREATE INDEX IF NOT EXISTS idx_orders_room_booking_id ON orders(room_booking_id);
CREATE INDEX IF NOT EXISTS idx_room_bookings_status ON room_bookings(status);
CREATE INDEX IF NOT EXISTS idx_room_bookings_cafe_check_in ON room_bookings(cafe_id, check_in_date);
