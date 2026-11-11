"""Durable runtime records, using the same SQL transaction as user mutations."""
from datetime import datetime, timezone
from uuid import UUID, uuid4

from psycopg.types.json import Jsonb


def timestamp(value):
    return datetime.fromtimestamp(value, timezone.utc)


SESSION_SELECT = """
    SELECT t.access_token_hash, t.refresh_token_hash, s.user_id, s.id AS family,
           t.access_expires_at, t.refresh_expires_at, t.refresh_used_at,
           (s.revoked_at IS NOT NULL OR t.revoked_at IS NOT NULL) AS revoked
    FROM auth_tokens t JOIN auth_sessions s ON s.id=t.session_id
"""


def session_record(row):
    return {"refresh_hash": row["refresh_token_hash"], "user_id": str(row["user_id"]),
            "family": str(row["family"]), "access_until": row["access_expires_at"].timestamp(),
            "refresh_until": row["refresh_expires_at"].timestamp(),
            "used": row["refresh_used_at"] is not None, "revoked": row["revoked"]}


class PostgresRecords:
    def get(self, connection, collection, key):
        if collection in ("objects", "imports"):
            try:
                key = UUID(str(key))
            except ValueError:
                return None
        if collection == "sessions":
            row = connection.execute(SESSION_SELECT + " WHERE t.access_token_hash=%s", (key,)).fetchone()
            return session_record(row) if row else None
        if collection == "objects":
            row = connection.execute("SELECT user_id,kind,body,expires_at FROM api_resources WHERE id=%s", (key,)).fetchone()
            return {"user_id": str(row["user_id"]), "kind": row["kind"], "body": row["body"],
                    "expires": row["expires_at"].timestamp()} if row else None
        if collection == "replays":
            row = connection.execute("SELECT request_hash,result,expires_at FROM api_idempotency "
                                     "WHERE user_id=%s AND scope=%s AND idempotency_key=%s", key).fetchone()
            return {"fingerprint": row["request_hash"], "result": row["result"],
                    "expires": row["expires_at"].timestamp()} if row else None
        if collection == "imports":
            row = connection.execute("SELECT user_id,operation_id FROM recognition_imports WHERE recognition_id=%s", (key,)).fetchone()
            return {"user_id": str(row["user_id"]), "operation_id": str(row["operation_id"])} if row else None
        raise ValueError(f"Unsupported SQL collection: {collection}")

    def put(self, connection, collection, key, value):
        if collection == "sessions":
            # Update an existing pair without constructing a new row: its access
            # token may already be expired, while refresh is still valid. An
            # INSERT ... ON CONFLICT would check new-row lifetime constraints
            # against today's created_at before reaching the conflict handler.
            updated = connection.execute("""
                UPDATE auth_tokens
                SET refresh_used_at=CASE WHEN %s THEN COALESCE(refresh_used_at,clock_timestamp()) ELSE refresh_used_at END,
                    revoked_at=CASE WHEN %s THEN COALESCE(revoked_at,clock_timestamp()) ELSE revoked_at END
                WHERE access_token_hash=%s
            """, (value["used"], value["revoked"], key))
            if updated.rowcount:
                return
            connection.execute("INSERT INTO auth_sessions(id,user_id,expires_at) VALUES (%s,%s,%s) "
                               "ON CONFLICT (id) DO NOTHING",
                               (value["family"], value["user_id"], timestamp(value["refresh_until"])))
            connection.execute("""
                INSERT INTO auth_tokens(id,session_id,access_token_hash,refresh_token_hash,
                                        access_expires_at,refresh_expires_at,refresh_used_at,revoked_at)
                VALUES (%s,%s,%s,%s,%s,%s,CASE WHEN %s THEN clock_timestamp() END,
                       CASE WHEN %s THEN clock_timestamp() END)
            """, (uuid4(), value["family"], key, value["refresh_hash"], timestamp(value["access_until"]),
                  timestamp(value["refresh_until"]), value["used"], value["revoked"]))
        elif collection == "objects":
            connection.execute("""
                INSERT INTO api_resources(id,user_id,kind,body,expires_at) VALUES (%s,%s,%s,%s,%s)
                ON CONFLICT (id) DO UPDATE SET body=EXCLUDED.body
            """, (key, value["user_id"], value["kind"], Jsonb(value["body"]), timestamp(value["expires"])))
        elif collection == "replays":
            connection.execute("""
                INSERT INTO api_idempotency(user_id,scope,idempotency_key,request_hash,result,expires_at)
                VALUES (%s,%s,%s,%s,%s,%s)
                ON CONFLICT (user_id,scope,idempotency_key) DO UPDATE
                SET request_hash=EXCLUDED.request_hash,result=EXCLUDED.result,
                    created_at=clock_timestamp(),expires_at=EXCLUDED.expires_at
            """, (*key, value["fingerprint"], Jsonb(value["result"]), timestamp(value["expires"])))
        elif collection == "imports":
            connection.execute("INSERT INTO recognition_imports(recognition_id,user_id,operation_id) VALUES (%s,%s,%s)",
                               (key, value["user_id"], value["operation_id"]))
        else:
            raise ValueError(f"Unsupported SQL collection: {collection}")

    def delete(self, connection, collection, key):
        if collection == "sessions":
            connection.execute("DELETE FROM auth_tokens WHERE access_token_hash=%s", (key,))
        elif collection == "objects":
            connection.execute("DELETE FROM api_resources WHERE id=%s", (key,))
        elif collection == "replays":
            connection.execute("DELETE FROM api_idempotency WHERE user_id=%s AND scope=%s AND idempotency_key=%s", key)
        else:
            raise ValueError(f"Unsupported SQL collection: {collection}")

    def session_by_refresh(self, connection, refresh_hash):
        row = connection.execute(SESSION_SELECT + " WHERE t.refresh_token_hash=%s", (refresh_hash,)).fetchone()
        return (row["access_token_hash"], session_record(row)) if row else None

    def revoke_family(self, connection, family):
        connection.execute("UPDATE auth_sessions SET revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE id=%s", (family,))

    def purge_sessions(self, connection, now):
        # Retain rotation history while ANY token in the family may still be used.
        connection.execute("""
            DELETE FROM auth_sessions s WHERE s.expires_at<=%s AND NOT EXISTS
            (SELECT 1 FROM auth_tokens t WHERE t.session_id=s.id
             AND (t.access_expires_at>%s OR t.refresh_expires_at>%s))
        """, (timestamp(now),) * 3)

    def purge_resources(self, connection, now):
        connection.execute("UPDATE api_resources SET body='{}'::jsonb WHERE kind='snapshot' AND expires_at<=%s AND body<>'{}'::jsonb",
                           (timestamp(now),))
        connection.execute("DELETE FROM api_resources WHERE kind<>'snapshot' AND expires_at<=%s", (timestamp(now),))
        connection.execute("DELETE FROM api_idempotency WHERE expires_at<=%s", (timestamp(now),))
