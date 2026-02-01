-- Bulk Upsert RPC for Optimization
-- Allows inserting/updating multiple activity records in a single transaction

CREATE OR REPLACE FUNCTION bulk_upsert_child_activity(
    p_records JSONB[]
)
RETURNS VOID AS $$
DECLARE
    v_record JSONB;
BEGIN
    FOREACH v_record IN ARRAY p_records
    LOOP
        INSERT INTO child_activity (
            child_id,
            app_package_name,
            app_display_name,
            daily_limit_minutes,
            minutes_used,
            is_blocked,
            last_updated,
            category,
            manual_category
        )
        VALUES (
            (v_record->>'child_id')::UUID,
            v_record->>'app_package_name',
            v_record->>'app_display_name',
            COALESCE((v_record->>'daily_limit_minutes')::INTEGER, 0),
            COALESCE((v_record->>'minutes_used')::INTEGER, 0),
            COALESCE((v_record->>'is_blocked')::BOOLEAN, false),
            COALESCE((v_record->>'last_updated')::TIMESTAMPTZ, NOW()),
            COALESCE(v_record->>'category', 'other'),
            v_record->>'manual_category'
        )
        ON CONFLICT (child_id, app_package_name)
        DO UPDATE SET
            app_display_name = EXCLUDED.app_display_name,
            -- Do NOT overwrite daily_limit_minutes if it's 0 (manual block) or specifically set?
            -- Actually, syncAllUsageStats logic in Dart already handles limit preservation.
            -- So we can just trust the incoming payload.
            daily_limit_minutes = EXCLUDED.daily_limit_minutes,
            minutes_used = EXCLUDED.minutes_used,
            is_blocked = EXCLUDED.is_blocked,
            last_updated = EXCLUDED.last_updated,
            category = EXCLUDED.category, 
            manual_category = EXCLUDED.manual_category;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
