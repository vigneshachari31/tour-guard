# Signup phone mapping

Current requested mapping: signup Mobile Number -> emergency_contact_phone;
Full Name -> full_name. No ECN value is populated; this database has no ECN column.

Updated Flutter signup/service, backend schema/model/endpoint, and regression tests.
Removed phone_number from active ORM and API schemas and from the additive bridge,
so future bridge runs will not recreate it. Existing UI, JWTs and password hashing
are unchanged. Old clients sending phone_number must update to the current request.

Backfill completed: 3 existing phone values copied only where the destination
was NULL. Zero differing non-null values remain. No rows deleted or existing
non-null emergency_contact_phone values overwritten.

Column removal was approved and applied. All source values matched their destination; all 6 accounts were preserved and API readiness returned HTTP 200. The prepared migration
locks users, repeats the NULL-only backfill, verifies all non-null source values
match the destination, and then drops only phone_number WITHOUT CASCADE. Any
conflict or dependency error rolls back the transaction. No Alembic baseline
has been stamped for this existing database.

Prepared files:
- migrations/consolidate_signup_phone.py (default execution only backfills)
- migrations/versions/0003_consolidate_signup_phone.py (column-removal revision)

Live registration returned 201 and saved name and emergency_contact_phone;
login, hashing, Tourist ID and duplicate-email checks passed. One retained test
account: tourguard-check-905fbcdd31eb43f39e84fcad1ecd578b@example.com.
Backend suite: 11 passed, spatial test skipped because its opt-in URL was not set.
Earlier route-restoration reports describe the superseded personal-phone mapping.
