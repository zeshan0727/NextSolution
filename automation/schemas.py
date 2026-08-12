"""Strict JSON schemas shared by the article writer and verifier."""

from __future__ import annotations

from typing import Any


ARTICLE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "meta_description": {"type": "string"},
        "summary": {"type": "string"},
        "what_it_does": {"type": "array", "items": {"type": "string"}},
        "compatibility_note": {"type": "string"},
        "installation_steps": {"type": "array", "items": {"type": "string"}},
        "safety_notes": {"type": "array", "items": {"type": "string"}},
        "faq": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "question": {"type": "string"},
                    "answer": {"type": "string"},
                },
                "required": ["question", "answer"],
                "additionalProperties": False,
            },
        },
        "youtube_title": {"type": "string"},
        "youtube_hook": {"type": "string"},
        "youtube_chapters": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "heading": {"type": "string"},
                    "narration": {"type": "string"},
                    "visual_instruction": {"type": "string"},
                },
                "required": ["heading", "narration", "visual_instruction"],
                "additionalProperties": False,
            },
        },
        "youtube_description": {"type": "string"},
    },
    "required": [
        "title",
        "meta_description",
        "summary",
        "what_it_does",
        "compatibility_note",
        "installation_steps",
        "safety_notes",
        "faq",
        "youtube_title",
        "youtube_hook",
        "youtube_chapters",
        "youtube_description",
    ],
    "additionalProperties": False,
}


VERDICT_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "approved": {"type": "boolean"},
        "issues": {"type": "array", "items": {"type": "string"}},
        "unsupported_claims": {"type": "array", "items": {"type": "string"}},
        "notes": {"type": "string"},
    },
    "required": ["approved", "issues", "unsupported_claims", "notes"],
    "additionalProperties": False,
}
