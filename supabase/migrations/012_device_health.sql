-- Device health, anti-tamper events, and offline reconciliation

CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE TABLE IF NOT EXISTS device_health (
    child_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    enrollment_mode TEXT NOT NULL DEFAULT 'standard'
        CHECK (enrollment_mode IN ('managed_device', 'standard', 'limited')),
    tamper_state TEXT NOT NULL DEFAULT 'healthy'
        CHECK (tamper_state IN ('healthy', 'degraded', 'tampered', 'offline')),
    tamper_reason TEXT,
    last_heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_service_seen_at TIMESTAMPTZ,
    last_policy_sync_at TIMESTAMPTZ,
    last_permission_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
    device_owner BOOLEAN NOT NULL DEFAULT FALSE,
    critical_permissions_ok BOOLEAN NOT NULL DEFAULT FALSE,
    monitoring_active BOOLEAN NOT NULL DEFAULT FALSE,
    app_version TEXT,
    last_healthy_at TIMESTAMPTZ,
    last_alert_sent_at TIMESTAMPTZ,
    last_reminder_sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_health_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    enrollment_mode TEXT NOT NULL
        CHECK (enrollment_mode IN ('managed_device', 'standard', 'limited')),
    tamper_state TEXT NOT NULL
        CHECK (tamper_state IN ('healthy', 'degraded', 'tampered', 'offline')),
    tamper_reason TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_health_events_child_time
    ON device_health_events(child_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_health_heartbeat
    ON device_health(last_heartbeat_at DESC);

ALTER TABLE device_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_health_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Children can manage own device health" ON device_health
    FOR ALL
    USING (child_id = auth.uid())
    WITH CHECK (child_id = auth.uid());

CREATE POLICY "Parents can view child device health" ON device_health
    FOR SELECT
    USING (
        child_id IN (
            SELECT id FROM profiles WHERE linked_to = auth.uid()
        )
    );

CREATE POLICY "Children can view own device health events" ON device_health_events
    FOR SELECT
    USING (child_id = auth.uid());

CREATE POLICY "Parents can view child device health events" ON device_health_events
    FOR SELECT
    USING (
        child_id IN (
            SELECT id FROM profiles WHERE linked_to = auth.uid()
        )
    );

CREATE OR REPLACE FUNCTION prepare_device_health_write()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    NEW.last_permission_snapshot := COALESCE(NEW.last_permission_snapshot, '{}'::JSONB);

    IF NEW.last_heartbeat_at IS NULL THEN
        NEW.last_heartbeat_at := NOW();
    END IF;

    IF NEW.tamper_state = 'healthy' THEN
        NEW.last_healthy_at := COALESCE(NEW.last_healthy_at, NOW());
        IF TG_OP = 'UPDATE' AND OLD.tamper_state IS DISTINCT FROM NEW.tamper_state THEN
            NEW.last_healthy_at := NOW();
        END IF;
        NEW.last_reminder_sent_at := NULL;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.tamper_state IN ('tampered', 'offline') THEN
            NEW.last_alert_sent_at := NOW();
            NEW.last_reminder_sent_at := NULL;
        END IF;
    ELSIF OLD.tamper_state IS DISTINCT FROM NEW.tamper_state
        OR COALESCE(OLD.tamper_reason, '') IS DISTINCT FROM COALESCE(NEW.tamper_reason, '')
    THEN
        IF NEW.tamper_state IN ('tampered', 'offline') THEN
            NEW.last_alert_sent_at := NOW();
            NEW.last_reminder_sent_at := NULL;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION log_device_health_transition()
RETURNS TRIGGER AS $$
DECLARE
    v_title TEXT;
    v_body TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO device_health_events (
            child_id,
            enrollment_mode,
            tamper_state,
            tamper_reason,
            metadata
        ) VALUES (
            NEW.child_id,
            NEW.enrollment_mode,
            NEW.tamper_state,
            NEW.tamper_reason,
            jsonb_build_object(
                'is_reminder', FALSE,
                'device_owner', NEW.device_owner,
                'critical_permissions_ok', NEW.critical_permissions_ok
            )
        );

        IF NEW.tamper_state IN ('tampered', 'offline') THEN
            v_title := CASE
                WHEN NEW.tamper_state = 'offline' THEN 'ParentLock offline'
                ELSE 'ParentLock tamper detected'
            END;

            v_body := CASE
                WHEN NEW.tamper_reason IS NOT NULL AND NEW.tamper_reason <> '' THEN NEW.tamper_reason
                WHEN NEW.tamper_state = 'offline' THEN 'No heartbeat received from the child device.'
                ELSE 'Monitoring protection was interrupted on the child device.'
            END;

            PERFORM notify_parent_push(
                'health',
                NEW.child_id,
                v_title,
                v_body,
                jsonb_build_object(
                    'tamper_state', NEW.tamper_state,
                    'tamper_reason', COALESCE(NEW.tamper_reason, ''),
                    'enrollment_mode', NEW.enrollment_mode
                )
            );
        END IF;
    ELSIF OLD.tamper_state IS DISTINCT FROM NEW.tamper_state
        OR COALESCE(OLD.tamper_reason, '') IS DISTINCT FROM COALESCE(NEW.tamper_reason, '')
        OR OLD.enrollment_mode IS DISTINCT FROM NEW.enrollment_mode
    THEN
        INSERT INTO device_health_events (
            child_id,
            enrollment_mode,
            tamper_state,
            tamper_reason,
            metadata
        ) VALUES (
            NEW.child_id,
            NEW.enrollment_mode,
            NEW.tamper_state,
            NEW.tamper_reason,
            jsonb_build_object(
                'is_reminder', FALSE,
                'device_owner', NEW.device_owner,
                'critical_permissions_ok', NEW.critical_permissions_ok
            )
        );

        IF NEW.tamper_state IN ('tampered', 'offline') THEN
            v_title := CASE
                WHEN NEW.tamper_state = 'offline' THEN 'ParentLock offline'
                ELSE 'ParentLock tamper detected'
            END;

            v_body := CASE
                WHEN NEW.tamper_reason IS NOT NULL AND NEW.tamper_reason <> '' THEN NEW.tamper_reason
                WHEN NEW.tamper_state = 'offline' THEN 'No heartbeat received from the child device.'
                ELSE 'Monitoring protection was interrupted on the child device.'
            END;

            PERFORM notify_parent_push(
                'health',
                NEW.child_id,
                v_title,
                v_body,
                jsonb_build_object(
                    'tamper_state', NEW.tamper_state,
                    'tamper_reason', COALESCE(NEW.tamper_reason, ''),
                    'enrollment_mode', NEW.enrollment_mode
                )
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS before_device_health_write ON device_health;
CREATE TRIGGER before_device_health_write
    BEFORE INSERT OR UPDATE ON device_health
    FOR EACH ROW
    EXECUTE FUNCTION prepare_device_health_write();

DROP TRIGGER IF EXISTS after_device_health_write ON device_health;
CREATE TRIGGER after_device_health_write
    AFTER INSERT OR UPDATE ON device_health
    FOR EACH ROW
    EXECUTE FUNCTION log_device_health_transition();

CREATE OR REPLACE FUNCTION reconcile_device_health_states()
RETURNS VOID AS $$
DECLARE
    reminder_row RECORD;
BEGIN
    UPDATE device_health
    SET
        tamper_state = 'offline',
        tamper_reason = 'No heartbeat received in the last 3 minutes.',
        monitoring_active = FALSE,
        updated_at = NOW()
    WHERE last_heartbeat_at < NOW() - INTERVAL '3 minutes'
      AND tamper_state <> 'offline';

    FOR reminder_row IN
        SELECT child_id, tamper_state, tamper_reason, enrollment_mode
        FROM device_health
        WHERE tamper_state IN ('tampered', 'offline')
          AND last_alert_sent_at IS NOT NULL
          AND last_alert_sent_at <= NOW() - INTERVAL '15 minutes'
          AND (
              last_reminder_sent_at IS NULL
              OR last_reminder_sent_at < last_alert_sent_at
          )
    LOOP
        PERFORM notify_parent_push(
            'health',
            reminder_row.child_id,
            'ParentLock still needs attention',
            CASE
                WHEN reminder_row.tamper_state = 'offline' THEN
                    'The child device is still offline and ParentLock has not recovered.'
                ELSE
                    'Protection is still interrupted on the child device.'
            END,
            jsonb_build_object(
                'tamper_state', reminder_row.tamper_state,
                'tamper_reason', COALESCE(reminder_row.tamper_reason, ''),
                'enrollment_mode', reminder_row.enrollment_mode,
                'is_reminder', TRUE
            )
        );

        UPDATE device_health
        SET
            last_reminder_sent_at = NOW(),
            updated_at = NOW()
        WHERE child_id = reminder_row.child_id;

        INSERT INTO device_health_events (
            child_id,
            enrollment_mode,
            tamper_state,
            tamper_reason,
            metadata
        ) VALUES (
            reminder_row.child_id,
            reminder_row.enrollment_mode,
            reminder_row.tamper_state,
            reminder_row.tamper_reason,
            jsonb_build_object('is_reminder', TRUE)
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DO $device_health_cron$
DECLARE
    existing_job RECORD;
BEGIN
    FOR existing_job IN
        SELECT jobid
        FROM cron.job
        WHERE jobname = 'parentlock-device-health'
    LOOP
        PERFORM cron.unschedule(existing_job.jobid);
    END LOOP;

    PERFORM cron.schedule(
        'parentlock-device-health',
        '* * * * *',
        'SELECT public.reconcile_device_health_states();'
    );
EXCEPTION
    WHEN undefined_table OR undefined_function THEN
        RAISE NOTICE 'pg_cron is unavailable; reconcile_device_health_states will need to be called manually.';
END;
$device_health_cron$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE device_health;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE device_health_events;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;
