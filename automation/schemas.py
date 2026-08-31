"""Strict JSON schemas shared by the article writer and verifier."""

from __future__ import annotations

from typing import Any


NON_EMPTY_STRING: dict[str, Any] = {"type": "string", "minLength": 1}
EDITORIAL_POINT: dict[str, Any] = {
    "type": "string",
    "minLength": 100,
    "maxLength": 520,
}
INSTALLATION_POINT: dict[str, Any] = {
    "type": "string",
    "minLength": 90,
    "maxLength": 450,
}
FAQ_ANSWER: dict[str, Any] = {
    "type": "string",
    "minLength": 180,
    "maxLength": 850,
}


ARTICLE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "title": {"type": "string", "minLength": 12, "maxLength": 120},
        "meta_description": {
            "type": "string",
            "minLength": 120,
            "maxLength": 165,
        },
        "summary": {
            "type": "string",
            "minLength": 280,
            "maxLength": 1200,
        },
        "what_it_does": {
            "type": "array",
            "items": EDITORIAL_POINT,
            "minItems": 5,
            "maxItems": 8,
        },
        "compatibility_note": {
            "type": "string",
            "minLength": 200,
            "maxLength": 1200,
        },
        "installation_steps": {
            "type": "array",
            "items": INSTALLATION_POINT,
            "minItems": 5,
            "maxItems": 9,
        },
        "safety_notes": {
            "type": "array",
            "items": EDITORIAL_POINT,
            "minItems": 3,
            "maxItems": 6,
        },
        "faq": {
            "type": "array",
            "minItems": 4,
            "maxItems": 7,
            "items": {
                "type": "object",
                "properties": {
                    "question": {
                        "type": "string",
                        "minLength": 15,
                        "maxLength": 180,
                    },
                    "answer": FAQ_ANSWER,
                },
                "required": ["question", "answer"],
                "additionalProperties": False,
            },
        },
        "youtube_title": {"type": "string", "minLength": 12, "maxLength": 100},
        "youtube_hook": {"type": "string", "minLength": 80, "maxLength": 600},
        "youtube_chapters": {
            "type": "array",
            "minItems": 5,
            "maxItems": 9,
            "items": {
                "type": "object",
                "properties": {
                    "heading": {"type": "string", "minLength": 4, "maxLength": 100},
                    "narration": {"type": "string", "minLength": 220, "maxLength": 2200},
                    "visual_instruction": {"type": "string", "minLength": 25, "maxLength": 500},
                },
                "required": ["heading", "narration", "visual_instruction"],
                "additionalProperties": False,
            },
        },
        "youtube_description": {"type": "string", "minLength": 180, "maxLength": 2500},
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
