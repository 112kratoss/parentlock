-- Fix for Block Notification Trigger
-- Fixes "operator does not exist: text ->> unknown" error
-- ==============================================

CREATE OR REPLACE FUNCTION notify_parent_on_block()
RETURNS TRIGGER AS $$
DECLARE
  parent_fcm TEXT;
  parent_id UUID;
BEGIN
  -- Only trigger if is_blocked changed from FALSE to TRUE
  IF OLD.is_blocked = FALSE AND NEW.is_blocked = TRUE THEN
    -- Get child's linked parent
    SELECT linked_to INTO parent_id
    FROM profiles
    WHERE id = NEW.child_id;
    
    IF parent_id IS NOT NULL THEN
      -- Get parent's FCM token
      SELECT fcm_token INTO parent_fcm
      FROM profiles
      WHERE id = parent_id;
      
      IF parent_fcm IS NOT NULL THEN
        -- Call the Edge Function to send notification
        -- Fixed Authorization header to use service_role_key instead of broken JWT extraction
        PERFORM
          net.http_post(
            url := 'https://clycrthzxpjwxrqlqkqv.supabase.co/functions/v1/send-block-notification',
            headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'Authorization', 'Bearer ' || COALESCE(
                  current_setting('app.settings.service_role_key', true),
                  current_setting('app.settings.anon_key', true),
                  ''
              )
            ),
            body := jsonb_build_object(
              'child_id', NEW.child_id::text,
              'app_name', NEW.app_display_name,
              'parent_fcm_token', parent_fcm
            )
          );
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
