-- Migration to clean up duplicates and fix zero limits

-- 1. Fix limits for apps that are not blocked but have 0 limit (Bug fix)
UPDATE public.child_activity
SET daily_limit_minutes = 1440,
    is_blocked = false 
WHERE daily_limit_minutes = 0 
  AND is_blocked = false;

-- 2. Remove duplicates
-- Keep the record that has the highest daily_limit_minutes (likely the configured one)
-- If equal, keep the most recently updated one.
DELETE FROM public.child_activity a
USING public.child_activity b
WHERE a.id < b.id
  AND a.child_id = b.child_id
  AND a.app_package_name = b.app_package_name
  AND (
    a.daily_limit_minutes < b.daily_limit_minutes 
    OR (a.daily_limit_minutes = b.daily_limit_minutes AND a.last_updated < b.last_updated)
  );

-- 3. Add unique constraint to prevent future duplicates
ALTER TABLE public.child_activity
ADD CONSTRAINT child_activity_child_id_package_unique UNIQUE (child_id, app_package_name);
