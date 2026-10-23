# SOS workflow

The tourist sends SOS with fresh GPS. Duplicate submissions while an incident
is OPEN or IN_PROGRESS return the existing incident. Original coordinates remain
unchanged. While signed in and in the foreground, the app submits fresh GPS
every 10 seconds, including accuracy and capture time. Readings older than two
minutes, future readings and out-of-order readings are rejected or ignored.

Admin opens SOS & Rescue, selects Assign responder, chooses an available
responder and writes an action note. After confirming directly with the responder,
the dispatcher records acceptance, departure and arrival in sequence.
These are admin-recorded confirmations, not a separate responder mobile app.
Reassignment resets progress; old assignment requests cannot change the new one.
The tourist sees the assigned responder name, phone and recorded progress.

Resolve closes the incident and releases the responder. Tourist cancellation
requires confirmation and performs the same release, preserving audit history.
The SOS screen and home card refresh every 10 seconds. Offline status remains
unconfirmed; GPS older than 60 seconds is marked stale in incident details.
The app does not contact public emergency services or upload GPS when closed.

GPS_UPDATE and RESPONDER_PROGRESS entries use the existing SOS history table.
No schema migration is required. Original incident location and timestamp remain
available beside the latest SOS GPS reading.

Verification: backend/tests/test_sos_flow.py exercises submission, duplicate
retry, cross-user access, fresh/stale/out-of-order GPS, assignment, ordered
progress, tourist contact visibility, resolution and cancellation.
