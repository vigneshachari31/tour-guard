# Free demonstration deployment

Status: deployment files only. No hosted service or migrated database is implied.

The root Dockerfile builds the React admin and serves it from FastAPI at /admin/.
render.yaml requests one free Render web service; it does not create a paid database.
Secrets and database backups are excluded from the Docker build context.

## Preserve existing records before deployment

1. Create a NEW Supabase project on the Free plan. Keep the password private.
2. Disable the Supabase Data API for this project before importing app tables.
   Tour Guard uses direct PostgreSQL connections and its own authentication.
   Its users, SOS locations and medical profiles must not be exposed via an
   automatically generated public database API.
3. Obtain the PostgreSQL Session pooler connection (port 5432) via Connect.
   Store it in a local secret store or enter it directly in Render, not Git/chat.
   Use TLS (sslmode=require). Do not use the transaction pooler for migration.
4. Before copying data, inspect the source PostgreSQL/PostGIS versions, schemas,
   Alembic revision, tables and row counts. Confirm the target has no application
   tables or data. Do not restore over an existing project.
5. Pause source app writes for the final copy. Make a private pg_dump backup with
   a compatible PostgreSQL client. Keep backups outside the Git repository.
   Restore only the application schema/data, without source ownership or ACLs;
   do not overwrite Supabase-managed schemas. Match the PostGIS extension schema
   to the source. Review the restore plan before executing it.
6. Verify all application table counts, foreign keys, sequence values, spatial
   queries and the Alembic revision in the destination. Apply any outstanding
   migrations explicitly using python -m alembic -c backend/alembic.ini upgrade head
   with the destination DATABASE_URL. Do not automatically migrate on web startup.
7. Preserve source database and backup until login, map, incidents, profiles and
   SOS history have been verified against the cloud database. Existing password
   hashes and roles must be retained; users sign in again after the URL changes.

## Render

Push the deployment files to the connected GitHub repository. In Render choose
New > Blueprint, select the repository and confirm the service plan is Free.
Set DATABASE_URL privately to the restored Supabase Session pooler connection
with TLS. Render generates a new JWT_SECRET. Do not copy backend/.env into Git.
The cloud database must be ready before /health/ready passes.

Use https://<service>.onrender.com/admin/ for the admin console. Same-origin
admin requests need no extra CORS entry. For a separately hosted Flutter web app,
set CORS_ORIGINS to a JSON list of its exact HTTPS origin; do not use a wildcard.
Native Android requests do not require browser CORS settings.

## Mobile build and checks

Once the deployed service is healthy, from the repository root:

    flutter build apk --release --dart-define=API_BASE_URL=https://<service>.onrender.com/api/v1

Install build/app/outputs/flutter-apk/app-release.apk on Android test devices.
Use appropriate release signing before public distribution. An APK does not
install on iPhones; iOS distribution requires a separate Apple build/signing flow.

Verify /health/live and /health/ready, existing-account login, admin login,
incident moderation, map/route calls and SOS history using mobile data with
Wi-Fi disabled. Only create clearly identified test SOS records, not real dispatches.
Ensure app errors are readable after a cold start. No production reliability claim.

## Free-tier limitations

Render free services sleep after inactivity; the first request can be delayed.
Supabase free projects can pause for low activity and have storage/usage limits.
Keep independent private backups. This is a demonstration deployment, not an
always-on emergency service. No custom domain, paid upgrade or uptime workaround
is required or authorized by this setup.

References:
- https://render.com/docs/free
- https://render.com/docs/blueprint-spec
- https://supabase.com/pricing
- https://supabase.com/docs/guides/database/connecting-to-postgres
