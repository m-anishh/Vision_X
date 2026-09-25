"""
Provider-agnostic LLM helper for the OpenAI branch of LLM_PROVIDER.
Gemini/Nemotron call sites in each agent/pipeline are left as-is; this module
only adds the OpenAI-compatible path (also used for third-party OpenAI-compatible
proxies via OPENAI_BASE_URL, e.g. AgentRouter).
"""

from __future__ import annotations

import base64
import mimetypes
from typing import Optional

from backend.core.config import settings
from backend.core.logging import get_logger

logger = get_logger(__name__)

try:
    from openai import OpenAI, AsyncOpenAI
    OPENAI_SDK_AVAILABLE = True
except ImportError:
    OPENAI_SDK_AVAILABLE = False


def is_openai_provider() -> bool:
    return (
        OPENAI_SDK_AVAILABLE
        and settings.LLM_PROVIDER == "openai"
        and bool(settings.OPENAI_API_KEY)
    )


def _client() -> Optional["OpenAI"]:
    if not is_openai_provider():
        return None
    return OpenAI(api_key=settings.OPENAI_API_KEY, base_url=settings.OPENAI_BASE_URL or None)


def _async_client() -> Optional["AsyncOpenAI"]:
    if not is_openai_provider():
        return None
    return AsyncOpenAI(api_key=settings.OPENAI_API_KEY, base_url=settings.OPENAI_BASE_URL or None)


def _messages(prompt: str, system_prompt: Optional[str]) -> list:
    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": prompt})
    return messages


def chat_sync(prompt: str, system_prompt: Optional[str] = None) -> Optional[str]:
    client = _client()
    if client is None:
        return None
    try:
        response = client.chat.completions.create(
            model=settings.OPENAI_MODEL,
            messages=_messages(prompt, system_prompt),
        )
        return response.choices[0].message.content
    except Exception as e:
        logger.error(f"OpenAI chat call failed: {e}")
        return None


async def chat_async(prompt: str, system_prompt: Optional[str] = None) -> Optional[str]:
    client = _async_client()
    if client is None:
        return None
    try:
        response = await client.chat.completions.create(
            model=settings.OPENAI_MODEL,
            messages=_messages(prompt, system_prompt),
        )
        return response.choices[0].message.content
    except Exception as e:
        logger.error(f"OpenAI chat call failed: {e}")
        return None


def vision_sync(prompt: str, image_path: str) -> Optional[str]:
    client = _client()
    if client is None:
        return None
    mime_type, _ = mimetypes.guess_type(image_path)
    if not mime_type or not mime_type.startswith("image/"):
        mime_type = "image/jpeg"
    try:
        with open(image_path, "rb") as f:
            b64 = base64.b64encode(f.read()).decode("utf-8")
        response = client.chat.completions.create(
            model=settings.OPENAI_MODEL,
            messages=[{
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": f"data:{mime_type};base64,{b64}"}},
                ],
            }],
        )
        return response.choices[0].message.content
    except Exception as e:
        logger.error(f"OpenAI vision call failed: {e}")
        return None
