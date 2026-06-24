COMPOSE := docker compose -f docker-compose.yml -f docker-compose.chaos.yml
COMPOSE_MULTI := docker compose -f docker-compose.yml -f docker-compose.chaos.yml -f docker-compose.multi-dir.yml
COMPOSE_PERSIST := docker compose -f docker-compose.yml -f docker-compose.persist.yml
TEST_FILE := /tmp/test-fragment.bin
GO := go

.PHONY: help init init-seaweedfs check-seaweedfs up down logs health test test-go test-integration test-all put get clean build-cli \
	chaos-volume-down chaos-volume-up chaos-master-down chaos-master-up \
	chaos-mount-unavailable chaos-disk-full chaos-disk-readonly chaos-reset \
	chaos-matrix chaos-recovery chaos-recovery-disk chaos-multi-dir put-v1 up-multi-dir up-persist \
	test-sideweed test-snapshot

help:
	@echo "Targets:"
	@echo "  init                 git submodule update --init"
	@echo "  init-seaweedfs       clone customer fork (SEAWEEDFS_REPO_URL) + checkout pin"
	@echo "  check-seaweedfs      verify ./seaweedfs at commit 1528e7d"
	@echo "  up                   build and start stack"
	@echo "  down                 stop stack"
	@echo "  health               wait for all services"
	@echo "  test                 bash smoke test (put + get)"
	@echo "  test-go              go integration tests (requires make up)"
	@echo "  test-unit            go unit tests (resilience)"
	@echo "  test-all             bash + go integration tests"
	@echo "  build-cli            build cmd/fragment binary"
	@echo "  put-v1               DEBUG: direct volume PUT (scripts/debug/)"
	@echo "  put-snapshot         PUT snapshot to bucket csb (production path)"
	@echo "  test-snapshot        smoke: snapshot PUT + GET via bucket csb"
	@echo "  verify-path          prove PUT goes sideweed → S3"
	@echo "  test-sideweed        sideweed write degradation gate (PUT block / recovery)"
	@echo "  chaos-matrix         run fault scenarios and save results"
	@echo "  chaos-recovery       fault -> reset -> assert PUT/GET recovery"
	@echo "  chaos-recovery-disk  disk ro -> soft reset -> GET baseline (no restart)"
	@echo "  chaos-multi-dir      per-dir disk health demo (volume1 /data1,/data2)"
	@echo "  up-multi-dir         start stack with multi-dir volume1"
	@echo "  up-persist           volume1 on named volume (persistent /data)"

init:
	git submodule sync --recursive
	git submodule update --init --recursive

init-seaweedfs:
	chmod +x ./scripts/init_seaweedfs.sh
	./scripts/init_seaweedfs.sh

check-seaweedfs:
	chmod +x ./scripts/check_seaweedfs.sh
	./scripts/check_seaweedfs.sh

up: init check-seaweedfs
	$(COMPOSE) up -d --build

up-multi-dir: init check-seaweedfs
	$(COMPOSE_MULTI) up -d --build

up-persist: init check-seaweedfs
	$(COMPOSE_PERSIST) up -d --build

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

test: check-seaweedfs test-file build-cli health
	@out=$$(./scripts/put_fragment.sh $(TEST_FILE) camera-test); echo "$$out"; \
	fid=$$(echo "$$out" | awk '/fragment_id:/ {print $$2}'); \
	./scripts/get_fragment.sh camera-test "$$fid"

# TODO: add check-seaweedfs once integration tests assume pinned fork binary
test-go: health
	$(GO) test -tags=integration -v -count=1 ./test/integration/...

test-all: test test-go

put: test-file
	./scripts/put_fragment.sh $(TEST_FILE) camera-manual

put-v1: test-file
	./scripts/debug/put_to_volume1.sh $(TEST_FILE) camera-manual-v1

put-snapshot: test-file
	./scripts/put_snapshot.sh $(TEST_FILE) snapshot-manual

test-snapshot: check-seaweedfs build-cli health
	chmod +x ./scripts/get_snapshot.sh ./scripts/test_snapshot.sh
	./scripts/test_snapshot.sh

verify-path: check-seaweedfs test-file build-cli health
	./scripts/verify_production_path.sh $(TEST_FILE)

test-sideweed: check-seaweedfs build-cli health
	chmod +x ./scripts/test_sideweed.sh
	./scripts/test_sideweed.sh

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

# TODO: add check-seaweedfs (chaos-matrix needs disk-health patch; run make up first)
chaos-matrix:
	chmod +x ./scripts/chaos/run_matrix.sh
	./scripts/chaos/run_matrix.sh

chaos-recovery:
	chmod +x ./scripts/chaos/run_recovery.sh
	./scripts/chaos/run_recovery.sh

chaos-recovery-disk:
	chmod +x ./scripts/chaos/run_recovery_disk.sh ./scripts/chaos/prepare_recovery_disk.sh ./scripts/chaos/disk_full_named.sh ./scripts/chaos/reset_volumes_soft_named.sh
	./scripts/chaos/run_recovery_disk.sh

chaos-multi-dir:
	chmod +x ./scripts/chaos/run_multi_dir_chaos.sh
	./scripts/chaos/run_multi_dir_chaos.sh

chaos-volume1:
	chmod +x ./scripts/chaos/run_volume1_chaos.sh
	./scripts/chaos/run_volume1_chaos.sh

test-unit:
	$(GO) test ./pkg/fragment/... -count=1 -v
