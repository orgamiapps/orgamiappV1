#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="orgami-66nxok"
PROJECT_NUMBER="951311475019"
POOL_ID="github-pool"
PROVIDER_ID="github-provider"
GH_REPO="orgamiapps/orgamiappV1"
SA_ID="sa-deployer"
SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud services enable iamcredentials.googleapis.com iam.googleapis.com sts.googleapis.com --project "$PROJECT_ID"

gcloud iam service-accounts create "$SA_ID" \
  --description="CI deployer for Firestore indexes" \
  --display-name="CI Deployer" \
  --project "$PROJECT_ID" || true
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role "roles/datastore.indexAdmin"

gcloud iam workload-identity-pools create "$POOL_ID" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions Pool" || true

gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL_ID" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --issuer-uri="https://token.actions.githubusercontent.com" || true

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project "$PROJECT_ID" \
  --role "roles/iam.workloadIdentityUser" \
  --member "principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GH_REPO}"

echo
echo "Use this in your workflow as workload_identity_provider:"
echo "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"
