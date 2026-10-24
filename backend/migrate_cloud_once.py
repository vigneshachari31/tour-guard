"""One-time, fail-closed migration into an EMPTY Supabase public schema.

Run from repository root with --execute after stopping source app writes.
Secrets stay in local backend/.env; backup stays outside the repository.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import psycopg
from psycopg import sql
from dotenv import dotenv_values
from sqlalchemy.engine import make_url

TABLES = ('alembic_version', 'audit_logs', 'hazard_zones', 'rescue_assignments',
          'responders', 'risk_assessment_logs', 'sos_event_history', 'sos_events',
          'tourist_hazard_reports', 'trip_location_updates', 'trips',
          'user_profiles', 'users')
BIN = Path('C:/Program Files/PostgreSQL/18/bin')


def run(args, env, data=None):
    result = subprocess.run(args, env=env, input=data, capture_output=True, timeout=240)
    if result.returncode:
        # SQL diagnostics may include private row contents: never print stderr.
        raise RuntimeError('Database utility failed; diagnostics withheld to protect private data')
    return result.stdout


def fingerprint(db, table):
    query = sql.SQL("SELECT count(*), md5(COALESCE(string_agg(row_text, E'\\n' ORDER BY md5(row_text)), '')) FROM (SELECT row_to_json(t)::text AS row_text FROM public.{} t) rows").format(sql.Identifier(table))
    return db.execute(query).fetchone()


def main():
    if sys.argv[1:] != ['--execute']:
        raise RuntimeError('Explicit --execute required; stop source writes first')
    cfg = dotenv_values('backend/.env')
    u = make_url(cfg['DATABASE_URL'])
    source = dict(host=u.host, port=u.port or 5432, dbname=u.database,
                  user=u.username, password=u.password, connect_timeout=15)
    target = dict(host='aws-0-ap-northeast-1.pooler.supabase.com', port=5432,
                  dbname='postgres', user='postgres.jpzldvgrghvkbjvhmmkt',
                  password=cfg['SUPABASE_DB_PASSWORD'], sslmode='require', connect_timeout=15)
    if source['host'] == target['host']:
        raise RuntimeError('Source must differ from target')
    with psycopg.connect(**target) as cloud:
        cloud.execute('SET TRANSACTION READ ONLY')
        if cloud.execute("SELECT 1 FROM pg_tables WHERE schemaname='public'").fetchone():
            raise RuntimeError('Destination is not empty; refusing to overwrite')
    with psycopg.connect(**source) as local:
        local.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
        local.execute("SET LOCAL timezone='UTC'")
        present = {r[0] for r in local.execute("SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> 'spatial_ref_sys'")}
        if present != set(TABLES):
            raise RuntimeError('Unexpected source tables; review before migration')
        snapshot = local.execute('SELECT pg_export_snapshot()').fetchone()[0]
        expected = {t: fingerprint(local, t) for t in TABLES}
        folder = Path(tempfile.mkdtemp(prefix='tour-guard-migration-', dir=os.environ['LOCALAPPDATA']))
        backup = folder / 'source-before-cloud.dump'
        env = os.environ.copy()
        env.update(PGHOST=source['host'], PGPORT=str(source['port']), PGDATABASE=source['dbname'],
                   PGUSER=source['user'], PGPASSWORD=source['password'], PGCONNECT_TIMEOUT='15')
        base = [str(BIN / 'pg_dump.exe'), '--no-owner', '--no-privileges', '--snapshot', snapshot]
        run(base + ['--format=custom', '--file', str(backup)], env)
        run([str(BIN / 'pg_restore.exe'), '--list', str(backup)], env)
        print('Private backup:', backup, flush=True)
        selection = [arg for t in TABLES for arg in ('--table', 'public.' + t)]
        dump = run(base + ['--format=plain'] + selection, env)
        pre = "SET LOCAL timezone='UTC';\nCREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;\n"
        post = "\nSET LOCAL timezone='UTC';\n"
        for t in TABLES:
            post += f'ALTER TABLE public.{t} ENABLE ROW LEVEL SECURITY;\n'
            post += f'REVOKE ALL ON TABLE public.{t} FROM PUBLIC, anon, authenticated, service_role;\n'
            count, digest = expected[t]
            post += f"DO $check$ BEGIN IF (SELECT count(*) FROM public.{t}) <> {count} OR (SELECT md5(COALESCE(string_agg(row_text, E'\\n' ORDER BY md5(row_text)), '')) FROM (SELECT row_to_json(t)::text AS row_text FROM public.{t} t) rows) <> '{digest}' THEN RAISE EXCEPTION 'Migration verification failed: {t}'; END IF; END $check$;\n"
        post += 'REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, anon, authenticated, service_role;\n'
        post += 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated, service_role;\n'
        post += 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role;\n'
        post += "DO $check$ BEGIN IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename <> 'spatial_ref_sys' AND NOT rowsecurity) THEN RAISE EXCEPTION 'RLS check failed'; END IF; END $check$;\n"
        cloud_env = os.environ.copy()
        cloud_env.update(PGHOST=target['host'], PGPORT='5432', PGDATABASE='postgres',
                         PGUSER=target['user'], PGPASSWORD=target['password'], PGSSLMODE='require', PGCONNECT_TIMEOUT='15')
        print('Importing with atomic verification and API-role access revoked...', flush=True)
        run([str(BIN / 'psql.exe'), '-X', '--single-transaction', '--set', 'ON_ERROR_STOP=1', '--file', '-'],
            cloud_env, pre.encode() + dump + post.encode())
    with psycopg.connect(**target) as cloud:
        cloud.execute('SET TRANSACTION READ ONLY')
        cloud.execute("SET LOCAL timezone='UTC'")
        for t in TABLES:
            if fingerprint(cloud, t) != expected[t]:
                raise RuntimeError('Post-commit verification mismatch')
            print(f'{t}: {expected[t][0]} records verified')
        denied = cloud.execute("SELECT count(*) FROM pg_tables t CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) r(name) WHERE t.schemaname='public' AND t.tablename <> 'spatial_ref_sys' AND has_table_privilege(r.name, quote_ident(t.schemaname)||'.'||quote_ident(t.tablename), 'SELECT,INSERT,UPDATE,DELETE')").fetchone()[0]
        if denied:
            raise RuntimeError('Unexpected API role access; do not deploy')
        print('API roles have no application table access. Migration verified.')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('Migration stopped:', type(exc).__name__, flush=True)
        # Do not print driver errors or connection details containing secrets.
        sys.exit(1)
