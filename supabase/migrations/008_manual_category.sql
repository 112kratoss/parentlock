-- Add manual_category to child_activity
-- This allows parents to override the auto-detected category
ALTER TABLE child_activity 
ADD COLUMN manual_category text;

-- Create function to update manual category (or we can just use standard update since policies allow it)
-- Parents can update child_activity
