"""Deterministic local risk index; not a calibrated disaster probability."""
import math


def calculate_risk_score(rain_mm: float, verified_hazards_count: int, pending_reports_count: int) -> dict:
    if not math.isfinite(rain_mm) or rain_mm < 0:
        raise ValueError("Rainfall must be finite and non-negative")
    if any(isinstance(n, bool) or not isinstance(n, int) or n < 0
           for n in (verified_hazards_count, pending_reports_count)):
        raise ValueError("Report counts must be non-negative integers")
    weather = 40 if rain_mm > 25 else 20 if rain_mm >= 10 else 0
    verified = 40 if verified_hazards_count >= 3 else 20 if verified_hazards_count else 0
    pending = 20 if pending_reports_count >= 2 else 10 if pending_reports_count else 0
    factors: list[str] = []
    if weather:
        factors.append(f"{'Heavy rain' if weather == 40 else 'Moderate rain'}: {rain_mm:g} mm in the forecast hour (+{weather})")
    if verified:
        factors.append(f"{verified_hazards_count} admin-verified hazard reports within 2 km (+{verified})")
    if pending:
        factors.append(f"{pending_reports_count} recent pending tourist reports within 2 km (+{pending}); not yet verified")
    score = min(weather + verified + pending, 100)
    return {"score": score, "risk_level": "LOW" if score <= 35 else "MODERATE" if score <= 70 else "HIGH", "factors": factors}
