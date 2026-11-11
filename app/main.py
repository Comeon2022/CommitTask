"""Minimal Meridian evaluation API. Checks are performed for every /health request."""
import os
from flask import Flask, jsonify
import psycopg2
from google.cloud import secretmanager

app = Flask(__name__)

PROJECT_ID = os.environ["PROJECT_ID"]
REGION = os.environ["REGION"]
CANDIDATE = os.environ["CANDIDATE"]
DEPLOYED_COMMIT = os.environ["DEPLOYED_COMMIT"]
DB_HOST = os.environ["DB_HOST"]
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASSWORD_SECRET = os.environ["DB_PASSWORD_SECRET"]
PROVIDER_TOKEN_SECRET = os.environ["PROVIDER_TOKEN_SECRET"]

secret_client = secretmanager.SecretManagerServiceClient()


def read_secret(secret_id: str) -> str:
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
    result = secret_client.access_secret_version(request={"name": name})
    payload = result.payload.data.decode("utf-8")
    if not payload:
        raise ValueError("Empty secret")
    return payload


@app.get("/health")
def health():
    db_status = "error"
    secret_status = "error"

    # Both reads happen on this request. An error remains visible to the caller.
    try:
        provider_token = read_secret(PROVIDER_TOKEN_SECRET)
        if provider_token:
            secret_status = "ok"
    except Exception:
        app.logger.exception("Unable to read provider token from Secret Manager")

    try:
        db_password = read_secret(DB_PASSWORD_SECRET)
        with psycopg2.connect(
            host=DB_HOST,
            port=5432,
            dbname=DB_NAME,
            user=DB_USER,
            password=db_password,
            connect_timeout=5,
            sslmode="require",
        ) as conn:
            with conn.cursor() as cursor:
                cursor.execute("SELECT 1")
                if cursor.fetchone() == (1,):
                    db_status = "ok"
    except Exception:
        app.logger.exception("Database health query failed")

    payload = {
        "candidate": CANDIDATE,
        "commit": DEPLOYED_COMMIT,
        "region": REGION,
        "db": db_status,
        "secret": secret_status,
    }
    status = 200 if db_status == "ok" and secret_status == "ok" else 503
    return jsonify(payload), status
