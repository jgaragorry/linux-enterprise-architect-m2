#!/usr/bin/env bash
set -euo pipefail

cd /home/gmt/lab-aws-ec2-clase4

AWS_REGION="${AWS_REGION:-sa-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET_NAME="${BUCKET_NAME:-tfstate-lab-gmt-${ACCOUNT_ID}-${AWS_REGION}}"

echo "1/3 Destruyendo recursos gestionados por Terraform..."
if [ -d ".terraform" ] || [ -f "backend.hcl" ]; then
  if [ ! -d ".terraform" ] && [ -f "backend.hcl" ]; then
    terraform init -backend-config=backend.hcl >/dev/null || true
  fi
  terraform destroy -auto-approve || true
fi

echo "2/3 Vaciando versiones y delete markers del bucket S3 ${BUCKET_NAME}..."
if aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" 2>/dev/null; then
  aws s3api list-object-versions \
    --bucket "${BUCKET_NAME}" \
    --region "${AWS_REGION}" \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json \
    | python3 -c '
import json, subprocess, sys
data = json.load(sys.stdin)
objs = data.get("Objects") or []
for i in range(0, len(objs), 1000):
    chunk = json.dumps({"Objects": objs[i:i+1000]})
    subprocess.run(["aws", "s3api", "delete-objects", "--bucket", sys.argv[1], "--region", sys.argv[2], "--delete", chunk], check=True, stdout=subprocess.DEVNULL)
' "${BUCKET_NAME}" "${AWS_REGION}"

  aws s3api list-object-versions \
    --bucket "${BUCKET_NAME}" \
    --region "${AWS_REGION}" \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json \
    | python3 -c '
import json, subprocess, sys
data = json.load(sys.stdin)
objs = data.get("Objects") or []
for i in range(0, len(objs), 1000):
    chunk = json.dumps({"Objects": objs[i:i+1000]})
    subprocess.run(["aws", "s3api", "delete-objects", "--bucket", sys.argv[1], "--region", sys.argv[2], "--delete", chunk], check=True, stdout=subprocess.DEVNULL)
' "${BUCKET_NAME}" "${AWS_REGION}"

  echo "3/3 Eliminando bucket S3 ${BUCKET_NAME}..."
  aws s3api delete-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}"
else
  echo "El bucket ${BUCKET_NAME} no existe o ya fue eliminado."
fi

rm -rf .terraform .terraform.lock.hcl backend.hcl gmt-lab-key.pem gmt-lab-key.pem.bak
echo "Limpieza completa sin residuos en AWS."
