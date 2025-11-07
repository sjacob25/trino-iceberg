#!/bin/bash

# Initialize Superset database
superset db upgrade

# Create admin user
superset fab create-admin \
    --username admin \
    --firstname Admin \
    --lastname User \
    --email admin@superset.com \
    --password admin

# Load examples (optional)
# superset load_examples

# Initialize Superset
superset init

echo "Superset initialized successfully!"
echo "Login: admin / admin"
