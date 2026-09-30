#!/usr/bin/env bash
set -euo pipefail

vault="__KEY_VAULT_NAME__"
token=$(curl -fsS -H Metadata:true 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2019-08-01&resource=https://vault.azure.net' | jq -r .access_token)
secret() {
  curl -fsS -H "Authorization: Bearer $token" "https://$vault.vault.azure.net/secrets/$1?api-version=7.4" | jq -r .value
}

postgres_password=$(secret postgres-password)
umask 077
cat >/opt/millionsend/.env <<EOF
POSTGRES_PASSWORD=$postgres_password
DATABASE_URL=postgres://millionsend:$(printf '%s' "$postgres_password" | jq -sRr @uri)@postgres:5432/millionsend
MASTER_ENCRYPTION_KEY=$(secret master-encryption-key)
BETTER_AUTH_SECRET=$(secret better-auth-secret)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=$(secret aws-access-key-id)
AWS_SECRET_ACCESS_KEY=$(secret aws-secret-access-key)
SNS_TOPIC_ARNS=$(secret sns-topic-arns)
SQS_QUEUE_URL=$(secret sqs-queue-url)
SES_CONFIGURATION_SET=millionsend
APP_BASE_URL=https://mesend.celrys.com
PUBLIC_API_URL=https://api.mesend.celrys.com
ALLOW_SIGNUP=false
EOF

docker compose -f /opt/millionsend/compose.yaml --project-directory /opt/millionsend up -d
