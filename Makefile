COMPOSE := docker compose -f docker-compose.yml -f docker-compose.chaos.yml
TEST_FILE := /tmp/test-fragment.bin
GO := go

.PHONY: help init up down logs health test test-go test-integration test-all put get clean build-cli \
	chaos-volume-down chaos-volume-up chaos-master-down chaos-master-up \
	chaos-mount-unavailable chaos-disk-full chaos-disk-readonly chaos-reset \
	chaos-matrix put-v1

help:
	@echo "Targets:"
	@echo "  init                 git submodule update --init"
	@echo "  up                   build and start stack"
	@echo "  down                 stop stack"
	@echo "  health               wait for all services"
	@echo "  test                 bash smoke test (put + get)"
	@echo "  test-go              go integration tests (requires make up)"
	@echo "  test-all             bash + go integration tests"
	@echo "  build-cli            build cmd/fragment binary"
	@echo "  put-v1               put fragment pinned to volume1 (dc1)"
	@echo "  chaos-matrix         run fault scenarios and save results"

init:
	git submodule sync --recursive
	git submodule update --init --recursive

up: init
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=100

health:
	./scripts/wait-healthy.sh

build-cli:
	$(GO) build -o bin/fragment ./cmd/fragment

test-file:
	@dd if=/dev/urandom of=$(TEST_FILE) bs=1M count=1 status=none
	@echo "Created $(TEST_FILE)"

test: test-file health
	@out=$$(./scripts/put_fragment.sh $(TEST_FILE) camera-test); echo "$$out"; \
	fid=$$(echo "$$out" | awk '/fragment_id:/ {print $$2}'); \
	./scripts/get_fragment.sh camera-test "$$fid"

test-go:
	$(GO) test -tags=integration -v -count=1 ./test/integration/...

test-all: test test-go

put: test-file
	./scripts/put_fragment.sh $(TEST_FILE) camera-manual

put-v1: test-file
	./scripts/put_to_volume1.sh $(TEST_FILE) camera-manual-v1

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
