"""Strict JSON schemas shared by the article writer and verifier."""

from __future__ import annotations

from typing import Any


NON_EMPTY_STRING: dict[str, Any] = {"type": "string", "minLength": 1}


ARTICLE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "title": NON_EMPTY_STRING,
        "meta_description": {
            "type": "string",
            "minLength": 110,
            "maxLength": 165,
        },
        "summary": NON_EMPTY_STRING,
        "what_it_does": {
            "type": "array",
            "items": NON_EMPTY_STRING,
            "minItems": 3,
            "maxItems": 7,
        },
        "compatibility_note": NON_EMPTY_STRING,
        "installation_steps": {
            "type": "array",
            "items": NON_EMPTY_STRING,
            "minItems": 4,
            "maxItems": 8,
        },
        "safety_notes": {
            "type": "array",
            "items": NON_EMPTY_STRING,
            "minItems": 2,
            "maxItems": 6,
        },
        "faq": {
            "type": "array",
            "minItems": 3,
            "maxItems": 6,
            "items": {
                "type": "object",
                "properties": {
                    "question": NON_EMPTY_STRING,
                    "answer": NON_EMPTY_STRING,
                },
                "required": ["question", "answer"],
                "additionalProperties": False,
            },
        },
        "youtube_title": {"type": "string", "minLength": 1, "maxLength": 100},
        "youtube_hook": NON_EMPTY_STRING,
        "youtube_chapters": {
            "type": "array",
            "minItems": 5,
            "maxItems": 9,
            "items": {
                "type": "object",
                "properties": {
                    "heading": NON_EMPTY_STRING,
                    "narration": NON_EMPTY_STRING,
                    "visual_instruction": NON_EMPTY_STRING,
                },
                "required": ["heading", "narration", "visual_instruction"],
                "additionalProperties": False,
            },
        },
        "youtube_description": NON_EMPTY_STRING,
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
