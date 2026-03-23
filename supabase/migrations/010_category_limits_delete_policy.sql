-- Add missing DELETE RLS policy for category_limits
-- Allows parents to remove category limits for their linked children.

DROP POLICY IF EXISTS "Parents can delete their children's category limits"
ON public.category_limits;

CREATE POLICY "Parents can delete their children's category limits"
ON public.category_limits FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = category_limits.child_id
    AND profiles.linked_to = auth.uid()
  )
);
