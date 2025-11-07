import os

# Superset specific config
ROW_LIMIT = 5000
SUPERSET_WEBSERVER_PORT = 8088

# Flask App Builder configuration
SECRET_KEY = 'your_secret_key_here'

# The SQLAlchemy connection string to your database backend
SQLALCHEMY_DATABASE_URI = 'sqlite:////app/superset_home/superset.db'

# Flask-WTF flag for CSRF
WTF_CSRF_ENABLED = True
WTF_CSRF_TIME_LIMIT = None

# Set this API key to enable Mapbox visualizations
MAPBOX_API_KEY = ''

# Default database connections
DATABASES = {
    'Trino': {
        'engine': 'trino',
        'host': 'trino',
        'port': 8080,
        'database': 'iceberg',
        'username': '',
        'password': '',
        'extra': {
            'engine_params': {
                'connect_args': {
                    'protocol': 'http'
                }
            }
        }
    },
    'PostgreSQL': {
        'engine': 'postgresql',
        'host': 'postgres',
        'port': 5432,
        'database': 'iceberg',
        'username': 'iceberg',
        'password': 'password'
    }
}

# Enable feature flags
FEATURE_FLAGS = {
    'ENABLE_TEMPLATE_PROCESSING': True,
    'DASHBOARD_NATIVE_FILTERS': True,
    'DASHBOARD_CROSS_FILTERS': True,
    'HORIZONTAL_FILTER_BAR': True,
}

# Cache configuration
CACHE_CONFIG = {
    'CACHE_TYPE': 'SimpleCache',
    'CACHE_DEFAULT_TIMEOUT': 300
}

# Async query configuration
RESULTS_BACKEND = None

# Security
TALISMAN_ENABLED = False
