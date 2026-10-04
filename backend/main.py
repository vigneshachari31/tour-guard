"""
main.py – Tour Guard FastAPI Backend
=====================================
Run with:  uvicorn main:app --reload --port 8000
Docs at:   http://localhost:8000/docs
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import risk, hazards, sos

app = FastAPI(
    title="Tour Guard API",
    description=(
        "AI-powered travel risk prediction backend for Tour Guard. "
        "Provides ML risk scores, nearby hazard alerts, and SOS dispatch."
    ),
    version="1.0.0",
)

# ── CORS ─────────────────────────────────────────────────────────────────────
# Allow the Flutter app (any origin during dev) to call this API.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],      # tighten to your domain in production
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(risk.router)
app.include_router(hazards.router)
app.include_router(sos.router)


# ── Health check ──────────────────────────────────────────────────────────────
@app.get("/", tags=["Health"])
def root():
    return {
        "service": "Tour Guard API",
        "status":  "online",
        "version": "1.0.0",
        "endpoints": [
            "POST /api/predict-risk",
            "GET  /api/hazards/nearby?lat=&lon=&radius=",
            "POST /api/sos/dispatch",
            "GET  /api/sos/log",
            "GET  /docs  (Swagger UI)",
        ],
    }

