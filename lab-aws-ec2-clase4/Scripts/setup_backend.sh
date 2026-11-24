#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-sa-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET_NAME="${BUCKET_NAME:-tfstate-lab-gmt-${ACCOUNT_ID}-${AWS_REGION}}"

echo "Configurando backend S3 idempotente: ${BUCKET_NAME} en ${AWS_REGION}..."

if aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" 2>/dev/null; then
  echo "El bucket ${BUCKET_NAME} ya existe. Verificando configuración..."
else
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  fi
fi

aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --region "${AWS_REGION}" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --region "${AWS_REGION}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --region "${AWS_REGION}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

cat <<EOF > backend.hcl
bucket       = "${BUCKET_NAME}"
key          = "lab-ubuntu2604-gmt/terraform.tfstate"
region       = "${AWS_REGION}"
encrypt      = true
use_lockfile = true
EOF

echo "Backend listo. Archivo generado: backend.hcl"
