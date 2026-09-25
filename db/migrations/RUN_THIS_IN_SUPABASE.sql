-- VisionX Database Migration: Create analysis tables
-- Creates tables for the multi-agent forensic analysis pipeline

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Analysis Jobs
CREATE TABLE analysis_jobs (
    id VARCHAR(36) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    user_id VARCHAR(36) NOT NULL,
    module_type VARCHAR(32) NOT NULL DEFAULT 'image',
    input_type VARCHAR(32),
    input_content TEXT,
    source_url VARCHAR(2048),
    title VARCHAR(255),
    status VARCHAR(32) DEFAULT 'pending',
    progress INTEGER DEFAULT 0,
    current_agent VARCHAR(128),
    current_stage VARCHAR(64),
    estimated_duration INTEGER DEFAULT 120,
    overall_confidence FLOAT,
    overall_verdict VARCHAR(64),
    risk_level VARCHAR(32) DEFAULT 'medium',
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    extra_metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_jobs_user_id ON analysis_jobs(user_id);
CREATE INDEX idx_jobs_status ON analysis_jobs(status);
CREATE INDEX idx_jobs_module_type ON analysis_jobs(module_type);
CREATE INDEX idx_jobs_created_at ON analysis_jobs(created_at);

-- Agent Results
CREATE TABLE agent_results (
    id VARCHAR(36) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    analysis_id VARCHAR(36) NOT NULL REFERENCES analysis_jobs(id) ON DELETE CASCADE,
    agent_name VARCHAR(128) NOT NULL,
    agent_order INTEGER DEFAULT 0,
    agent_group INTEGER DEFAULT 1,
    handler VARCHAR(128),
    status VARCHAR(32) DEFAULT 'pending',
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    duration_ms FLOAT DEFAULT 0.0,
    confidence FLOAT DEFAULT 0.0,
    reasoning TEXT,
    summary TEXT,
    raw_output JSONB DEFAULT '{}',
    evidence JSONB DEFAULT '{}',
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    is_critical BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_agent_result_analysis ON agent_results(analysis_id);
CREATE INDEX idx_agent_result_name ON agent_results(agent_name);

-- Agent Logs
CREATE TABLE agent_logs (
    id VARCHAR(36) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    analysis_id VARCHAR(36) NOT NULL REFERENCES analysis_jobs(id) ON DELETE CASCADE,
    agent_name VARCHAR(128),
    level VARCHAR(16) DEFAULT 'info',
    message TEXT NOT NULL,
    correlation_id VARCHAR(36),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_log_analysis ON agent_logs(analysis_id);
CREATE INDEX idx_log_timestamp ON agent_logs(timestamp);

-- Evidence Items
CREATE TABLE evidence_items (
    id VARCHAR(36) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    analysis_id VARCHAR(36) NOT NULL REFERENCES analysis_jobs(id) ON DELETE CASCADE,
    agent_name VARCHAR(128) NOT NULL,
    evidence_type VARCHAR(64) NOT NULL,
    key VARCHAR(255) NOT NULL,
    value TEXT,
    reference_url VARCHAR(2048),
    confidence FLOAT DEFAULT 0.0,
    is_exculpatory BOOLEAN DEFAULT FALSE,
    is_inculpatory BOOLEAN DEFAULT FALSE,
    extra_metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_evidence_analysis ON evidence_items(analysis_id);
CREATE INDEX idx_evidence_agent ON evidence_items(agent_name);

-- Uploads
CREATE TABLE uploads (
    id VARCHAR(36) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    user_id VARCHAR(36) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    storage_path VARCHAR(2048) NOT NULL,
    public_url VARCHAR(2048),
    mime_type VARCHAR(128),
    file_size BIGINT,
    status VARCHAR(32) DEFAULT 'completed',
    extra_metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_uploads_user_id ON uploads(user_id);
CREATE INDEX idx_uploads_created_at ON uploads(created_at);

-- Reports (main reports table for user-facing reports)
CREATE TABLE IF NOT EXISTS reports (
    id VARCHAR(36) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    user_id VARCHAR(36) NOT NULL,
    analysis_id VARCHAR(36) NOT NULL REFERENCES analysis_jobs(id) ON DELETE CASCADE,
    upload_id VARCHAR(36) REFERENCES uploads(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    trust_score INTEGER,
    authenticity_status VARCHAR(64) DEFAULT 'unknown',
    risk_level VARCHAR(32) DEFAULT 'medium',
    verdict VARCHAR(64),
    report_data JSONB DEFAULT '{}',
    pdf_url VARCHAR(2048),
    pdf_path VARCHAR(1024),
    download_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE incidents (
    id VARCHAR(36) PRIMARY KEY DEFAULT uuid_generate_v4()::text,
    user_id VARCHAR(36) NOT NULL,
    analysis_id VARCHAR(36) REFERENCES analysis_jobs(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    reason TEXT,
    severity VARCHAR(32) DEFAULT 'medium',
    trust_score INTEGER,
    status VARCHAR(32) DEFAULT 'open',
    resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_incidents_user_id ON incidents(user_id);
CREATE INDEX idx_incidents_analysis_id ON incidents(analysis_id);
CREATE INDEX idx_incidents_created_at ON incidents(created_at);
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
-- Video Analysis Module - Complete Schema
-- Follows Evidence-First architecture like News Verification

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Main video analyses table
CREATE TABLE IF NOT EXISTS public.video_analyses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    input_type TEXT NOT NULL,  -- upload, url, youtube
    input_content TEXT NOT NULL,  -- video URL or file path
    source_url TEXT,
    title TEXT,
    status TEXT NOT NULL DEFAULT 'queued',  -- queued, processing, completed, failed
    progress INTEGER NOT NULL DEFAULT 0,
    trust_score NUMERIC,
    authenticity_score NUMERIC,
    authenticity_level TEXT,
    risk_level TEXT,
    verdict TEXT,
    confidence NUMERIC,
    metadata JSONB,
    executive_summary TEXT,
    error_message TEXT,
    processing_time_ms BIGINT,
    claim_count INTEGER,
    evidence_count INTEGER,
    frame_count INTEGER,
    audio_duration_seconds NUMERIC,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Video frames table
CREATE TABLE IF NOT EXISTS public.video_frames (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id UUID NOT NULL,
    frame_number INTEGER NOT NULL,
    timestamp_seconds NUMERIC NOT NULL,
    frame_path TEXT,
    thumbnail_path TEXT,
    scene_change BOOLEAN DEFAULT FALSE,
    motion_score NUMERIC,
    ocr_text TEXT,
    objects_detected JSONB,
    faces_detected JSONB,
    deepfake_score NUMERIC,
    manipulation_indicators JSONB,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Video evidence table
CREATE TABLE IF NOT EXISTS public.video_evidence (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id UUID NOT NULL,
    agent_name TEXT NOT NULL,
    evidence_type TEXT NOT NULL,  -- frame, audio, ocr, deepfake, external
    key TEXT NOT NULL,
    value TEXT,
    reference_url TEXT,
    confidence NUMERIC,
    claim TEXT,
    source TEXT,
    url TEXT,
    excerpt TEXT,
    credibility NUMERIC,
    supports_claim BOOLEAN DEFAULT TRUE,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Video audio table
CREATE TABLE IF NOT EXISTS public.video_audio (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id UUID NOT NULL,
    audio_path TEXT,
    transcript TEXT,
    language_detected TEXT,
    confidence NUMERIC,
    speaker_segments JSONB,
    silence_periods JSONB,
    audio_manipulation_indicators JSONB,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Video reports table
CREATE TABLE IF NOT EXISTS public.video_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id UUID NOT NULL,
    user_id UUID NOT NULL,
    report_data JSONB,
    report_type TEXT DEFAULT 'json',
    executive_summary TEXT,
    executive_summary_short TEXT,
    recommendations JSONB,
    claims JSONB,
    evidence JSONB,
    sources JSONB,
    frame_analysis JSONB,
    ocr_findings JSONB,
    audio_findings JSONB,
    deepfake_findings JSONB,
    bias_analysis JSONB,
    context_analysis JSONB,
    ai_explanation TEXT,
    processing_time_ms BIGINT,
    pdf_path TEXT,
    pdf_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Video agent results table
CREATE TABLE IF NOT EXISTS public.video_agent_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id UUID NOT NULL,
    agent_name TEXT NOT NULL,
    agent_order INTEGER,
    status TEXT,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    duration_ms NUMERIC,
    confidence NUMERIC,
    reasoning TEXT,
    summary TEXT,
    raw_output JSONB,
    evidence JSONB,
    error_message TEXT,
    retry_count INTEGER,
    findings JSONB,
    processing_time_ms BIGINT,
    processed_output JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Foreign Keys
ALTER TABLE public.video_frames
    ADD CONSTRAINT fk_video_frames_analysis
    FOREIGN KEY (analysis_id)
    REFERENCES public.video_analyses(id)
    ON DELETE CASCADE;

ALTER TABLE public.video_evidence
    ADD CONSTRAINT fk_video_evidence_analysis
    FOREIGN KEY (analysis_id)
    REFERENCES public.video_analyses(id)
    ON DELETE CASCADE;

ALTER TABLE public.video_audio
    ADD CONSTRAINT fk_video_audio_analysis
    FOREIGN KEY (analysis_id)
    REFERENCES public.video_analyses(id)
    ON DELETE CASCADE;

ALTER TABLE public.video_reports
    ADD CONSTRAINT fk_video_reports_analysis
    FOREIGN KEY (analysis_id)
    REFERENCES public.video_analyses(id)
    ON DELETE CASCADE;

ALTER TABLE public.video_agent_results
    ADD CONSTRAINT fk_video_agent_results_analysis
    FOREIGN KEY (analysis_id)
    REFERENCES public.video_analyses(id)
    ON DELETE CASCADE;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_video_analyses_user_id ON public.video_analyses(user_id);
CREATE INDEX IF NOT EXISTS idx_video_analyses_status ON public.video_analyses(status);
CREATE INDEX IF NOT EXISTS idx_video_analyses_created_at ON public.video_analyses(created_at);
CREATE INDEX IF NOT EXISTS idx_video_analyses_module_type ON public.video_analyses(input_type);

CREATE INDEX IF NOT EXISTS idx_video_frames_analysis_id ON public.video_frames(analysis_id);
CREATE INDEX IF NOT EXISTS idx_video_frames_timestamp ON public.video_frames(timestamp_seconds);

CREATE INDEX IF NOT EXISTS idx_video_evidence_analysis_id ON public.video_evidence(analysis_id);
CREATE INDEX IF NOT EXISTS idx_video_evidence_type ON public.video_evidence(evidence_type);

CREATE INDEX IF NOT EXISTS idx_video_audio_analysis_id ON public.video_audio(analysis_id);

CREATE INDEX IF NOT EXISTS idx_video_reports_analysis_id ON public.video_reports(analysis_id);
CREATE INDEX IF NOT EXISTS idx_video_reports_user_id ON public.video_reports(user_id);

CREATE INDEX IF NOT EXISTS idx_video_agent_results_analysis_id ON public.video_agent_results(analysis_id);
CREATE INDEX IF NOT EXISTS idx_video_agent_results_agent_name ON public.video_agent_results(agent_name);

-- Enable Row Level Security
ALTER TABLE public.video_analyses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_frames ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_audio ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_agent_results ENABLE ROW LEVEL SECURITY;

-- RLS Policies for video_analyses
CREATE POLICY "Users can view own video analyses"
    ON public.video_analyses
    FOR SELECT
    USING ((select auth.uid()) = user_id);

CREATE POLICY "Users can insert own video analyses"
    ON public.video_analyses
    FOR INSERT
    WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY "Users can update own video analyses"
    ON public.video_analyses
    FOR UPDATE
    USING ((select auth.uid()) = user_id);

CREATE POLICY "Users can delete own video analyses"
    ON public.video_analyses
    FOR DELETE
    USING ((select auth.uid()) = user_id);

-- RLS Policies for video_frames
CREATE POLICY "Users can view frames of own analyses"
    ON public.video_frames
    FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.video_analyses WHERE video_analyses.id = video_frames.analysis_id AND video_analyses.user_id = (select auth.uid())));

CREATE POLICY "Users can insert frames for own analyses"
    ON public.video_frames
    FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM public.video_analyses WHERE video_analyses.id = video_frames.analysis_id AND video_analyses.user_id = (select auth.uid())));

-- RLS Policies for video_evidence
CREATE POLICY "Users can view evidence of own analyses"
    ON public.video_evidence
    FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.video_analyses WHERE video_analyses.id = video_evidence.analysis_id AND video_analyses.user_id = (select auth.uid())));

CREATE POLICY "Users can insert evidence for own analyses"
    ON public.video_evidence
    FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM public.video_analyses WHERE video_analyses.id = video_evidence.analysis_id AND video_analyses.user_id = (select auth.uid())));

-- RLS Policies for video_audio
CREATE POLICY "Users can view audio of own analyses"
    ON public.video_audio
    FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.video_analyses WHERE video_analyses.id = video_audio.analysis_id AND video_analyses.user_id = (select auth.uid())));

CREATE POLICY "Users can insert audio for own analyses"
    ON public.video_audio
    FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM public.video_analyses WHERE video_analyses.id = video_audio.analysis_id AND video_analyses.user_id = (select auth.uid())));

-- RLS Policies for video_reports
CREATE POLICY "Users can view reports of own analyses"
    ON public.video_reports
    FOR SELECT
    USING ((select auth.uid()) = user_id);

CREATE POLICY "Users can insert reports for own analyses"
    ON public.video_reports
    FOR INSERT
    WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY "Users can update reports of own analyses"
    ON public.video_reports
    FOR UPDATE
    USING ((select auth.uid()) = user_id);

-- RLS Policies for video_agent_results
CREATE POLICY "Users can view agent results of own analyses"
    ON public.video_agent_results
    FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.video_analyses WHERE video_analyses.id = video_agent_results.analysis_id AND video_analyses.user_id = (select auth.uid())));

CREATE POLICY "Users can insert agent results for own analyses"
    ON public.video_agent_results
    FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM public.video_analyses WHERE video_analyses.id = video_agent_results.analysis_id AND video_analyses.user_id = (select auth.uid())));

-- Grant permissions
GRANT ALL ON public.video_analyses TO authenticated;
GRANT ALL ON public.video_frames TO authenticated;
GRANT ALL ON public.video_evidence TO authenticated;
GRANT ALL ON public.video_audio TO authenticated;
GRANT ALL ON public.video_reports TO authenticated;
GRANT ALL ON public.video_agent_results TO authenticated;-- Document Verification Module - Complete Schema
-- Follows the same pattern as the Video Analysis module (20260710_video_module_complete.sql)

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Main document analyses table
CREATE TABLE IF NOT EXISTS public.document_analyses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    original_filename TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    file_size BIGINT,
    content_type TEXT,
    status TEXT NOT NULL DEFAULT 'queued',  -- queued, processing, completed, failed
    progress INTEGER NOT NULL DEFAULT 0,
    trust_score NUMERIC,
    confidence NUMERIC,
    risk_level TEXT,
    verdict TEXT,
    document_type TEXT,
    executive_summary TEXT,
    error_message TEXT,
    processing_time_ms BIGINT,
    page_count INTEGER,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Document evidence table (structural flags, metadata findings, per-page forensics, OCR text)
CREATE TABLE IF NOT EXISTS public.document_evidence (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id UUID NOT NULL,
    agent_name TEXT NOT NULL,
    evidence_type TEXT NOT NULL,  -- structural, metadata, page_forensics, ocr, reasoning, manager_decision
    key TEXT NOT NULL,
    value TEXT,
    confidence NUMERIC,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Document reports table
CREATE TABLE IF NOT EXISTS public.document_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id UUID NOT NULL,
    user_id UUID NOT NULL,
    report_data JSONB,
    report_type TEXT DEFAULT 'json',
    executive_summary TEXT,
    pdf_path TEXT,
    pdf_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Document agent results table
CREATE TABLE IF NOT EXISTS public.document_agent_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id UUID NOT NULL,
    agent_name TEXT NOT NULL,
    agent_order INTEGER,
    status TEXT,
    confidence NUMERIC,
    findings JSONB,
    evidence JSONB,
    error_message TEXT,
    processing_time_ms NUMERIC,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Foreign Keys
ALTER TABLE public.document_evidence
    ADD CONSTRAINT fk_document_evidence_analysis
    FOREIGN KEY (analysis_id)
    REFERENCES public.document_analyses(id)
    ON DELETE CASCADE;

ALTER TABLE public.document_reports
    ADD CONSTRAINT fk_document_reports_analysis
    FOREIGN KEY (analysis_id)
    REFERENCES public.document_analyses(id)
    ON DELETE CASCADE;

ALTER TABLE public.document_agent_results
    ADD CONSTRAINT fk_document_agent_results_analysis
    FOREIGN KEY (analysis_id)
    REFERENCES public.document_analyses(id)
    ON DELETE CASCADE;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_document_analyses_user_id ON public.document_analyses(user_id);
CREATE INDEX IF NOT EXISTS idx_document_analyses_status ON public.document_analyses(status);
CREATE INDEX IF NOT EXISTS idx_document_analyses_created_at ON public.document_analyses(created_at);

CREATE INDEX IF NOT EXISTS idx_document_evidence_analysis_id ON public.document_evidence(analysis_id);
CREATE INDEX IF NOT EXISTS idx_document_evidence_type ON public.document_evidence(evidence_type);

CREATE INDEX IF NOT EXISTS idx_document_reports_analysis_id ON public.document_reports(analysis_id);
CREATE INDEX IF NOT EXISTS idx_document_reports_user_id ON public.document_reports(user_id);

CREATE INDEX IF NOT EXISTS idx_document_agent_results_analysis_id ON public.document_agent_results(analysis_id);
CREATE INDEX IF NOT EXISTS idx_document_agent_results_agent_name ON public.document_agent_results(agent_name);

-- Row Level Security
ALTER TABLE public.document_analyses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_agent_results ENABLE ROW LEVEL SECURITY;

-- RLS Policies for document_analyses
CREATE POLICY "Users can view own document analyses"
    ON public.document_analyses
    FOR SELECT
    USING ((select auth.uid()) = user_id);

CREATE POLICY "Users can insert own document analyses"
    ON public.document_analyses
    FOR INSERT
    WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY "Users can update own document analyses"
    ON public.document_analyses
    FOR UPDATE
    USING ((select auth.uid()) = user_id);

CREATE POLICY "Users can delete own document analyses"
    ON public.document_analyses
    FOR DELETE
    USING ((select auth.uid()) = user_id);

-- RLS Policies for document_evidence
CREATE POLICY "Users can view evidence of own document analyses"
    ON public.document_evidence
    FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.document_analyses WHERE document_analyses.id = document_evidence.analysis_id AND document_analyses.user_id = (select auth.uid())));

CREATE POLICY "Users can insert evidence for own document analyses"
    ON public.document_evidence
    FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM public.document_analyses WHERE document_analyses.id = document_evidence.analysis_id AND document_analyses.user_id = (select auth.uid())));

-- RLS Policies for document_reports
CREATE POLICY "Users can view reports of own document analyses"
    ON public.document_reports
    FOR SELECT
    USING ((select auth.uid()) = user_id);

CREATE POLICY "Users can insert reports for own document analyses"
    ON public.document_reports
    FOR INSERT
    WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY "Users can update reports of own document analyses"
    ON public.document_reports
    FOR UPDATE
    USING ((select auth.uid()) = user_id);

-- RLS Policies for document_agent_results
CREATE POLICY "Users can view agent results of own document analyses"
    ON public.document_agent_results
    FOR SELECT
    USING (EXISTS (SELECT 1 FROM public.document_analyses WHERE document_analyses.id = document_agent_results.analysis_id AND document_analyses.user_id = (select auth.uid())));

CREATE POLICY "Users can insert agent results for own document analyses"
    ON public.document_agent_results
    FOR INSERT
    WITH CHECK (EXISTS (SELECT 1 FROM public.document_analyses WHERE document_analyses.id = document_agent_results.analysis_id AND document_analyses.user_id = (select auth.uid())));

-- Grant permissions
GRANT ALL ON public.document_analyses TO authenticated;
GRANT ALL ON public.document_evidence TO authenticated;
GRANT ALL ON public.document_reports TO authenticated;
GRANT ALL ON public.document_agent_results TO authenticated;
