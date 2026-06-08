#!/bin/bash
set -e

if [ -n "$AWS_ACCESS_KEY_ID" ]; then
    mkdir -p ~/.aws
    cat > ~/.aws/credentials <<- EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
aws_session_token = $AWS_SESSION_TOKEN
EOF
fi

exec "$@"
