"""Minimal Responses API client using only the Python standard library."""

from __future__ import annotations

import json
import os
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


API_URL = "https://api.openai.com/v1/responses"


class OpenAIAPIError(RuntimeError):
    """A bounded, user-safe API error."""


def _output_text(response: dict[str, Any]) -> str:
    values: list[str] = []
    for output in response.get("output", []):
        if not isinstance(output, dict) or output.get("type") != "message":
            continue
        for content in output.get("content", []):
            if not isinstance(content, dict):
                continue
            if content.get("type") == "refusal":
                raise OpenAIAPIError(f"model refusal: {content.get('refusal', 'unspecified')}")
            if content.get("type") == "output_text" and isinstance(content.get("text"), str):
                values.append(content["text"])
    if not values:
        raise OpenAIAPIError("response did not contain output text")
    return "".join(values)


def structured_response(
    *,
    model: str,
    instructions: str,
    input_payload: dict[str, Any],
    schema_name: str,
    schema: dict[str, Any],
    max_output_tokens: int,
    api_key: str | None = None,
    timeout: float = 90,
    retries: int = 2,
) -> tuple[dict[str, Any], dict[str, Any]]:
    key = api_key or os.environ.get("OPENAI_API_KEY", "")
    if not key:
        raise OpenAIAPIError(
            "OPENAI_API_KEY is unavailable; add it as a GitHub Actions encrypted secret"
        )
    request_payload = {
        "model": model,
        "store": False,
        "reasoning": {"effort": "low"},
        "max_output_tokens": max_output_tokens,
        "instructions": instructions,
        "input": json.dumps(input_payload, ensure_ascii=False, sort_keys=True),
        "text": {
            "format": {
                "type": "json_schema",
                "name": schema_name,
                "strict": True,
                "schema": schema,
            }
        },
    }
    body = json.dumps(request_payload).encode("utf-8")
    last_error = "unknown API error"
    for attempt in range(retries + 1):
        request = Request(
            API_URL,
            data=body,
            method="POST",
            headers={
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
                "User-Agent": "NextSolutionDraftWriter/0.1",
            },
        )
        try:
            with urlopen(request, timeout=timeout) as response:
                payload = json.loads(response.read().decode("utf-8"))
            if payload.get("status") == "incomplete":
                raise OpenAIAPIError("model response was incomplete")
            text = _output_text(payload)
            structured = json.loads(text)
            if not isinstance(structured, dict):
                raise OpenAIAPIError("structured response was not an object")
            metadata = {
                "response_id": payload.get("id"),
                "model": payload.get("model", model),
                "usage": payload.get("usage", {}),
            }
            return structured, metadata
        except HTTPError as exc:
            error_body = exc.read(2048).decode("utf-8", errors="replace")
            last_error = f"HTTP {exc.code}: {error_body[:500]}"
            if exc.code not in {408, 409, 429, 500, 502, 503, 504}:
                break
        except (URLError, TimeoutError, json.JSONDecodeError, OpenAIAPIError) as exc:
            last_error = str(exc)
            if isinstance(exc, OpenAIAPIError) or isinstance(exc, json.JSONDecodeError):
                break
        if attempt < retries:
            time.sleep(2**attempt)
    raise OpenAIAPIError(last_error)
