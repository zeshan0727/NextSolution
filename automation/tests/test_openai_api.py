import json
import os
import unittest
from unittest.mock import patch

from automation.openai_api import OpenAIAPIError, structured_response
from automation.schemas import ARTICLE_SCHEMA


class FakeResponse:
    def __init__(self, payload: dict) -> None:
        self.payload = json.dumps(payload).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback) -> None:
        return None

    def read(self) -> bytes:
        return self.payload


class OpenAIClientTests(unittest.TestCase):
    def test_article_schema_enforces_deterministic_collection_limits(self) -> None:
        self.assertEqual(ARTICLE_SCHEMA["properties"]["what_it_does"]["minItems"], 5)
        self.assertEqual(ARTICLE_SCHEMA["properties"]["faq"]["minItems"], 4)
        self.assertEqual(ARTICLE_SCHEMA["properties"]["youtube_chapters"]["maxItems"], 9)
        self.assertEqual(ARTICLE_SCHEMA["properties"]["youtube_title"]["maxLength"], 100)

    def test_request_is_structured_stateless_and_bounded(self) -> None:
        response_payload = {
            "id": "resp_test",
            "model": "gpt-5.6-luna",
            "status": "completed",
            "usage": {"input_tokens": 10, "output_tokens": 5},
            "output": [
                {
                    "type": "message",
                    "content": [
                        {"type": "output_text", "text": "{\"approved\":true}"}
                    ],
                }
            ],
        }
        schema = {
            "type": "object",
            "properties": {"approved": {"type": "boolean"}},
            "required": ["approved"],
            "additionalProperties": False,
        }
        with patch(
            "automation.openai_api.urlopen", return_value=FakeResponse(response_payload)
        ) as mocked:
            result, metadata = structured_response(
                model="gpt-5.6-luna",
                instructions="Return a verdict.",
                input_payload={"fact": "value"},
                schema_name="verdict",
                schema=schema,
                max_output_tokens=100,
                api_key="unit-key",
                retries=0,
            )
        request = mocked.call_args.args[0]
        body = json.loads(request.data.decode("utf-8"))
        self.assertEqual(result, {"approved": True})
        self.assertEqual(metadata["response_id"], "resp_test")
        self.assertFalse(body["store"])
        self.assertEqual(body["max_output_tokens"], 100)
        self.assertEqual(body["text"]["format"]["type"], "json_schema")
        self.assertTrue(body["text"]["format"]["strict"])
        self.assertEqual(request.get_header("Authorization"), "Bearer unit-key")

    def test_missing_api_key_stops_before_network(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(OpenAIAPIError):
                structured_response(
                    model="gpt-5.6-luna",
                    instructions="test",
                    input_payload={},
                    schema_name="empty",
                    schema={"type": "object", "properties": {}, "required": [], "additionalProperties": False},
                    max_output_tokens=20,
                    retries=0,
                )


if __name__ == "__main__":
    unittest.main()
