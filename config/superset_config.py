# Superset configuration
# Installed to /opt/superset/config/superset_config.py

import os
from datetime import timedelta

# Flask app name
APP_NAME = "Superset"

# Secret key for session signing - CHANGE IN PRODUCTION
SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "superset-default-secret-key-change-me")

# Database connection
SQLALCHEMY_DATABASE_URI = os.environ.get(
    "SUPERSET_DATABASE_URI",
    "postgresql://superset:superset@localhost:5432/superset"
)

# Redis for caching and Celery
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))
REDIS_CELERY_DB = 0
REDIS_RESULTS_DB = 1

# Cache configuration
CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
    "CACHE_KEY_PREFIX": "superset_",
    "CACHE_REDIS_HOST": REDIS_HOST,
    "CACHE_REDIS_PORT": REDIS_PORT,
    "CACHE_REDIS_DB": REDIS_RESULTS_DB,
}

DATA_CACHE_CONFIG = CACHE_CONFIG

# Celery configuration
class CeleryConfig:
    broker_url = f"redis://{REDIS_HOST}:{REDIS_PORT}/{REDIS_CELERY_DB}"
    result_backend = f"redis://{REDIS_HOST}:{REDIS_PORT}/{REDIS_RESULTS_DB}"
    imports = ("superset.sql_lab",)
    task_annotations = {
        "sql_lab.get_sql_results": {"rate_limit": "100/s"},
    }

CELERY_CONFIG = CeleryConfig

# Feature flags
FEATURE_FLAGS = {
    "ENABLE_TEMPLATE_PROCESSING": True,
    "DASHBOARD_NATIVE_FILTERS": True,
    "DASHBOARD_CROSS_FILTERS": True,
    "DASHBOARD_NATIVE_FILTERS_SET": True,
    "ALERT_REPORTS": True,
}

# Web server settings
SUPERSET_WEBSERVER_PORT = 8088
SUPERSET_WEBSERVER_TIMEOUT = 60

# SQL Lab settings
SQLLAB_TIMEOUT = 300
SQLLAB_ASYNC_TIME_LIMIT_SEC = 600

# Upload folder
UPLOAD_FOLDER = "/opt/superset/uploads"

# Enable proxy fix for running behind reverse proxy
ENABLE_PROXY_FIX = True

# Row limit for queries
ROW_LIMIT = 5000
SQL_MAX_ROW = 10000

# Flask-WTF CSRF protection
WTF_CSRF_ENABLED = True
WTF_CSRF_EXEMPT_LIST = []
WTF_CSRF_TIME_LIMIT = 60 * 60 * 24 * 365

# Logging
LOG_FORMAT = "%(asctime)s:%(levelname)s:%(name)s:%(message)s"
LOG_LEVEL = "INFO"
