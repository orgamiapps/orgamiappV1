#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="orgami-66nxok"
STAGING_PROJECT_ID="attendus-staging"
PROJECT_NUMBER="951311475019"
POOL_ID="github-pool"
PROVIDER_ID="github-provider"
GH_REPO="orgamiapps/orgamiappV1"
SA_ID="sa-deployer"
SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

# Enable required APIs
gcloud services enable iamcredentials.googleapis.com iam.googleapis.com sts.googleapis.com --project "$PROJECT_ID"

# Create service account
gcloud iam service-accounts create "$SA_ID" \
  --description="CI deployer for Firestore indexes" \
  --display-name="CI Deployer" \
  --project "$PROJECT_ID" || true

# Grant the roles required by the serialized index, Functions, and Hosting gates.
for TARGET_PROJECT in "$PROJECT_ID" "$STAGING_PROJECT_ID"; do
  for ROLE in \
    roles/artifactregistry.admin \
    roles/cloudfunctions.admin \
    roles/cloudscheduler.admin \
    roles/datastore.indexAdmin \
    roles/datastore.user \
    roles/eventarc.admin \
    roles/firebase.viewer \
    roles/firebasehosting.admin \
    roles/iam.serviceAccountUser \
    roles/pubsub.editor \
    roles/run.admin \
    roles/secretmanager.viewer \
    roles/serviceusage.serviceUsageConsumer; do
    gcloud projects add-iam-policy-binding "$TARGET_PROJECT" \
      --member "serviceAccount:${SA_EMAIL}" \
      --role "$ROLE"
  done
done

# Create Workload Identity Pool
gcloud iam workload-identity-pools create "$POOL_ID" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions Pool" || true

# Create GitHub provider
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL_ID" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="attribute.repository=='${GH_REPO}'" \
  --issuer-uri="https://token.actions.githubusercontent.com" || true

gcloud iam workload-identity-pools providers update-oidc "$PROVIDER_ID" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL_ID" \
  --attribute-condition="attribute.repository=='${GH_REPO}'"

# Allow repository to impersonate the service account
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project "$PROJECT_ID" \
  --role "roles/iam.workloadIdentityUser" \
  --member "principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GH_REPO}"

# Output provider resource path for workflow
echo
echo "Use this in your workflow as workload_identity_provider:"
echo "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"
