include env.mk

# You can use bigger machine type n1-highcpu-8 or n1-highcpu-32.
# See https://cloud.google.com/cloud-build/pricing
# for more detail.
ifdef CB_MACHINE_TYPE
	MACHINE_TYPE=--machine-type=$(CB_MACHINE_TYPE)
endif

CR_ARGS = \
	_CR_REGION=$(CR_REGION)

# backend/cloudbuild.yaml
API_SVC_SUBS = $(CR_ARGS) \
	_BACKEND_IMAGE_NAME=$(BACKEND_IMAGE_NAME) \
	_BACKEND_SERVICE_NAME=$(BACKEND_SERVICE_NAME) \
	_GIT_USER_ID=$(GIT_USER_ID) \
	_GIT_REPO_ID=$(GIT_REPO_ID)

API_SVC_TEST_SUBS = _GIT_USER_ID=$(GIT_USER_ID) \
	_GIT_REPO_ID=$(GIT_REPO_ID)

USER_SVC_SUBS = $(CR_ARGS) \
	_USER_SVC_IMAGE=$(USER_SVC_IMAGE_NAME) \
	_USER_SVC_NAME=$(USER_SVC_NAME) \

FRONTEND_E2E_SUBS = _DOMAIN=$(DOMAIN) \
	_ARTIFACTS_LOCATION=$(TEST_ARTIFACTS_LOCATION)

# webui/cloudbuild.yaml
WEBUI_SUBS = _DOMAIN=$(DOMAIN)

# webui/cloudbuild-test.yaml
TEST_WEBUI_SUBS = _ARTIFACTS_LOCATION=$(TEST_ARTIFACTS_LOCATION)

ISTIO_AUTH_TEST_SUBS = $(ISTIO_ARGS) \
	_CLUSTER_LOCATION=$(CLUSTER_LOCATION) \
	_CLUSTER_NAME=$(CLUSTER_NAME)

# Comma separate substitution args
comma := ,
empty :=
space := $(empty) $(empty)
join_subs = $(subst $(space),$(comma),$(1))

# Open API args
CUSTOM_TEMPLATES=backend/templates
OPENAPI_GEN_JAR=openapi-generator-cli-4.3.0.jar
OPENAPI_GEN_URL="https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/4.3.0/$(OPENAPI_GEN_JAR)"
OPENAPI_GEN_SERVER_ARGS=-g go-server -i openapi.yaml -o backend/api-service --api-name-suffix= --git-user-id=$(GIT_USER_ID) --git-repo-id=$(GIT_REPO_ID)/api-service --package-name=service -t $(CUSTOM_TEMPLATES) --additional-properties=sourceFolder=src
OPENAPI_GEN_API_CLIENT_ARGS=-g typescript-angular -i openapi.yaml -o webui/api-client
OPENAPI_GEN_USER_CLIENT_ARGS=-g typescript-angular -i backend/user-service/user-api.yaml -o webui/user-svc-client

CLUSTER_MISSING=$(shell gcloud --project=$(PROJECT_ID) container clusters describe $(CLUSTER_NAME) --zone $(CLUSTER_LOCATION) 2>&1 > /dev/null; echo $$?)

.PHONY: clean delete delete-cluster run-local-webui run-local-backend lint-webui lint test-webui-local test-backend-local test-istio-auth-local build-webui test-webui test-istio-auth build-backend build-infrastructure build-all test cluster jq

## RULES FOR LOCAL DEVELOPMENT
clean:
	rm -rf webui/node_modules webui/api-client
	git clean -d -f -X backend/

/tmp/$(OPENAPI_GEN_JAR):
	wget $(OPENAPI_GEN_URL) -P /tmp/

webui/api-client: /tmp/$(OPENAPI_GEN_JAR) openapi.yaml
	java -jar /tmp/$(OPENAPI_GEN_JAR) generate $(OPENAPI_GEN_API_CLIENT_ARGS)

webui/user-svc-client: /tmp/$(OPENAPI_GEN_JAR) backend/user-service/user-api.yaml
	java -jar /tmp/$(OPENAPI_GEN_JAR) generate $(OPENAPI_GEN_USER_CLIENT_ARGS)

webui/node_modules:
	cd webui && npm ci

backend/api-service/src/api/openapi.yaml: /tmp/$(OPENAPI_GEN_JAR) openapi.yaml $(CUSTOM_TEMPLATES)/*.mustache
	java -jar /tmp/$(OPENAPI_GEN_JAR) generate $(OPENAPI_GEN_SERVER_ARGS)

# Uses port 4200
run-local-webui: webui/api-client
	cd webui && ng serve --proxy-config proxy.conf.json

# Uses port 8080
run-local-backend: backend/api-service/src/api/openapi.yaml
	cd backend/api-service && go run main.go

lint-webui: webui/node_modules
	cd webui && npm run lint

lint: lint-webui

jq:
	@which jq > /dev/null || (echo "'jq' needs to be installed for this target to run. It can be downloaded from https://stedolan.github.io/jq/." && exit 1)

test-backend-local: backend/api-service/src/api/openapi.yaml
	docker stop firestore-emulator 2>/dev/null || true
	docker run --detach --rm -p 9090:9090 --name=firestore-emulator google/cloud-sdk:292.0.0 sh -c \
	 "apt-get install google-cloud-sdk-firestore-emulator && gcloud beta emulators firestore start --host-port=0.0.0.0:9090"
	docker run --network=host jwilder/dockerize:0.6.1 dockerize -timeout=60s -wait=tcp://localhost:9090
	cd backend/api-service/src && FIRESTORE_EMULATOR_HOST=localhost:9090 go test -tags=emulator -v
	docker stop firestore-emulator

test-webui-local: webui/api-client webui/user-svc-client webui/node_modules
	cd webui && npm run test -- --watch=false --browsers=ChromeHeadless

test-webui-e2e-local: webui/api-client webui/user-svc-client webui/node_modules
	cd webui && npm run e2e

test-webui-e2e-prod: webui/api-client webui/user-svc-client webui/node_modules
	cd webui && npm run e2e -- --headless --config baseUrl=https://${DOMAIN}

## RULES FOR CLOUD DEVELOPMENT
GCLOUD_BUILD=gcloud --project=$(PROJECT_ID) builds submit $(MACHINE_TYPE) --verbosity=info .

build-webui:
	$(GCLOUD_BUILD) --config ./webui/cloudbuild.yaml --substitutions $(call join_subs,$(WEBUI_SUBS))

test-apiservice:
	$(GCLOUD_BUILD) --config ./backend/api-service/cloudbuild-test.yaml --substitutions $(call join_subs,$(API_SVC_TEST_SUBS))

test-istio-auth:
	$(GCLOUD_BUILD) --config ./istio-auth/cloudbuild-test.yaml --substitutions $(call join_subs,$(ISTIO_AUTH_TEST_SUBS))

test-webui:
	$(GCLOUD_BUILD) --config ./webui/cloudbuild-test.yaml --substitutions $(call join_subs,$(TEST_WEBUI_SUBS))

test-webui-e2e:
	$(GCLOUD_BUILD) --config ./webui/cypress/cloudbuild.yaml --substitutions $(call join_subs,$(FRONTEND_E2E_SUBS))

build-apiservice:
	$(GCLOUD_BUILD) --config ./backend/api-service/cloudbuild.yaml --substitutions $(call join_subs,$(API_SVC_SUBS))

build-userservice:
	$(GCLOUD_BUILD) --config ./backend/user-service/cloudbuild.yaml --substitutions $(call join_subs,$(USER_SVC_SUBS))

build-infrastructure:
	# $(GCLOUD_BUILD) --config cloudbuild.yaml --substitutions $(call join_subs,$(INFRA_SUBS))

build-infra: build-infrastructure

build-all: build-infrastructure build-apiservice build-userservice build-webui

test: test-apiservice test-webui
