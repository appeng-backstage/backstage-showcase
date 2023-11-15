################################################
# Makefile for deploying Backstage #
################################################

IMAGE ?= quay.io/janus-idp/backstage-showcase
IMAGE_TAG ?= latest
DEV_NAMESPACE ?= janus-idp-prod
NAME=janus-idp
HOSTNAME ?=  $(strip $(call get_cluster_addr))
CONFIG_FILE_NAME ?= app-config-openshift.yaml

##########################
# Plugins settings for backstage
##########################

#keycloak
KEYCLOAK_REALM_NAME ?= redhat-external
KEYCLOAK_CLIENT_ID ?= kcm-client
KEYCLOAK_CLIENT_SECRET ?=
KEYCLOAK_BASE_URL ?=

##########################
# Customizable Variables #
##########################
BIN_AWK ?= awk ##@ Set a custom 'awk' binary path if not in PATH
BIN_OC ?= oc ##@ Set a custom 'oc' binary path if not in PATH
BIN_YQ ?= yq ##@ Set a custom 'yq' binary path if not in PATH


#####################
# various functions #
#####################
define get_cluster_addr
	$(shell $(BIN_OC) get routes -n openshift-console console --output=yaml | $(BIN_YQ) '.spec.host' | $(BIN_AWK) '{gsub(/console-openshift-console./, ""); print}')
endef

CONTAINER_ENGINE ?= docker
ifneq (,$(wildcard $(CURDIR)/.docker))
	DOCKER_CONF := $(CURDIR)/.docker
else
	DOCKER_CONF := $(HOME)/.docker
endif

CONFIG_CONTENT=$$(yq e '.app.baseUrl = "https://$(NAME)-$(DEV_NAMESPACE).$(HOSTNAME)"' $(CONFIG_FILE_NAME) | \
	yq e '.backend.baseUrl = "https://$(NAME)-$(DEV_NAMESPACE).$(HOSTNAME)"' - | \
	yq e '.backend.cors.origin = "https://$(NAME)-$(DEV_NAMESPACE).$(HOSTNAME)"' -); \


########################################################
# Makefile section for building and pushing backstage image #
########################################################

.PHONY: image/push
## Build and push the image
image/push:
	${CONTAINER_ENGINE} --config=${DOCKER_CONF} push ${IMAGE}:latest
	${CONTAINER_ENGINE} --config=${DOCKER_CONF} push ${IMAGE}:${IMAGE_TAG}


.PHONY: image/build
## Build the image
image/build:
	${CONTAINER_ENGINE} build --ulimit nofile=16384:65536 --tag ${IMAGE}:${IMAGE_TAG} --tag ${IMAGE}:latest .

########################################################
# Makefile section for deploying backstage using openshift template #
########################################################

PARAMS = -f deploy/template/dev-template.yaml
PARAMS += -p CONFIG_CONTENT="$(CONFIG_CONTENT)"
PARAMS += -p IMAGE=$(IMAGE)
PARAMS += -p IMAGE_TAG=$(IMAGE_TAG)
PARAMS += -p DEV_NAMESPACE=$(DEV_NAMESPACE)
PARAMS += -p HOSTNAME=$(HOSTNAME)

# Github Authentication and integration
PARAMS += -p GITHUB_CLIENT_ID=4b2866ec3b47c658fa46
PARAMS += -p GITHUB_CLIENT_SECRET=2608654ee3492a5305044ad7aa88a13242cba26e
PARAMS += -p GITHUB_ACCESS_TOKEN=test

#keyclaok
PARAMS += -p KEYCLOAK_REALM_NAME=redhat-external
PARAMS += -p KEYCLOAK_CLIENT_ID=redhat-external
PARAMS += -p KEYCLOAK_CLIENT_SECRET=redhat-external
PARAMS += -p KEYCLOAK_BASE_URL=redhat-external

.PHONY: template/apply
template/apply:
	@if ! oc get project $(DEV_NAMESPACE) >/dev/null 2>&1; then \
		oc new-project $(DEV_NAMESPACE); \
		oc process $(PARAMS) | oc create --save-config -n $(DEV_NAMESPACE) -f -; \
	else \
		oc process $(PARAMS) | oc apply -n $(DEV_NAMESPACE) -f -; \
	fi

.PHONY: template/clean
template/clean:
	oc process -f deploy/template/dev-template.yaml -p DEV_NAMESPACE=$(DEV_NAMESPACE)  | oc -n $(DEV_NAMESPACE) delete -f -
