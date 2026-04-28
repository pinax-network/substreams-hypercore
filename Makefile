ENDPOINT ?= hypercore-substreams-tier1-prod.kan-sst2.pinax.io:443
START_BLOCK ?= 866536721
STOP_BLOCK ?= +10000
PARALLEL_JOBS ?= 500
.DEFAULT_GOAL := pack

.PHONY: protogen
protogen:
	substreams protogen

.PHONY: build
build:
	cargo build --target wasm32-unknown-unknown --release

.PHONY: pack
pack: build
	substreams pack -o ./spkg/{spkgDefaultName}

.PHONY: noop
noop: build
	substreams-sink-noop $(ENDPOINT) substreams.yaml db_out -H "X-Sf-Substreams-Parallel-Jobs: $(PARALLEL_JOBS)" $(START_BLOCK):$(STOP_BLOCK)

.PHONY: gui
gui: build
	substreams gui -e $(ENDPOINT) substreams.yaml db_out -s $(START_BLOCK)

.PHONY: prod
prod: build
	substreams gui -e $(ENDPOINT) substreams.yaml db_out -s $(START_BLOCK) -t $(STOP_BLOCK) --limit-processed-blocks 0 --production-mode  -H "X-Sf-Substreams-Parallel-Jobs: $(PARALLEL_JOBS)"