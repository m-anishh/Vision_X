-- Missing core tables that the backend writes to but were never captured as
-- migrations anywhere in the repo: profiles, analysis (image module), and the
-- full news verification module (news_analyses/news_agent_results/news_evidence/news_reports).
-- Reconstructed from actual column usage in backend/api/auth.py,
-- backend/services/image_analysis_service.py and backend/services/news_pipeline.py.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- profiles (extends Supabase Auth user)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT,
    username TEXT UNIQUE,
    avatar_url TEXT,
    bio TEXT,
    role TEXT NOT NULL DEFAULT 'user',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile" ON public.profiles
    FOR SELECT USING ((select auth.uid()) = id);
CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE USING ((select auth.uid()) = id);
CREATE POLICY "Users can insert own profile" ON public.profiles
    FOR INSERT WITH CHECK ((select auth.uid()) = id);

-- ============================================================
-- analysis (image verification module - singular table name)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.analysis (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    upload_id VARCHAR(36), -- uploads.id is VARCHAR(36), not native UUID (see 001_create_analysis_tables.sql)
    trust_score NUMERIC DEFAULT 0,
    authenticity_status TEXT DEFAULT 'unknown',
    risk_level TEXT DEFAULT 'unknown',
    summary TEXT,
    ai_model TEXT,
    reasoning JSONB DEFAULT '{}',
    evidence_summary JSONB DEFAULT '[]',
    recommendations JSONB DEFAULT '[]',
    agent_results JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analysis_user_id ON public.analysis(user_id);

ALTER TABLE public.analysis ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own analysis" ON public.analysis
    FOR SELECT USING ((select auth.uid()) = user_id);
CREATE POLICY "Users can insert own analysis" ON public.analysis
    FOR INSERT WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "Users can update own analysis" ON public.analysis
    FOR UPDATE USING ((select auth.uid()) = user_id);
CREATE POLICY "Users can delete own analysis" ON public.analysis
    FOR DELETE USING ((select auth.uid()) = user_id);

-- ============================================================
-- News Verification Module
-- ============================================================
CREATE TABLE IF NOT EXISTS public.news_analyses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    input_type TEXT NOT NULL,
    input_content TEXT NOT NULL,
    source_url TEXT,
    title TEXT,
    status TEXT NOT NULL DEFAULT 'queued',
    progress INTEGER NOT NULL DEFAULT 0,
    current_agent TEXT,
    verdict TEXT,
    confidence NUMERIC,
    trust_score DOUBLE PRECISION DEFAULT 0,
    authenticity_score DOUBLE PRECISION DEFAULT 0,
    authenticity_level TEXT DEFAULT 'unknown',
    risk_level TEXT DEFAULT 'medium',
    claim_count INTEGER DEFAULT 0,
    evidence_count INTEGER DEFAULT 0,
    executive_summary TEXT,
    error_message TEXT,
    metadata JSONB DEFAULT '{}',
    processing_time_ms BIGINT DEFAULT 0,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.news_agent_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id UUID NOT NULL REFERENCES public.news_analyses(id) ON DELETE CASCADE,
    agent_name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    confidence NUMERIC DEFAULT 0,
    processing_time_ms BIGINT DEFAULT 0,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    findings JSONB DEFAULT '[]',
    evidence JSONB DEFAULT '[]',
    raw_output JSONB,
    processed_output JSONB,
    error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.news_evidence (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id UUID NOT NULL REFERENCES public.news_analyses(id) ON DELETE CASCADE,
    agent_name TEXT,
    evidence_type TEXT DEFAULT 'text',
    key TEXT,
    value TEXT,
    reference_url TEXT,
    claim TEXT,
    source TEXT,
    url TEXT,
    excerpt TEXT,
    confidence NUMERIC DEFAULT 0.5,
    credibility NUMERIC DEFAULT 0.5,
    supports_claim BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.news_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id UUID NOT NULL UNIQUE REFERENCES public.news_analyses(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    report_data JSONB DEFAULT '{}',
    report_type TEXT DEFAULT 'json',
    executive_summary TEXT,
    recommendations JSONB DEFAULT '[]',
    claims JSONB DEFAULT '[]',
    evidence JSONB DEFAULT '[]',
    sources JSONB DEFAULT '[]',
    bias_analysis JSONB DEFAULT '{}',
    context_analysis JSONB DEFAULT '{}',
    ai_explanation TEXT,
    processing_time_ms BIGINT DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_news_analyses_user_id ON public.news_analyses(user_id);
CREATE INDEX IF NOT EXISTS idx_news_analyses_status ON public.news_analyses(status);
CREATE INDEX IF NOT EXISTS idx_news_analyses_created_at ON public.news_analyses(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_news_agent_results_analysis_id ON public.news_agent_results(analysis_id);
CREATE INDEX IF NOT EXISTS idx_news_evidence_analysis_id ON public.news_evidence(analysis_id);
CREATE INDEX IF NOT EXISTS idx_news_reports_analysis_id ON public.news_reports(analysis_id);
CREATE INDEX IF NOT EXISTS idx_news_reports_user_id ON public.news_reports(user_id);

ALTER TABLE public.news_analyses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.news_agent_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.news_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.news_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own news analyses" ON public.news_analyses
    FOR SELECT USING ((select auth.uid()) = user_id);
CREATE POLICY "Users can insert own news analyses" ON public.news_analyses
    FOR INSERT WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY "Users can update own news analyses" ON public.news_analyses
    FOR UPDATE USING ((select auth.uid()) = user_id);
CREATE POLICY "Users can delete own news analyses" ON public.news_analyses
    FOR DELETE USING ((select auth.uid()) = user_id);

CREATE POLICY "Users can view agent results of own analyses" ON public.news_agent_results
    FOR SELECT USING (EXISTS (SELECT 1 FROM public.news_analyses WHERE news_analyses.id = news_agent_results.analysis_id AND news_analyses.user_id = (select auth.uid())));

CREATE POLICY "Users can view evidence of own analyses" ON public.news_evidence
    FOR SELECT USING (EXISTS (SELECT 1 FROM public.news_analyses WHERE news_analyses.id = news_evidence.analysis_id AND news_analyses.user_id = (select auth.uid())));

CREATE POLICY "Users can view own news reports" ON public.news_reports
    FOR SELECT USING ((select auth.uid()) = user_id);
