-- Add category column to child_activity
ALTER TABLE public.child_activity
ADD COLUMN category text DEFAULT 'other';

-- Create table for category limits
CREATE TABLE public.category_limits (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    child_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    category text NOT NULL,
    daily_limit_minutes int NOT NULL DEFAULT 60,
    last_updated timestamptz DEFAULT now(),
    UNIQUE(child_id, category)
);

-- Enable RLS
ALTER TABLE public.category_limits ENABLE ROW LEVEL SECURITY;

-- Policies for category_limits
-- Parents can view/edit their children's category limits
CREATE POLICY "Parents can view their children's category limits"
ON public.category_limits FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = category_limits.child_id
    AND profiles.linked_to = auth.uid()
  )
);

CREATE POLICY "Parents can update their children's category limits"
ON public.category_limits FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = category_limits.child_id
    AND profiles.linked_to = auth.uid()
  )
);

CREATE POLICY "Parents can update their children's category limits update"
ON public.category_limits FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = category_limits.child_id
    AND profiles.linked_to = auth.uid()
  )
);

-- Children can view their own limits
CREATE POLICY "Children can view their own category limits"
ON public.category_limits FOR SELECT
USING ( auth.uid() = child_id );

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.category_limits;
