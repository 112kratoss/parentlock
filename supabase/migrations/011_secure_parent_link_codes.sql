-- Secure one-time parent link codes
-- Replaces client-side UUID prefix matching with short-lived server-validated codes.

CREATE TABLE IF NOT EXISTS public.parent_link_codes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    code text NOT NULL,
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT parent_link_codes_code_length CHECK (char_length(code) = 8),
    CONSTRAINT parent_link_codes_code_unique UNIQUE (code)
);

ALTER TABLE public.parent_link_codes ENABLE ROW LEVEL SECURITY;

CREATE UNIQUE INDEX IF NOT EXISTS parent_link_codes_one_active_per_parent_idx
ON public.parent_link_codes (parent_id)
WHERE used_at IS NULL;

CREATE OR REPLACE FUNCTION public.generate_random_parent_link_code(
    p_length integer DEFAULT 8
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    v_result text := '';
    v_index integer;
BEGIN
    FOR v_index IN 1..p_length LOOP
        v_result := v_result || substr(v_chars, floor(random() * length(v_chars) + 1)::integer, 1);
    END LOOP;

    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_parent_link_code()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_parent_id uuid := auth.uid();
    v_code text;
    v_expires_at timestamptz := now() + interval '10 minutes';
    v_attempt integer := 0;
BEGIN
    IF v_parent_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = v_parent_id
          AND role = 'parent'
    ) THEN
        RAISE EXCEPTION 'Only parent accounts can generate linking codes';
    END IF;

    UPDATE public.parent_link_codes
    SET used_at = now()
    WHERE parent_id = v_parent_id
      AND used_at IS NULL;

    LOOP
        v_attempt := v_attempt + 1;
        v_code := public.generate_random_parent_link_code(8);

        BEGIN
            INSERT INTO public.parent_link_codes (
                parent_id,
                code,
                expires_at
            ) VALUES (
                v_parent_id,
                v_code,
                v_expires_at
            );

            RETURN jsonb_build_object(
                'code', v_code,
                'expires_at', v_expires_at
            );
        EXCEPTION
            WHEN unique_violation THEN
                IF v_attempt >= 10 THEN
                    RAISE EXCEPTION 'Unable to generate a unique linking code';
                END IF;
        END;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.redeem_parent_link_code(
    p_code text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_child_id uuid := auth.uid();
    v_parent_id uuid;
BEGIN
    IF v_child_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = v_child_id
          AND role = 'child'
    ) THEN
        RAISE EXCEPTION 'Only child accounts can use a linking code';
    END IF;

    SELECT parent_id
    INTO v_parent_id
    FROM public.parent_link_codes
    WHERE code = upper(trim(p_code))
      AND used_at IS NULL
      AND expires_at > now()
    FOR UPDATE;

    IF v_parent_id IS NULL THEN
        RAISE EXCEPTION 'Invalid or expired linking code';
    END IF;

    IF v_parent_id = v_child_id THEN
        RAISE EXCEPTION 'You cannot link a child account to itself';
    END IF;

    UPDATE public.profiles
    SET linked_to = v_parent_id
    WHERE id = v_child_id;

    UPDATE public.parent_link_codes
    SET used_at = now()
    WHERE code = upper(trim(p_code))
      AND used_at IS NULL;

    RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_parent_link_code() TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_parent_link_code(text) TO authenticated;
