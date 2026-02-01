-- Push Notification Triggers Migration
-- Creates database triggers that call Edge Function on SOS and geofence events

-- ============================================
-- HELPER FUNCTION: Call Edge Function
-- ============================================

CREATE OR REPLACE FUNCTION notify_parent_push(
    p_type TEXT,
    p_child_id UUID,
    p_title TEXT,
    p_body TEXT,
    p_data JSONB DEFAULT '{}'::JSONB
)
RETURNS VOID AS $$
DECLARE
    v_parent_id UUID;
    v_parent_fcm_token TEXT;
    v_edge_function_url TEXT;
BEGIN
    -- Get parent ID from child's profile
    SELECT linked_to INTO v_parent_id
    FROM profiles
    WHERE id = p_child_id;
    
    IF v_parent_id IS NULL THEN
        RAISE NOTICE 'No parent linked to child %', p_child_id;
        RETURN;
    END IF;
    
    -- Get parent's FCM token
    SELECT fcm_token INTO v_parent_fcm_token
    FROM profiles
    WHERE id = v_parent_id;
    
    IF v_parent_fcm_token IS NULL THEN
        RAISE NOTICE 'No FCM token for parent %', v_parent_id;
        RETURN;
    END IF;
    
    -- Call Edge Function via pg_net (async HTTP)
    -- Note: Requires pg_net extension to be enabled
    PERFORM net.http_post(
        url := 'https://' || current_setting('app.settings.project_ref', true) || '.supabase.co/functions/v1/send-push-notification',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := jsonb_build_object(
            'type', p_type,
            'childId', p_child_id::TEXT,
            'parentFcmToken', v_parent_fcm_token,
            'title', p_title,
            'body', p_body,
            'data', p_data
        )
    );
    
    RAISE NOTICE 'Push notification sent for % to parent %', p_type, v_parent_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Failed to send push notification: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- SOS ALERT TRIGGER
-- ============================================

CREATE OR REPLACE FUNCTION trigger_sos_push_notification()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM notify_parent_push(
        'sos',
        NEW.child_id,
        '🆘 SOS ALERT!',
        COALESCE(NEW.message, 'Your child needs help immediately!'),
        jsonb_build_object(
            'latitude', COALESCE(NEW.latitude::TEXT, ''),
            'longitude', COALESCE(NEW.longitude::TEXT, ''),
            'alert_id', NEW.id::TEXT
        )
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on sos_alerts table
DROP TRIGGER IF EXISTS on_sos_alert_created ON sos_alerts;
CREATE TRIGGER on_sos_alert_created
    AFTER INSERT ON sos_alerts
    FOR EACH ROW
    EXECUTE FUNCTION trigger_sos_push_notification();

-- ============================================
-- GEOFENCE EVENT TRIGGER
-- ============================================

CREATE OR REPLACE FUNCTION trigger_geofence_push_notification()
RETURNS TRIGGER AS $$
DECLARE
    v_geofence_name TEXT;
    v_title TEXT;
    v_body TEXT;
BEGIN
    -- Get geofence name
    SELECT name INTO v_geofence_name
    FROM geofences
    WHERE id = NEW.geofence_id;
    
    v_geofence_name := COALESCE(v_geofence_name, 'Safe Zone');
    
    -- Set message based on event type
    IF NEW.event_type = 'enter' THEN
        v_title := '✅ Arrived at ' || v_geofence_name;
        v_body := 'Your child has entered ' || v_geofence_name;
    ELSE
        v_title := '⚠️ Left ' || v_geofence_name;
        v_body := 'Your child has left ' || v_geofence_name;
    END IF;
    
    PERFORM notify_parent_push(
        'geofence',
        NEW.child_id,
        v_title,
        v_body,
        jsonb_build_object(
            'event_type', NEW.event_type,
            'geofence_id', NEW.geofence_id::TEXT,
            'geofence_name', v_geofence_name
        )
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on geofence_events table
DROP TRIGGER IF EXISTS on_geofence_event_created ON geofence_events;
CREATE TRIGGER on_geofence_event_created
    AFTER INSERT ON geofence_events
    FOR EACH ROW
    EXECUTE FUNCTION trigger_geofence_push_notification();

-- ============================================
-- NOTES
-- ============================================
-- 
-- This migration requires:
-- 1. pg_net extension enabled (for async HTTP calls)
-- 2. Edge Function deployed: send-push-notification
-- 3. Secrets configured in Supabase:
--    - FIREBASE_SERVER_KEY: Your FCM server key from Firebase Console
-- 
-- To enable pg_net:
-- Run in SQL Editor: CREATE EXTENSION IF NOT EXISTS pg_net;
-- 
-- To set app settings (for edge function URL):
-- ALTER DATABASE postgres SET "app.settings.project_ref" = 'your-project-ref';
-- ALTER DATABASE postgres SET "app.settings.service_role_key" = 'your-service-role-key';
