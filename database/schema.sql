-- VIVIPREFIT - Esquema Completo PostgreSQL
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Tabla: landing_config
CREATE TABLE IF NOT EXISTS public.landing_config (
    key         TEXT PRIMARY KEY,
    value       JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla: profiles
CREATE TABLE IF NOT EXISTS public.profiles (
    id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email               TEXT UNIQUE NOT NULL,
    full_name           TEXT,
    phone_number        TEXT,
    is_admin            BOOLEAN NOT NULL DEFAULT FALSE,
    stripe_customer_id  TEXT,
    stripe_sub_id       TEXT,
    plan_status         TEXT NOT NULL DEFAULT 'inactive'
                        CHECK (plan_status IN ('active','canceled','past_due','inactive','trial')),
    plan_tier           TEXT NOT NULL DEFAULT 'monthly_40',
    current_period_end  TIMESTAMPTZ,
    trial_start_date    TIMESTAMPTZ,
    trial_end_date      TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_plan_status ON public.profiles(plan_status);

-- Tabla: membership_content
CREATE TABLE IF NOT EXISTS public.membership_content (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cycle_date      DATE NOT NULL,
    category        TEXT NOT NULL,
    title           TEXT NOT NULL,
    description     TEXT,
    bunny_video_id  TEXT,
    storage_path    TEXT,
    content_url     TEXT,
    target_mode     TEXT NOT NULL DEFAULT 'Ambos',
    class_type      TEXT,
    month_year      TEXT,
    is_published    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_membership_content_cycle ON public.membership_content(cycle_date);
CREATE INDEX IF NOT EXISTS idx_membership_content_published ON public.membership_content(is_published);

-- Funcion: handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name, plan_status, plan_tier)
    VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)), 'inactive', 'monthly_40')
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Funcion: set_updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_membership_content_updated_at ON public.membership_content;
CREATE TRIGGER trg_membership_content_updated_at BEFORE UPDATE ON public.membership_content
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_landing_config_updated_at ON public.landing_config;
CREATE TRIGGER trg_landing_config_updated_at BEFORE UPDATE ON public.landing_config
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Funciones auxiliares
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE admin_flag BOOLEAN;
BEGIN
    SELECT COALESCE(p.is_admin, FALSE) INTO admin_flag FROM public.profiles p WHERE p.id = auth.uid();
    RETURN COALESCE(admin_flag, FALSE);
END;
$$;

CREATE OR REPLACE FUNCTION public.has_active_subscription()
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE status TEXT;
BEGIN
    SELECT p.plan_status INTO status FROM public.profiles p WHERE p.id = auth.uid();
    RETURN status = 'active';
END;
$$;

-- Row Level Security
ALTER TABLE public.landing_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membership_content ENABLE ROW LEVEL SECURITY;

-- Politicas landing_config
DROP POLICY IF EXISTS "landing_config_select_public" ON public.landing_config;
CREATE POLICY "landing_config_select_public" ON public.landing_config FOR SELECT TO anon, authenticated USING (TRUE);

DROP POLICY IF EXISTS "landing_config_insert_admin" ON public.landing_config;
CREATE POLICY "landing_config_insert_admin" ON public.landing_config FOR INSERT TO authenticated
    WITH CHECK (public.is_admin() OR (auth.jwt() ->> 'email') = 'admin@vivipressonfit.com');

DROP POLICY IF EXISTS "landing_config_update_admin" ON public.landing_config;
CREATE POLICY "landing_config_update_admin" ON public.landing_config FOR UPDATE TO authenticated
    USING (public.is_admin() OR (auth.jwt() ->> 'email') = 'admin@vivipressonfit.com')
    WITH CHECK (public.is_admin() OR (auth.jwt() ->> 'email') = 'admin@vivipressonfit.com');

-- Politicas profiles
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
CREATE POLICY "profiles_select_own" ON public.profiles FOR SELECT TO authenticated
    USING (auth.uid() = id OR public.is_admin());

DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
CREATE POLICY "profiles_insert_own" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own" ON public.profiles FOR UPDATE TO authenticated
    USING (auth.uid() = id OR public.is_admin()) WITH CHECK (auth.uid() = id OR public.is_admin());

-- Politicas membership_content
DROP POLICY IF EXISTS "membership_content_select_subscribers" ON public.membership_content;
CREATE POLICY "membership_content_select_subscribers" ON public.membership_content FOR SELECT TO authenticated
    USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.plan_status = 'active'));

DROP POLICY IF EXISTS "membership_content_insert_admin" ON public.membership_content;
CREATE POLICY "membership_content_insert_admin" ON public.membership_content FOR INSERT TO authenticated
    WITH CHECK (public.is_admin() OR (auth.jwt() ->> 'email') = 'admin@vivipressonfit.com');

-- Seed data
INSERT INTO public.landing_config (key, value) VALUES
    ('membership_params', jsonb_build_object('price', 40, 'currency', 'USD', 'whatsapp_number', '59178000000')),
    ('hero_texts', jsonb_build_object('title', 'Programa de Entrenamiento', 'sub', 'Metodo completo y dinamico.'))
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.membership_content (cycle_date, category, title, target_mode, class_type, month_year, is_published, content_url)
VALUES
    (date_trunc('month', CURRENT_DATE)::date, 'GAP', 'GAP: Gluteos, Abdomen y Piernas', 'Ambos', 'gap', to_char(CURRENT_DATE, 'YYYY-MM'), TRUE, 'https://example.com/gap'),
    (date_trunc('month', CURRENT_DATE)::date, 'Full Body', 'Full Body Integral', 'Ambos', 'full_body', to_char(CURRENT_DATE, 'YYYY-MM'), TRUE, 'https://example.com/full'),
    (date_trunc('month', CURRENT_DATE)::date, 'Cardio HIIT', 'Cardio HIIT', 'Ambos', 'hiit', to_char(CURRENT_DATE, 'YYYY-MM'), TRUE, 'https://example.com/hiit'),
    (date_trunc('month', CURRENT_DATE)::date, 'Fuerza + Aerobico', 'Fuerza + Aerobico', 'Ambos', 'aerobico', to_char(CURRENT_DATE, 'YYYY-MM'), TRUE, 'https://example.com/aero'),
    (date_trunc('month', CURRENT_DATE)::date, 'Rutina Fuerza', 'Plan Fuerza Casa', 'Casa', 'rutina_casa', to_char(CURRENT_DATE, 'YYYY-MM'), TRUE, 'https://example.com/casa'),
    (date_trunc('month', CURRENT_DATE)::date, 'Rutina Fuerza', 'Plan Fuerza Gym', 'Gimnasio', 'rutina_gym', to_char(CURRENT_DATE, 'YYYY-MM'), TRUE, 'https://example.com/gym'),
    (date_trunc('month', CURRENT_DATE)::date, 'Nutricion', 'Guia Nutricional', 'Ambos', 'nutricion', to_char(CURRENT_DATE, 'YYYY-MM'), TRUE, 'https://example.com/nut')
ON CONFLICT DO NOTHING;


-- ============================================================================
-- STORAGE: Buckets y politicas
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('landing-media', 'landing-media', TRUE, 52428800,
        ARRAY['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm']),
    ('nutrition-pdfs', 'nutrition-pdfs', FALSE, 20971520,
        ARRAY['application/pdf'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "landing_media_public_read" ON storage.objects;
CREATE POLICY "landing_media_public_read"
    ON storage.objects FOR SELECT
    TO anon, authenticated
    USING (bucket_id = 'landing-media');

DROP POLICY IF EXISTS "landing_media_admin_write" ON storage.objects;
CREATE POLICY "landing_media_admin_write"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (bucket_id = 'landing-media' AND public.is_admin());

DROP POLICY IF EXISTS "landing_media_admin_update" ON storage.objects;
CREATE POLICY "landing_media_admin_update"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (bucket_id = 'landing-media' AND public.is_admin())
    WITH CHECK (bucket_id = 'landing-media' AND public.is_admin());

DROP POLICY IF EXISTS "landing_media_admin_delete" ON storage.objects;
CREATE POLICY "landing_media_admin_delete"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (bucket_id = 'landing-media' AND public.is_admin());

DROP POLICY IF EXISTS "nutrition_pdfs_subscriber_read" ON storage.objects;
CREATE POLICY "nutrition_pdfs_subscriber_read"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (bucket_id = 'nutrition-pdfs' AND (public.is_admin() OR public.has_active_subscription()));

DROP POLICY IF EXISTS "nutrition_pdfs_admin_write" ON storage.objects;
CREATE POLICY "nutrition_pdfs_admin_write"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (bucket_id = 'nutrition-pdfs' AND public.is_admin());


-- ============================================================================
-- STORAGE: Buckets y politicas
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('landing-media', 'landing-media', TRUE, 52428800,
        ARRAY['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm']),
    ('nutrition-pdfs', 'nutrition-pdfs', FALSE, 20971520,
        ARRAY['application/pdf'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "landing_media_public_read" ON storage.objects;
CREATE POLICY "landing_media_public_read"
    ON storage.objects FOR SELECT
    TO anon, authenticated
    USING (bucket_id = 'landing-media');

DROP POLICY IF EXISTS "landing_media_admin_write" ON storage.objects;
CREATE POLICY "landing_media_admin_write"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (bucket_id = 'landing-media' AND public.is_admin());

DROP POLICY IF EXISTS "landing_media_admin_update" ON storage.objects;
CREATE POLICY "landing_media_admin_update"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (bucket_id = 'landing-media' AND public.is_admin())
    WITH CHECK (bucket_id = 'landing-media' AND public.is_admin());

DROP POLICY IF EXISTS "landing_media_admin_delete" ON storage.objects;
CREATE POLICY "landing_media_admin_delete"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (bucket_id = 'landing-media' AND public.is_admin());

DROP POLICY IF EXISTS "nutrition_pdfs_subscriber_read" ON storage.objects;
CREATE POLICY "nutrition_pdfs_subscriber_read"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (bucket_id = 'nutrition-pdfs' AND (public.is_admin() OR public.has_active_subscription()));

DROP POLICY IF EXISTS "nutrition_pdfs_admin_write" ON storage.objects;
CREATE POLICY "nutrition_pdfs_admin_write"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (bucket_id = 'nutrition-pdfs' AND public.is_admin());