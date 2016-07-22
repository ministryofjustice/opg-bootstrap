.PHONY: check test clean all build showvars
shellcheck := $(shell which shellcheck)
git_branch := $(shell git branch | awk '/^\*/ {print $$2}')
cleanup =? no

check:
ifneq ($(shellcheck),)
	@echo Running lint tests on shell scripts
	$(shellcheck) -e SC2086 ../bootstrap.sh
	$(shellcheck) -e SC2086 ../modules/*.sh
else
	$(error shellcheck not found in path.)
endif

test:
	@echo Setup virtualenv
	( \
	virtualenv virtenv; \
	. ./virtenv/bin/activate; \
	pip install -r requirements.txt; \
	pip freeze; \
	virtenv/bin/ansible-playbook -i hosts site.yml  --syntax-check; \
	virtenv/bin/ansible-playbook -i hosts site.yml -vvv -e "subnet_id=${SUBNET_ID} cleanup='$(cleanup)' git_branch=$(git_branch)"  --check; \
	)
debug:
	@echo Setup virtualenv
	( \
	virtualenv virtenv; \
	. ./virtenv/bin/activate; \
	pip install -r requirements.txt; \
	pip freeze; \
	virtenv/bin/ansible-playbook -i hosts site.yml -vvv  -e "subnet_id=${SUBNET_ID} cleanup='$(cleanup)' git_branch=$(git_branch)"; \
	)

clean:
	@rm -rf virtenv

all: showvars check test build clean

build:
	@echo Setup virtualenv
	( \
	virtualenv virtenv; \
	. ./virtenv/bin/activate; \
	pip install -r requirements.txt; \
	pip freeze; \
	virtenv/bin/ansible-playbook -i hosts site.yml -v  -e "subnet_id=${SUBNET_ID} cleanup='$(cleanup)' git_branch=$(git_branch)"; \
	)

showvars:
	@echo "============================"
	@echo "cleanup: $(cleanup)"
	@echo "subnet_id: $(SUBNET_ID)"
	@echo "git_branch: $(git_branch)"
	@echo "============================"
