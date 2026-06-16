COMPOSE := docker compose -f docker-compose.yml -f docker-compose.chaos.yml
TEST_FILE := /tmp/test-fragment.bin

.PHONY: help init up down logs health test put get clean \
	chaos-volume-down chaos-volume-up chaos-master-down chaos-master-up \
	chaos-mount-unavailable chaos-disk-full chaos-disk-readonly chaos-reset \
	chaos-matrix

help:
	@echo "Targets:"
	@echo "  init                 git submodule update --init"
	@echo "  up                   build and start stack"
	@echo "  down                 stop stack"
	@echo "  health               wait for all services"
	@echo "  test                 smoke test (put + get)"
	@echo "  chaos-matrix         run fault scenarios and save results"
	@echo "  chaos-volume-down    stop volume1"
	@echo "  chaos-volume-up      start volume1"
	@echo "  chaos-master-down    stop master"
	@echo "  chaos-master-up      start master"
	@echo "  chaos-mount-unavailable  chmod 000 /data on volume1"
	@echo "  chaos-disk-full      fill volume1 disk"
	@echo "  chaos-disk-readonly  remount volume1 /data read-only"
	@echo "  chaos-reset          reset volume1 fault state"

init:
	git submodule update --init --recursive

up: init
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=100

health:
	./scripts/wait-healthy.sh

test-file:
	@dd if=/dev/urandom of=$(TEST_FILE) bs=1M count=1 status=none
	@echo "Created $(TEST_FILE)"

test: test-file health
	@out=$$(./scripts/put_fragment.sh $(TEST_FILE) camera-test); echo "$$out"; \
	fid=$$(echo "$$out" | awk '/fragment_id:/ {print $$2}'); \
	./scripts/get_fragment.sh camera-test "$$fid"

put: test-file
	./scripts/put_fragment.sh $(TEST_FILE) camera-manual

get:
	@test -n "$(CAMERA)" && test -n "$(FRAGMENT)" || (echo "Usage: make get CAMERA=camera-1 FRAGMENT=<uuid>" && exit 1)
	./scripts/get_fragment.sh $(CAMERA) $(FRAGMENT)

clean:
	$(COMPOSE) down -v

chaos-volume-down:
	./scripts/chaos/volume_down.sh volume1

chaos-volume-up:
	./scripts/chaos/volume_up.sh volume1

chaos-master-down:
	./scripts/chaos/master_down.sh

chaos-master-up:
	./scripts/chaos/master_up.sh

chaos-mount-unavailable:
	./scripts/chaos/mount_unavailable.sh volume1

chaos-disk-full:
	./scripts/chaos/disk_full.sh volume1

chaos-disk-readonly:
	./scripts/chaos/disk_readonly.sh volume1

chaos-reset:
	./scripts/chaos/reset_volumes.sh volume1

chaos-matrix:
	./scripts/chaos/run_matrix.sh
