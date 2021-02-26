# Configure all these variables for your project/application

# TODO: Replace these values with:
#  - YOUR project id.
#  - YOUR verified custom domain.
PROJECT_ID=project-id
DOMAIN=my-zone.cloud-tutorial.dev

CR_REGION=us-central1

# Parameters for code generation
# These must always match the module declaration in backend/go.mod
# i.e. `module github.com/${GIT_USER_ID}/${GIT_REPO_ID}
GIT_USER_ID=zsxking
GIT_REPO_ID=cloud-run-reference-web-app

# Parameters for e2e testing
# Set this to a valid GCS bucket path within your project
TEST_ARTIFACTS_LOCATION=this.is.not.a.real.bucket

# Cloud DNS managed zone name
MANAGED_ZONE_NAME=$(or $(shell gcloud --project=$(PROJECT_ID) dns managed-zones list --format="value(name)" --filter="dnsName=$(DOMAIN)."), $(shell exit 1))

# Backend service name
BACKEND_IMAGE_NAME=api-service
BACKEND_SERVICE_NAME=$(BACKEND_IMAGE_NAME)

USER_SVC_NAME=user-service
USER_SVC_IMAGE_NAME=$(USER_SVC_NAME)

