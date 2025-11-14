from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import RedirectResponse
import os, hashlib, time
from .ddb import put_mapping, get_mapping

app = FastAPI()

@app.get("/")
def root():
    return {
        "service": "URL Shortener",
        "version": "1.0.0",
        "endpoints": {
            "health": "GET /healthz - Health check endpoint",
            "shorten": "POST /shorten - Create a short URL (body: {\"url\": \"https://example.com\"})",
            "redirect": "GET /{short_id} - Redirect to original URL"
        },
        "example": {
            "shorten": "POST /shorten with body: {\"url\": \"https://example.com\"}",
            "redirect": "GET /100680ad (will redirect to the original URL)"
        }
    }

@app.get("/healthz")
def health():
    return {"status": "ok", "ts": int(time.time())}

@app.post("/shorten")
async def shorten(req: Request):
    body = await req.json()
    url = body.get("url")
    if not url:
        raise HTTPException(400, "url required")
    short = hashlib.sha256(url.encode()).hexdigest()[:8]
    put_mapping(short, url)
    return {"short": short, "url": url}

@app.get("/{short_id}")
def resolve(short_id: str):
    item = get_mapping(short_id)
    if not item:
        raise HTTPException(404, "not found")
    return RedirectResponse(item["url"])
