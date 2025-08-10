#!/usr/bin/env bash
set -euo pipefail

# EDIT THESE VALUES
PROJECT_ID="orgami-66nxok"
PROJECT_NUMBER="CHANGE_ME"
POOL_ID="GITHUB_POOL"
PROVIDER_ID="GITHUB_PROVIDER"
GH_REPO="your-org/your-repo"  # e.g., username/reponame
SA_ID="sa-deployer"
SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

# Enable required APIs
 gcloud services enable iamcredentials.googleapis.com iam.googleapis.com sts.googleapis.com --project "$PROJECT_ID"

# Create service account
 gcloud iam service-accounts create "$SA_ID" --description="CI deployer for Firestore indexes" --display-name="CI Deployer" --project "$PROJECT_ID" || true

# Grant least-privilege roles (Firestore index admin)
 gcloud projects add-iam-policy-binding "$PROJECT_ID" \
   --member "serviceAccount:${SA_EMAIL}" \
   --role "roles/datastore.indexAdmin"

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
   --issuer-uri="https://token.actions.githubusercontent.com" || true

# Allow repository to impersonate the service account
 gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
   --project "$PROJECT_ID" \
   --role "roles/iam.workloadIdentityUser" \
   --member "principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GH_REPO}"

# Output provider resource path for workflow
 echo "\nUse this in your workflow as workload_identity_provider:"
 echo "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"