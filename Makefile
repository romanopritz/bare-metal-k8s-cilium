SHELL := /usr/bin/env bash
export KUBECONFIG ?= $(CURDIR)/ansible/admin.conf

ANSIBLE_DIR := ansible
PLAYBOOK    := $(ANSIBLE_DIR)/site.yml

.PHONY: help deps bootstrap cilium ingress app policies verify reset

help:
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk -F'[:#]' '{printf "  \033[1m%-12s\033[0m %s\n", $$1, $$NF}'

deps: ## Install Ansible collections required by the playbooks
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml

bootstrap: ## Run the full Ansible site.yml (host prep + kubeadm + Cilium)
	cd $(ANSIBLE_DIR) && ansible-playbook $(notdir $(PLAYBOOK))

cilium: ## Re-run only the Cilium install role
	cd $(ANSIBLE_DIR) && ansible-playbook $(notdir $(PLAYBOOK)) --tags cilium

ingress: ## Install ingress-nginx as DaemonSet on workers
	./scripts/install-ingress.sh

app: ## Deploy the demo nginx app
	kubectl apply -f manifests/app/

policies: ## Apply the two demo NetworkPolicies + L7 Cilium policy
	kubectl apply -f manifests/policies/

verify: ## Run quick sanity checks
	@./scripts/verify.sh

reset: ## DANGEROUS - tear down the cluster on every node
	cd $(ANSIBLE_DIR) && ansible-playbook reset.yml
