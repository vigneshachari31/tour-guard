from datetime import datetime, timezone, timedelta
from backend.tests.test_admin import account

def test_complete_sos_flow(client):
    _, _, tourist, tourist_id = account(client)
    _, _, other, _ = account(client)
    _, _, admin, _ = account(client, "admin")
    payload = {"tourist_id": tourist_id, "latitude": 19.04, "longitude": 72.85}
    identity = client.post("/api/v1/sos/trigger", headers=tourist, json=payload).json()["id"]
    assert client.post("/api/v1/sos/trigger", headers=tourist, json=payload).json()["id"] == identity
    loc = f"/api/v1/sos/events/{identity}/location"
    point = {"latitude": 19.05, "longitude": 72.86, "accuracy": 8, "captured_at": datetime.now(timezone.utc).isoformat()}
    assert client.post(loc, headers=other, json=point).status_code == 404
    assert client.post(loc, headers=tourist, json={**point, "captured_at": (datetime.now(timezone.utc)-timedelta(minutes=5)).isoformat()}).status_code == 422
    assert client.post(loc, headers=tourist, json=point).json()["recorded"]
    assert not client.post(loc, headers=tourist, json=point).json()["recorded"]
    responder = client.post("/api/v1/admin/responders", headers=admin, json={"name": "Duty team", "phone": "+12025550123"}).json()
    base = f"/api/v1/admin/incidents/{identity}"
    assert client.post(base+"/assign", headers=admin, json={"responder_id": responder["id"], "note": "Radio assignment"}).status_code == 200
    detail = client.get(base, headers=admin).json()
    assignment = detail["responder"]["assignment_id"]
    assert detail["sos_location"]["latitude"] == 19.05
    assert not detail["sos_location"]["stale"]
    def stage(value, headers=admin):
        return client.patch(base+"/progress", headers=headers, json={"assignment_id": assignment, "stage": value, "note": "Confirmed by radio"})
    assert stage("ACCEPTED", tourist).status_code == 403
    assert stage("ARRIVED").status_code == 409
    for value in ["ACCEPTED", "DEPARTED", "ARRIVED"]:
        assert stage(value).status_code == 200
        event = client.get("/api/v1/sos/events", headers=tourist).json()["events"][0]
        assert event["responder_stage"] == value
        assert event["responder"]["phone"] == "+12025550123"
    assert client.patch(base+"/status", headers=admin, json={"expected_status": "IN_PROGRESS", "status": "RESOLVED", "note": "Tourist reached safety"}).status_code == 200
    assert client.post(loc, headers=tourist, json=point).status_code == 409
    assert stage("ARRIVED").status_code == 409
    assert client.get("/api/v1/sos/events", headers=tourist).json()["events"][0]["workflow_status"] == "RESOLVED"
    new_id = client.post("/api/v1/sos/trigger", headers=tourist, json=payload).json()["id"]
    assert new_id != identity
    assert client.post(f"/api/v1/sos/events/{new_id}/cancel", headers=other).status_code == 404
    assert client.post(f"/api/v1/sos/events/{new_id}/cancel", headers=tourist).status_code == 200
    assert client.get("/api/v1/sos/events", headers=tourist).json()["events"][0]["workflow_status"] == "CANCELLED"
