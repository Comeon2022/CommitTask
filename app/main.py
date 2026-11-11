"""Meridian PoC: public health contract with actual IAM-authenticated SQL query."""
import os
import threading

from flask import Flask, jsonify
from google.cloud import secretmanager
from google.cloud.sql.connector import Connector, IPTypes

app = Flask(__name__)
PROJECT_ID = os.environ["PROJECT_ID"]
REGION = os.environ["REGION"]
CANDIDATE = os.environ["CANDIDATE"]
DEPLOYED_COMMIT = os.environ["DEPLOYED_COMMIT"]
INSTANCE_CONNECTION_NAME = os.environ["INSTANCE_CONNECTION_NAME"]
DB_NAME = os.environ["DB_NAME"]
DB_IAM_USER = os.environ["DB_IAM_USER"]
PROVIDER_TOKEN_SECRET = os.environ["PROVIDER_TOKEN_SECRET"]
DB_PASSWORD_SECRET = os.environ["DB_PASSWORD_SECRET"]

_secret_client = secretmanager.SecretManagerServiceClient()
_connector = None
_connector_lock = threading.Lock()


def connector():
    global _connector
    if _connector is None:
        with _connector_lock:
            if _connector is None:
                _connector = Connector(refresh_strategy="LAZY")
    return _connector


def secret_exists_and_nonempty(secret_id: str) -> bool:
    """Read payload using runtime identity; never return/log its contents."""
    secret_name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
    response = _secret_client.access_secret_version(request={"name": secret_name})
    return bool(response.payload.data)

def sql_probe() -> bool:
    # The Cloud SQL Python Connector generates and refreshes temporary IAM tokens.
    # PostgreSQL username is the runtime SA email minus .gserviceaccount.com.
    with connector().connect(
        INSTANCE_CONNECTION_NAME,
        "pg8000",
        user=DB_IAM_USER,
        db=DB_NAME,
        enable_iam_auth=True,
        ip_type=IPTypes.PRIVATE,
        timeout=10,
    ) as connection:
        cursor = connection.cursor()
        try:
            cursor.execute("SELECT 1")
            return cursor.fetchone() == (1,)
        finally:
            cursor.close()


@app.get("/health")
def health():
    secret_ok = False
    db_ok = False

    try:
        # Validate both required secrets on each request. SQL still uses IAM.
                token_ok = secret_exists_and_nonempty(PROVIDER_TOKEN_SECRET)
                password_ok = secret_exists_and_nonempty(DB_PASSWORD_SECRET)
                secret_ok = token_ok and password_ok
    except Exception:
        app.logger.exception("Secret Manager health check failed")

    try:
        db_ok = sql_probe()
    except Exception:
        app.logger.exception("Cloud SQL IAM health check failed")

    return jsonify({
        "candidate": CANDIDATE,
        "commit": DEPLOYED_COMMIT,
        "region": REGION,
        "db": "ok" if db_ok else "error",
        "secret": "ok" if secret_ok else "error",
    }), 200 if db_ok and secret_ok else 503
