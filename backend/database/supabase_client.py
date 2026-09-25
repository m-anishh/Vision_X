"""
Supabase Database Client
Provides Supabase client for database and auth operations.
"""

from __future__ import annotations

import os
from typing import Optional

from supabase import create_client, Client


# Module-level client instance
_supabase_client: Optional[Client] = None


def get_supabase_client() -> Client:
    """
    Get or create Supabase client with service role key for backend operations.
    
    Returns:
        Supabase Client instance
    
    Raises:
        RuntimeError: If SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY are not configured
    """
    global _supabase_client
    
    if _supabase_client is None:
        supabase_url = os.getenv("SUPABASE_URL")
        # Use service role key for backend operations
        supabase_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_SERVICE_KEY")
        
        if not supabase_url:
            raise RuntimeError("Supabase not configured. Set SUPABASE_URL environment variable.")
        
        if not supabase_key:
            raise RuntimeError("Supabase not configured. Set SUPABASE_SERVICE_ROLE_KEY or SUPABASE_SERVICE_KEY environment variable.")
        
        _supabase_client = create_client(supabase_url, supabase_key)
    
    return _supabase_client


def reset_client():
    """Reset the client instance (useful for testing)."""
    global _supabase_client
    _supabase_client = None


def create_fresh_supabase_client() -> Client:
    """
    Create a brand-new, uncached Supabase client with the service role key.

    Use this (never the shared get_supabase_client() singleton) for any call
    that establishes a user session on the client - sign_in_with_password,
    sign_up, sign_out, refresh_session. Those calls mutate the client's
    internal auth session, and since postgrest requests on that client then
    use the session's token instead of the service role key, doing this on
    the shared singleton silently downgrades every other admin DB write
    (from any concurrent request) to that user's restricted RLS permissions.
    """
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_SERVICE_KEY")

    if not supabase_url or not supabase_key:
        raise RuntimeError("Supabase not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.")

    return create_client(supabase_url, supabase_key)