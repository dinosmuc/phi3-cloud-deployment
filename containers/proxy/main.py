import os
import secrets

import httpx
from fastapi import FastAPI, Header, HTTPException, Request, Response
from fastapi.responses import StreamingResponse
from starlette.background import BackgroundTask

BACKEND_URL = os.environ.get("BACKEND_URL", "http://127.0.0.1:8000")
PUBLIC_API_KEY = os.environ.get("PUBLIC_API_KEY")
INTERNAL_API_KEY = os.environ.get("INTERNAL_API_KEY")

client = httpx.AsyncClient(base_url=BACKEND_URL, timeout=httpx.Timeout(300.0, connect=10.0))
app = FastAPI()


@app.get("/health")
async def health():
    upstream = await client.get("/health")
    return Response(status_code=upstream.status_code)


@app.post("/v1/chat/completions")
async def chat(request: Request, x_api_key: str = Header(default="")):
    # Constant-time comparison, so the time taken to reject a wrong key does not leak
    # how many leading characters were right. Compared as bytes because compare_digest
    # rejects non-ASCII str. The PUBLIC_API_KEY guard has to come first: without it an
    # unset key would compare equal to a missing header and let every request through.
    if not PUBLIC_API_KEY or not secrets.compare_digest(
        x_api_key.encode("utf-8"), PUBLIC_API_KEY.encode("utf-8")
    ):
        raise HTTPException(401, "Invalid or missing API key.")

    upstream_request = client.build_request(
        "POST", "/v1/chat/completions",
        content=await request.body(),
        headers={
            "Authorization": f"Bearer {INTERNAL_API_KEY}",
            "Content-Type": "application/json",
        },
    )

    upstream = await client.send(upstream_request, stream=True)
    return StreamingResponse(
        upstream.aiter_raw(),
        status_code=upstream.status_code,
        media_type=upstream.headers.get("content-type"),
        background=BackgroundTask(upstream.aclose),
    )
