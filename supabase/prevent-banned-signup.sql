-- Impede que um e-mail banido permanentemente crie uma nova conta no Supabase Auth.
-- Execute este arquivo no SQL Editor do Supabase após admin-delete-user.sql.

CREATE OR REPLACE FUNCTION public.prevent_banned_email_signup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.email IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.permanent_bans AS b
       WHERE lower(b.email) = lower(btrim(NEW.email))
     ) THEN
    RAISE EXCEPTION 'Esta conta foi banida permanentemente e não pode ser cadastrada novamente.'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS prevent_banned_email_signup ON auth.users;

CREATE TRIGGER prevent_banned_email_signup
BEFORE INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.prevent_banned_email_signup();
