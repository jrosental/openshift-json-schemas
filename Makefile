# Based on:
# - https://github.com/garethr/openshift-json-schema
# - https://cloud.redhat.com/blog/validating-openshift-manifests-in-a-gitops-world

ifeq ($(VERSION),)
VERSION := $(shell oc version -o json | jq -r 'if .openshiftVersion then "v" + .openshiftVersion | split(".")[:2] | join(".") else "master" end')
endif
OPENAPI_SPEC_FILE = openapi/openshift-openapi-spec-$(VERSION).json
PREFIX = https://raw.githubusercontent.com/melmorabity/openshift-json-schemas/main/$(VERSION)/_definitions.json

VIRTUAL_ENV = $(PWD)/.venv
PATH := $(VIRTUAL_ENV)/bin:$(PATH)

define generate_schema =
$(VERSION)$(if $(1),-$(1))/.jsonschema.stamp: $(OPENAPI_SPEC_FILE) $(VIRTUAL_ENV_STAMP)
	openapi2jsonschema -o $$(dir $$@) --expanded --kubernetes $(2) $$<
	openapi2jsonschema -o $$(dir $$@) --kubernetes $(2) $$<
	touch $$@

$(VERSION)$(if $(1),-$(1)): $(VERSION)$(if $(1),-$(1))/.jsonschema.stamp

$(VERSION).0$(if $(1),-$(1))/.jsonschema.stamp: $(VERSION)$(if $(1),-$(1))
	cp -a $$< $$(dir $$@)
	touch $$@

$(VERSION).0$(if $(1),-$(1)): $(VERSION).0$(if $(1),-$(1))/.jsonschema.stamp

SCHEMA_DIRS += $(VERSION)$(if $(1),-$(1)) $(VERSION).0$(if $(1),-$(1))
endef

all: build

$(VIRTUAL_ENV)/bin/python:
	python3 -m venv $(VIRTUAL_ENV)

VIRTUAL_ENV_STAMP = $(VIRTUAL_ENV)/.virtualenv.stamp

$(VIRTUAL_ENV_STAMP): requirements.txt $(VIRTUAL_ENV)/bin/python
	pip install -r $<
	touch $@

virtualenv: $(VIRTUAL_ENV_STAMP)

$(OPENAPI_SPEC_FILE):
	mkdir -p $(dir $(OPENAPI_SPEC_FILE))
	oc get --raw /openapi/v2 >$@

$(eval $(call generate_schema,,--prefix $(PREFIX)))

$(eval $(call generate_schema,standalone,--stand-alone))

$(eval $(call generate_schema,standalone-strict,--stand-alone --strict))

$(eval $(call generate_schema,local,))

build: $(SCHEMA_DIRS)

test: lint

lint:
	pre-commit run --all

pre-commit-update:
	pre-commit autoupdate

clean:
	$(RM) -r $(SCHEMA_DIRS)

mrproper: clean
	$(RM) $(OPENAPI_SPEC_FILE)
	$(RM) -r $(VIRTUAL_ENV)

.PHONY: all build clean lint mrproper pre-commit-update test virtualenv
