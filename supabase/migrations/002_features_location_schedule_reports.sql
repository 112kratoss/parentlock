-- ParentLock Feature Migration
-- Run this in Supabase SQL Editor
-- ==============================================

-- ============================================
-- LOCATION TRACKING
-- ============================================

-- Real-time location records
CREATE TABLE IF NOT EXISTS location_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION,
    battery_level INTEGER,
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast location queries
CREATE INDEX IF NOT EXISTS idx_location_child_time ON location_records(child_id, recorded_at DESC);

-- Enable RLS
ALTER TABLE location_records ENABLE ROW LEVEL SECURITY;

-- Policy: Parents can read their children's locations
CREATE POLICY "Parents can view child locations" ON location_records
    FOR SELECT
    USING (
        child_id IN (
            SELECT id FROM profiles WHERE linked_to = auth.uid()
        )
    );

-- Policy: Children can insert their own locations
CREATE POLICY "Children can insert own location" ON location_records
    FOR INSERT
    WITH CHECK (child_id = auth.uid());

-- ============================================
-- GEOFENCES (Safe Zones)
-- ============================================

CREATE TABLE IF NOT EXISTS geofences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    child_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius_meters INTEGER DEFAULT 100,
    notify_on_enter BOOLEAN DEFAULT true,
    notify_on_exit BOOLEAN DEFAULT true,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE geofences ENABLE ROW LEVEL SECURITY;

-- Policy: Parents can manage their geofences
CREATE POLICY "Parents can manage geofences" ON geofences
    FOR ALL
    USING (parent_id = auth.uid());

-- Policy: Children can read their geofences
CREATE POLICY "Children can view their geofences" ON geofences
    FOR SELECT
    USING (child_id = auth.uid());

-- ============================================
-- GEOFENCE EVENTS LOG
-- ============================================

CREATE TABLE IF NOT EXISTS geofence_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    geofence_id UUID REFERENCES geofences(id) ON DELETE CASCADE,
    child_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('enter', 'exit')),
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE geofence_events ENABLE ROW LEVEL SECURITY;

-- Policy: Children can insert events
CREATE POLICY "Children can insert geofence events" ON geofence_events
    FOR INSERT
    WITH CHECK (child_id = auth.uid());

-- Policy: Parents can view events for their children
CREATE POLICY "Parents can view child geofence events" ON geofence_events
    FOR SELECT
    USING (
        child_id IN (
            SELECT id FROM profiles WHERE linked_to = auth.uid()
        )
    );

-- ============================================
-- SOS ALERTS
-- ============================================

CREATE TABLE IF NOT EXISTS sos_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    message TEXT,
    is_acknowledged BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE sos_alerts ENABLE ROW LEVEL SECURITY;

-- Policy: Children can create SOS alerts
CREATE POLICY "Children can create SOS alerts" ON sos_alerts
    FOR INSERT
    WITH CHECK (child_id = auth.uid());

-- Policy: Parents can view and update SOS alerts
CREATE POLICY "Parents can view child SOS alerts" ON sos_alerts
    FOR SELECT
    USING (
        child_id IN (
            SELECT id FROM profiles WHERE linked_to = auth.uid()
        )
    );

CREATE POLICY "Parents can acknowledge SOS alerts" ON sos_alerts
    FOR UPDATE
    USING (
        child_id IN (
            SELECT id FROM profiles WHERE linked_to = auth.uid()
        )
    );

-- ============================================
-- SCREEN TIME SCHEDULES
-- ============================================

CREATE TABLE IF NOT EXISTS schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    child_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    schedule_type TEXT NOT NULL CHECK (schedule_type IN ('allowed_hours', 'bedtime', 'homework')),
    days_of_week INTEGER[] NOT NULL,  -- 0=Sun, 1=Mon, etc.
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    blocked_categories TEXT[],  -- ['games', 'social', 'video']
    block_all_apps BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE schedules ENABLE ROW LEVEL SECURITY;

-- Policy: Parents can manage schedules
CREATE POLICY "Parents can manage schedules" ON schedules
    FOR ALL
    USING (parent_id = auth.uid());

-- Policy: Children can view their schedules
CREATE POLICY "Children can view their schedules" ON schedules
    FOR SELECT
    USING (child_id = auth.uid());

-- ============================================
-- DAILY USAGE SUMMARY (for reports)
-- ============================================

CREATE TABLE IF NOT EXISTS daily_usage_summary (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    total_minutes INTEGER DEFAULT 0,
    app_breakdown JSONB,  -- {"com.youtube": 45, "com.instagram": 30}
    most_used_app TEXT,
    blocked_attempts INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(child_id, date)
);

-- Enable RLS
ALTER TABLE daily_usage_summary ENABLE ROW LEVEL SECURITY;

-- Policy: Children can insert/update their own summaries
CREATE POLICY "Children can manage own summaries" ON daily_usage_summary
    FOR ALL
    USING (child_id = auth.uid());

-- Policy: Parents can view their children's summaries
CREATE POLICY "Parents can view child summaries" ON daily_usage_summary
    FOR SELECT
    USING (
        child_id IN (
            SELECT id FROM profiles WHERE linked_to = auth.uid()
        )
    );

-- ============================================
-- REAL-TIME SUBSCRIPTIONS
-- ============================================

-- Enable realtime for new tables
ALTER PUBLICATION supabase_realtime ADD TABLE location_records;
ALTER PUBLICATION supabase_realtime ADD TABLE geofence_events;
ALTER PUBLICATION supabase_realtime ADD TABLE sos_alerts;
ALTER PUBLICATION supabase_realtime ADD TABLE schedules;
