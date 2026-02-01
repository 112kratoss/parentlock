-- Fix duplicate apps in child_activity table
-- Run this in Supabase SQL Editor
-- ==============================================

-- Step 1: Remove duplicate entries, keeping only the most recent one
DELETE FROM child_activity a
USING child_activity b
WHERE a.id < b.id
  AND a.child_id = b.child_id
  AND a.app_package_name = b.app_package_name;

-- Step 2: Add unique constraint to prevent future duplicates
-- First, drop the constraint if it exists (to make this idempotent)
ALTER TABLE child_activity DROP CONSTRAINT IF EXISTS unique_child_app;

-- Add the unique constraint
ALTER TABLE child_activity ADD CONSTRAINT unique_child_app 
  UNIQUE (child_id, app_package_name);

-- Verify: Check remaining records (should have no duplicates)
-- SELECT child_id, app_package_name, COUNT(*) 
-- FROM child_activity 
-- GROUP BY child_id, app_package_name 
-- HAVING COUNT(*) > 1;
