-- Exclusão permanente de contas pelo painel Staff.
-- Execute este arquivo no SQL Editor do Supabase.

CREATE OR REPLACE FUNCTION public.admin_delete_user(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
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

  IF NOT EXISTS (
    SELECT 1 FROM auth.users WHERE id = p_user_id
  ) THEN
    RAISE EXCEPTION 'A conta informada não existe ou já foi excluída.';
  END IF;

  -- Remove os dados operacionais conhecidos desta conta.
  DELETE FROM public.transactions
  WHERE user_id = p_user_id;

  DELETE FROM public.staff_roles
  WHERE user_id = p_user_id;

  DELETE FROM public.profiles
  WHERE id = p_user_id;

  -- A exclusão em auth.users remove a conta de autenticação.
  -- O histórico de bloqueios é preservado para auditoria.
  DELETE FROM auth.users
  WHERE id = p_user_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_delete_user(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_user(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
