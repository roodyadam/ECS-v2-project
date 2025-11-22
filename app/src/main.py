from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import RedirectResponse, HTMLResponse
import os, hashlib, time
from urllib.parse import urlparse
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
            "redirect": "GET /s/{short_id} - Redirect to original URL"
        },
        "example": {
            "shorten": "POST /shorten with body: {\"url\": \"https://example.com\"}",
            "redirect": "GET /s/100680ad (will redirect to the original URL)"
        }
    }

@app.get("/healthz")
def health():
    return {"status": "ok", "ts": int(time.time())}

def _validate_url(url: str) -> str:
    """Validate and normalize URL format"""
    if not url or not isinstance(url, str):
        raise ValueError("URL must be a non-empty string")
    
    url = url.strip()
    
    # Parse the URL
    parsed = urlparse(url)
    
    # Check if URL has a scheme (http/https)
    if not parsed.scheme:
        # If no scheme, try adding https://
        url = f"https://{url}"
        parsed = urlparse(url)
    
    # Validate scheme is http or https
    if parsed.scheme not in ("http", "https"):
        raise ValueError("URL must use http or https protocol")
    
    # Validate that URL has a netloc (domain)
    if not parsed.netloc:
        raise ValueError("URL must contain a valid domain")
    
    # Basic domain validation (must contain at least one dot or be localhost)
    if parsed.netloc != "localhost" and "." not in parsed.netloc:
        raise ValueError("URL must contain a valid domain")
    
    return url

@app.post("/shorten")
async def shorten(req: Request):
    try:
        body = await req.json()
    except Exception:
        raise HTTPException(400, "Invalid JSON in request body")
    
    url = body.get("url")
    if not url:
        raise HTTPException(400, "url required")
    
    try:
        # Validate and normalize URL
        validated_url = _validate_url(url)
    except ValueError as e:
        raise HTTPException(400, str(e))
    
    short = hashlib.sha256(validated_url.encode()).hexdigest()[:8]
    try:
        put_mapping(short, validated_url)
    except RuntimeError as e:
        raise HTTPException(503, f"Service temporarily unavailable: {str(e)}")
    return {"short": short, "url": validated_url}

@app.get("/s/{short_id}")
def resolve(short_id: str):
    try:
        item = get_mapping(short_id)
    except RuntimeError as e:
        raise HTTPException(503, f"Service temporarily unavailable: {str(e)}")
    if not item:
        raise HTTPException(404, "not found")
    return RedirectResponse(item["url"])

@app.on_event("startup")
def _log_routes():
    for _route in app.router.routes:
        try:
            print("route:", _route.path)
        except Exception:
            pass

@app.get("/ui", response_class=HTMLResponse)
def ui():
    return """
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>URL Shortener</title>
    <style>
      body{font-family:system-ui,Segoe UI,Arial;margin:40px;background:#0e1032;color:#eef}
      .card{background:#1a1f4a;border-radius:12px;padding:24px;max-width:720px;margin:0 auto;box-shadow:0 10px 30px rgba(0,0,0,.25)}
      input,button{font-size:16px}
      input{width:100%;padding:12px;border-radius:8px;border:none;outline:none}
      .row{display:flex;gap:12px;margin-top:12px}
      button{padding:12px 16px;border:none;border-radius:8px;background:#6c8cff;color:#fff;cursor:pointer}
      button:hover{background:#5c7cff}
      .out{margin-top:16px}
      code{background:#11163a;padding:2px 6px;border-radius:6px}
      a{color:#9fd}
    </style>
  </head>
  <body>
    <div class="card">
      <h2>POST /shorten</h2>
      <p>Paste a long URL:</p>
      <input id="url" type="url" placeholder="https://example.com/very/long?utm_source=..." required />
      <div class="row">
        <button onclick="shorten()">✨ SHORTEN IT!</button>
      </div>
      <div id="out" class="out"></div>
    </div>

    <script>
      async function shorten(){
        const u = document.getElementById('url').value.trim();
        if(!u) return;
        const r = await fetch('/shorten', {
          method:'POST',
          headers:{'Content-Type':'application/json'},
          body: JSON.stringify({url:u})
        });
        const j = await r.json();
        const out = document.getElementById('out');
        if(j.short){
          const shortUrl = location.origin + '/s/' + j.short;
          out.innerHTML = 'Response:<br><code>' + JSON.stringify(j) + '</code><br><br>'
            + 'Open: <a href=\"' + shortUrl + '\">' + shortUrl + '</a> '
            + '(<a href=\"/s/' + j.short + '/preview\">preview</a>)';
        }else{
          out.textContent = 'Error: ' + JSON.stringify(j);
        }
      }
    </script>
  </body>
</html>
"""

@app.get("/s/{short_id}/preview", response_class=HTMLResponse)
def preview(short_id: str):
    item = get_mapping(short_id)
    dest = item["url"] if item else None
    if not dest:
        return HTMLResponse("<h3>Not found</h3>", status_code=404)
    return f"""
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>Destination</title></head>
  <body style="font-family:system-ui;max-width:700px;margin:40px auto">
    <h2>GET /{short_id}</h2>
    <div style="padding:16px;border:1px solid #ddd;border-radius:8px">
      <strong>HTTP 302/307 Redirect</strong><br>
      Redirecting to: <a href="{dest}">{dest}</a>
    </div>
    <p style="margin-top:16px;color:#555">Powered by AWS ECS Fargate, ALB+WAF, DynamoDB, CodeDeploy.</p>
    <p><a href="{dest}">Continue</a></p>
  </body>
</html>
"""
