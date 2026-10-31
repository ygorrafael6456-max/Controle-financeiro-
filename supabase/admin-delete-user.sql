-- Exclusão permanente com registro de banimento para impedir novo acesso.
-- Execute este arquivo no SQL Editor do Supabase.

CREATE TABLE IF NOT EXISTS public.permanent_bans (
  email TEXT PRIMARY KEY,
  display_name TEXT,
  reason TEXT NOT NULL DEFAULT 'Banimento permanente pelo administrador.',
  banned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  banned_by TEXT
);

ALTER TABLE public.permanent_bans ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.permanent_bans FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_permanent_ban_status(p_email TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_result JSONB;
BEGIN
  IF p_email IS NULL OR btrim(p_email) = '' THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'reason', reason,
    'banned_at', banned_at,
    'banned_by', banned_by
  )
  INTO v_result
  FROM public.permanent_bans
  WHERE lower(email) = lower(btrim(p_email));

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_permanent_ban_status(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_permanent_ban_status(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_user(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_email TEXT;
  v_display_name TEXT;
  v_admin_name TEXT;
BEGIN
  IF auth.uid() IS NULL
     OR public.get_my_staff_role() IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Acesso permitido somente para administradores.';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Informe uma conta válida.';
  END IF;

  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Você não pode excluir sua própria conta.';
  END IF;

  SELECT u.email, COALESCE(p.display_name, u.raw_user_meta_data->>'full_name')
  INTO v_email, v_display_name
  FROM auth.users AS u
  LEFT JOIN public.profiles AS p ON p.id = u.id
  WHERE u.id = p_user_id;

  IF v_email IS NULL THEN
    RAISE EXCEPTION 'A conta informada não existe ou já foi excluída.';
  END IF;

  SELECT display_name
  INTO v_admin_name
  FROM public.profiles
  WHERE id = auth.uid();

  -- Guarda um registro mínimo para identificar o banimento após apagar o usuário.
  INSERT INTO public.permanent_bans (email, display_name, reason, banned_by)
  VALUES (
    lower(v_email),
    v_display_name,
    'Banimento permanente pelo administrador.',
    COALESCE(v_admin_name, 'Administrador')
  )
  ON CONFLICT (email) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    reason = EXCLUDED.reason,
    banned_at = now(),
    banned_by = EXCLUDED.banned_by;

  -- Dispara o aviso em tempo real para sessões que ainda estejam abertas.
  UPDATE public.profiles
  SET is_blocked = true
  WHERE id = p_user_id;

  DELETE FROM public.transactions WHERE user_id = p_user_id;
  DELETE FROM public.staff_roles WHERE user_id = p_user_id;
  DELETE FROM public.profiles WHERE id = p_user_id;

  -- O registro em permanent_bans permanece mesmo após remover a autenticação.
  DELETE FROM auth.users WHERE id = p_user_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_delete_user(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_user(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
