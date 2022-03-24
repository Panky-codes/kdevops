# SPDX-License-Identifier: copyleft-next-0.3.1

PROJECT = kdevops
VERSION = 4
PATCHLEVEL = 3
SUBLEVEL = 3
EXTRAVERSION =

all: deps

export KCONFIG_DIR=$(CURDIR)/scripts/kconfig
include $(KCONFIG_DIR)/kconfig.Makefile
include Makefile.subtrees

export KDEVOPS_EXTRA_VARS ?=			extra_vars.yaml
export KDEVOPS_PLAYBOOKS_DIR :=			playbooks
export KDEVOPS_HOSTFILE ?=			hosts
export KDEVOPS_NODES :=				vagrant/kdevops_nodes.yaml
export PYTHONUNBUFFERED=1

KDEVOPS_NODES_TEMPLATES :=			workflows/linux/kdevops_nodes_split_start.yaml.in
export KDEVOPS_NODES_TEMPLATES

KDEVOPS_INSTALL_TARGETS :=

DEFAULT_DEPS :=
MAKEFLAGS += --no-print-directory
SHELL := /bin/bash
HELP_TARGETS := kconfig-help-menu
EXTRA_VAR_INPUTS := most_extra_vars
PHONY += kconfig-help-menu

ifeq ($(V),1)
export Q=
export NQ=true
else
export Q=@
export NQ=echo
endif

null :=
space := ${null} ${null}
${space} := ${space}
LIMIT_HOSTS :=
ifneq (,$(HOSTS))
LIMIT_HOSTS := $(subst ${ }, -l , $(HOSTS))
endif

INCLUDES = -I include/
CFLAGS += $(INCLUDES)

export KDEVOPS_HOSTS_TEMPLATE := $(KDEVOPS_HOSTFILE).in
export KDEVOPS_HOSTS := $(KDEVOPS_HOSTFILE)

# This will be used to generate our extra_args.yml file used to pass on
# configuration data for ansible roles through kconfig.
ANSIBLE_EXTRA_ARGS :=

# These should be set as non-empty if you want any generic bring up
# targets to come up. We support 2 bring up methods:
#
#  - vagrant: for kvm/virtualbox
#  - terraform: for any cloud provider
#
# If you are using bare metal, you don't do bring up, or you'd
# likely do this yourself. What you *might* need if working
# with bare metal is provisioning, but our workflows targets
# provide that. The devconfig ansible role can be also augmented
# to support many different custom provisioning preferences outside
# of the scope of workflows. With things like kdump, etc.
KDEVOPS_BRING_UP_DEPS :=
KDEVOPS_DESTROY_DEPS :=

ifeq (y,$(CONFIG_TERRAFORM))
include scripts/terraform.Makefile
endif # CONFIG_TERRAFORM

VAGRANT_ARGS :=
ifeq (y,$(CONFIG_VAGRANT))
include scripts/vagrant.Makefile
endif
ANSIBLE_EXTRA_ARGS += $(VAGRANT_ARGS)

WORKFLOW_ARGS	:=
ifeq (y,$(CONFIG_WORKFLOWS))
include workflows/Makefile
endif # CONFIG_WORKFLOWS

ANSIBLE_EXTRA_ARGS += $(WORKFLOW_ARGS)

include scripts/devconfig.Makefile
include scripts/ssh.Makefile

ANSIBLE_CMD_KOTD_ENABLE := echo KOTD disabled so not running: 
ifeq (y,$(CONFIG_WORKFLOW_KOTD_ENABLE))
include scripts/kotd.Makefile
endif # WORKFLOW_KOTD_ENABLE

# We may not need the extra_args.yaml file all the time.  If this file is empty
# you don't need it. All of our ansible kdevops roles check for this file
# without you having to specify it as an extra_args=@extra_args.yaml file. This
# helps us with allowing users call ansible on the command line themselves,
# instead of using the make constructs we have built here.
ifneq (,$(ANSIBLE_EXTRA_ARGS))
DEFAULT_DEPS += $(KDEVOPS_EXTRA_VARS)
endif

# To not clutter the top level Makefile, work which requires to be made
# on the localhost can be augmented on the LOCALHOST_SETUP_WORK variable.
# This will run after the extra_vars.yaml file is created and so you can
# rely on it. The work in LOCALHOST_SETUP_WORK is run when you just run
# make with no arguments.
LOCALHOST_SETUP_WORK :=

POSTFIX_SETUP_ARGS :=
ifeq (y,$(CONFIG_SETUP_POSTFIX_EMAIL_RELAY))
include Makefile.postfix
endif # CONFIG_SETUP_POSTFIX_EMAIL_RELAY
ANSIBLE_EXTRA_ARGS += $(POSTFIX_SETUP_ARGS)

HYPERVISOR_TUNING_ARGS :=
ifeq (y,$(CONFIG_HYPERVISOR_TUNING))
include Makefile.hypervisor-tunings
endif # CONFIG_HYPERVISOR_TUNING
ANSIBLE_EXTRA_ARGS += $(HYPERVISOR_TUNING_ARGS)

ifeq (y,$(CONFIG_KDEVOPS_DISTRO_REG_METHOD_TWOLINE))
DEFAULT_DEPS += playbooks/secret.yml
endif

ifeq (y,$(CONFIG_KDEVOPS_ENABLE_DISTRO_EXTRA_ADDONS))
KDEVOPS_EXTRA_ADDON_SOURCE:=$(subst ",,$(CONFIG_KDEVOPS_EXTRA_ADDON_SOURCE))
endif

KDEVOPS_ANSIBLE_PROVISION_PLAYBOOK:=$(subst ",,$(CONFIG_KDEVOPS_ANSIBLE_PROVISION_PLAYBOOK))

export TOPDIR=./

# disable built-in rules for this file
.SUFFIXES:

.config:
	@(								\
	echo "/--------------"						;\
	echo "| $(PROJECT) isn't configured, please configure it" 	;\
	echo "| using one of the following options:"			;\
	echo "| To configure manually:"					;\
	echo "|     make oldconfig"					;\
	echo "|     make menuconfig"					;\
	echo "|"							;\
	make -f scripts/build.Makefile help                             ;\
	false)

define YAML_ENTRY
$(1)

endef

# We can transform most of .config things we need to using
# looping on ANSIBLE_EXTRA_ARGS and converting those with
# this target. If you need to do more complex fancy stuff
# extend the EXTRA_VAR_INPUTS variable in your workflow with
# your custom stuff.
most_extra_vars:
	@echo --- > $(KDEVOPS_EXTRA_VARS)
	@$(foreach exp,$(ANSIBLE_EXTRA_ARGS),echo $(call YAML_ENTRY,$(subst =,: ,$(exp)) >> $(KDEVOPS_EXTRA_VARS)))

PHONY += $(EXTRA_VAR_INPUTS)

$(KDEVOPS_EXTRA_VARS): .config $(EXTRA_VAR_INPUTS)

playbooks/secret.yml:
	@if [[ "$(CONFIG_KDEVOPS_REG_TWOLINE_REGCODE)" == "" ]]; then \
		echo "Registration code is not set, this must be set for this configuration" ;\
		exit 1 ;\
	fi
	@echo --- > $@
	@echo "$(CONFIG_KDEVOPS_REG_TWOLINE_ENABLE_STRING): True" >> $@
	@echo "$(CONFIG_KDEVOPS_REG_TWOLINE_REGCODE_VAR): $(CONFIG_KDEVOPS_REG_TWOLINE_REGCODE)" >> $@

ifeq (y,$(CONFIG_KDEVOPS_ENABLE_DISTRO_EXTRA_ADDONS))
$(KDEVOPS_EXTRA_ADDON_DEST): .config $(KDEVOPS_EXTRA_ADDON_SOURCE)
	@$(Q)cp $(KDEVOPS_EXTRA_ADDON_SOURCE) $(KDEVOPS_EXTRA_ADDON_DEST)
endif

ifneq (,$(KDEVOPS_BRING_UP_DEPS))
include scripts/bringup.Makefile
endif

DEFAULT_DEPS += $(KDEVOPS_HOSTS)
$(KDEVOPS_HOSTS): .config $(KDEVOPS_HOSTS_TEMPLATE)
	$(Q)$(TOPDIR)/scripts/gen_hosts.sh

DEFAULT_DEPS += $(KDEVOPS_NODES)
$(KDEVOPS_NODES): $(KDEVOPS_NODES_TEMPLATES) .config
	$(Q)$(TOPDIR)/scripts/gen_nodes_file.sh

DEFAULT_DEPS += $(LOCALHOST_SETUP_WORK)

PHONY += clean
clean:
	$(Q)$(MAKE) -f scripts/build.Makefile $@
	@$(Q)if [ -f terraform/Makefile ]; then \
		$(MAKE) -C terraform/ $@ ;\
	fi

PHONY += mrproper
mrproper:
	$(Q)$(MAKE) -f scripts/build.Makefile clean
	$(Q)$(MAKE) -f scripts/build.Makefile $@
	@$(Q)if [ -f terraform/Makefile ]; then \
		$(MAKE) -C terraform clean ;\
	fi
	$(Q)rm -f terraform/*/terraform.tfvars
	$(Q)rm -f $(KDEVOPS_NODES)
	$(Q)rm -f $(KDEVOPS_HOSTFILE) $(KDEVOPS_WORKFLOW_FSTESTS_CLEAN)
	$(Q)rm -f .config .config.old extra_vars.yaml
	$(Q)rm -f playbooks/secret.yml $(KDEVOPS_EXTRA_ADDON_DEST)
	$(Q)rm -rf include

kconfig-help-menu:
	$(Q)$(MAKE) -s -C scripts/kconfig help
	$(Q)$(MAKE) -f scripts/build.Makefile help

PHONY += $(HELP_TARGETS)

PHONY += help
help: $(HELP_TARGETS)

PHONY += deps
deps: $(DEFAULT_DEPS)

PHONY += install
install: $(KDEVOPS_INSTALL_TARGETS)
	$(Q)echo   Installed

.PHONY: $(PHONY)
