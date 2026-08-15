import os
import sys
from pathlib import Path

# The proxy reads its keys from the environment at import time, so set them first.
os.environ["PUBLIC_API_KEY"] = "public-test-key"
os.environ["INTERNAL_API_KEY"] = "internal-test-key"

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "containers" / "proxy"))

import httpx
import pytest
from fastapi.testclient import TestClient

import main

SSE_BODY = (
    b'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'
    b"data: [DONE]\n\n"
)


@pytest.fixture
def client():
    with TestClient(main.app) as test_client:
        yield test_client


# Swap the upstream vLLM client for a stub and record what it was sent.
def stub_vllm(body=SSE_BODY, content_type="text/event-stream"):
    seen = {}

    def handler(request):
        seen["authorization"] = request.headers.get("authorization")
        seen["body"] = request.content

        # Yield the body from an async iterator so the response stays streaming,
        # the way vLLM sends it. Plain bytes would arrive already consumed and the
        # proxy could not stream them on.
        async def stream():
            yield body

        return httpx.Response(
            200,
            headers={"content-type": content_type},
            content=stream(),
        )

    main.client = httpx.AsyncClient(
        base_url="http://vllm",
        transport=httpx.MockTransport(handler),
    )

    return seen


def test_missing_api_key_is_rejected(client):
    response = client.post("/v1/chat/completions", json={"messages": []})

    assert response.status_code == 401


def test_wrong_api_key_is_rejected(client):
    response = client.post(
        "/v1/chat/completions",
        headers={"x-api-key": "not-the-key"},
        json={"messages": []},
    )

    assert response.status_code == 401


def test_valid_key_is_swapped_for_the_internal_token(client):
    seen = stub_vllm()

    response = client.post(
        "/v1/chat/completions",
        headers={"x-api-key": "public-test-key"},
        json={"model": "google/gemma-4-E2B-it", "messages": []},
    )

    assert response.status_code == 200
    # vLLM is reached with the internal token; the public key never leaves the proxy.
    assert seen["authorization"] == "Bearer internal-test-key"
    assert b"public-test-key" not in seen["body"]


def test_streamed_response_passes_through_unchanged(client):
    stub_vllm()

    response = client.post(
        "/v1/chat/completions",
        headers={"x-api-key": "public-test-key"},
        json={"messages": []},
    )

    assert response.status_code == 200
    assert response.content == SSE_BODY
    # Starlette appends a charset to text media types; the type itself is kept.
    assert response.headers["content-type"].startswith("text/event-stream")
