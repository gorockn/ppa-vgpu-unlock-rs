DISTRIB  ?= ubuntu
RELEASE  ?= 22.04
CODENAME ?= jammy

REPOS  = github.com/mbilker/vgpu_unlock-rs
BRANCH = master

DEBFULLNAME = Gorockn
DEBEMAIL    = gorockn@users.noreply.github.com

ASSETS_DIR   = $(CURDIR)/assets
DOWNLOAD_DIR = $(CURDIR)/download
BUILD_DIR    = $(CURDIR)/build

DOCKER_BUILD_ARGS = \
	--build-arg "DISTRIB=$(DISTRIB)" \
	--build-arg "RELEASE=$(RELEASE)" \
	--build-arg "DEBFULLNAME=$(DEBFULLNAME)" \
	--build-arg "DEBEMAIL=$(DEBEMAIL)"

ifeq (${GITHUB_REPOSITORY},)
DOCKER_IMAGE_REPOSITORY = gorockn/ppa-vgpu-unlock-rs
else
DOCKER_IMAGE_REPOSITORY = ${GITHUB_REPOSITORY}
endif

DOCKER_IMAGE_CACHE_TAG   = $(DOCKER_IMAGE_REPOSITORY):cache-$(DISTRIB)-$(RELEASE)
DOCKER_IMAGE_BUILDER_TAG = $(DOCKER_IMAGE_REPOSITORY):builder-$(DISTRIB)-$(RELEASE)

ifneq (${GITHUB_ACTION},)
DOCKER_BUILD_ARGS += --push
DOCKER_BUILD_ARGS += --cache-from type=registry,ref=$(DOCKER_IMAGE_CACHE_TAG)
DOCKER_BUILD_ARGS += --cache-to type=registry,ref=$(DOCKER_IMAGE_CACHE_TAG),mode=max
endif

################################################################################
# Default Target (Build Only)
################################################################################

.PHONY: all
all: build

################################################################################
# Build Matrix (CI Setup Phase)
################################################################################

.PHONY: matrix
matrix:
	@{ \
		echo '{"distrib": "ubuntu", "release": "22.04", "codename": "jammy"}'; \
		echo '{"distrib": "ubuntu", "release": "20.04", "codename": "focal"}'; \
		echo '{"distrib": "debian", "release": "12-slim", "codename": "bookworm"}'; \
		echo '{"distrib": "debian", "release": "11-slim", "codename": "bullseye"}'; \
	} | jq -Mcs .

################################################################################
# Build Package (CI Build Phase)
################################################################################

.PHONY: download
download:
ifeq ($(wildcard $(DOWNLOAD_DIR)/vgpu_unlock-rs.tar.gz),)
	@mkdir -p "$(DOWNLOAD_DIR)"
	@wget -O "$(DOWNLOAD_DIR)/vgpu_unlock-rs.tar.gz" "https://$(REPOS)/archive/refs/heads/$(BRANCH).tar.gz"
endif

.PHONY: extract
extract: download
ifeq ($(wildcard $(BUILD_DIR)/Cargo.toml),)
	@mkdir -p "$(BUILD_DIR)"
	@tar -xvf "$(DOWNLOAD_DIR)/vgpu_unlock-rs.tar.gz" -C "$(BUILD_DIR)" --strip-components=1
	@cat "$(ASSETS_DIR)/cargo-deb.toml" >> "$(BUILD_DIR)/Cargo.toml"
	@cat "$(ASSETS_DIR)/cargo-deb-config.toml" >> "$(BUILD_DIR)/config.toml"
	@cat "$(ASSETS_DIR)/cargo-deb-systemd.conf" >> "$(BUILD_DIR)/systemd.conf"
	@cat "$(ASSETS_DIR)/cargo-deb-modules.conf" >> "$(BUILD_DIR)/modules.conf"
	@cat "$(ASSETS_DIR)/cargo-deb-blacklist.conf" >> "$(BUILD_DIR)/blacklist.conf"
endif

.PHONY: docker-build
docker-build:
ifeq ($(shell docker images -q $(DOCKER_IMAGE_BUILDER_TAG)),)
	@docker build $(DOCKER_BUILD_ARGS) --tag $(DOCKER_IMAGE_BUILDER_TAG) .
endif

.PHONY: build
build: extract docker-build
ifeq ($(wildcard $(BUILD_DIR)/target/debian/*.deb),)
	@docker run --rm -v "$(BUILD_DIR):/build" $(DOCKER_IMAGE_BUILDER_TAG) sh -c "cargo build --release && cargo deb"
endif

################################################################################
# Build Repository (CI Integration Phase)
################################################################################

# TODO

define repository
	@mkdir -p public/dists/$(1)/main/binary-all
	@mkdir -p public/dists/$(1)/main/binary-i386
	@mkdir -p public/dists/$(1)/main/binary-amd64
	@mkdir -p public/dists/$(1)/main/binary-armhf
	@mkdir -p public/dists/$(1)/main/binary-arm64
	@mkdir -p public/pool/$(1)/main
	@cp build/$(1)/*.deb public/pool/$(1)/main/
	@cd public && apt-ftparchive generate ../build/debian-$(1)-repos.conf
	@cd public && apt-ftparchive -c ../build/debian-$(1)-meta.conf release dists/$(1) > dists/$(1)/Release
endef

.PHONY: repository
repository: package
	@$(call repository,bullseye)
	@$(call repository,bookworm)
	@$(call repository,focal)
	@$(call repository,jammy)

define reposign
	@gpg --homedir secret/gpghome \
		--pinentry-mode loopback \
		--passphrase "$$(cat secret/passphrase)" \
		--clearsign \
		-o public/dists/$(1)/InRelease \
		public/dists/$(1)/Release
	@gpg --homedir secret/gpghome \
		--pinentry-mode loopback \
		--passphrase "$$(cat secret/passphrase)" \
		-abs \
		-o public/dists/$(1)/Release.gpg \
		public/dists/$(1)/Release
endef

.PHONY: reposign
reposign: repository
	@mkdir -p -m 0700 secret/gpghome
	@gpg --homedir secret/gpghome \
		--pinentry-mode loopback \
		--passphrase "$$(cat secret/passphrase)" \
		--import \
		--allow-secret-key-import \
		secret/secret.gpg.asc
	$(call reposign,bullseye)
	$(call reposign,bookworm)
	$(call reposign,focal)
	$(call reposign,jammy)

.PHONY: assets
assets: reposign
	@cp assets/index.html public/index.html
	@cp assets/public.gpg.asc public/public.gpg.asc

################################################################################
# Generate GPG Keys (Manual)
################################################################################

.PHONY: generate-gpg
generate-gpg: assets/public.gpg.asc secret/secret.gpg.asc
secret/passphrase:
	@mkdir -p -m 0700 secret
	@pwgen -ncys1 64 > secret/passphrase
	@chmod 0600 secret/passphrase
secret/gpghome: secret/passphrase
	@mkdir -p -m 0700 secret/gpghome
	@gpg --homedir secret/gpghome \
		--pinentry-mode loopback \
		--passphrase "$$(cat secret/passphrase)" \
		--quick-generate-key "$(DEBFULLNAME) <$(DEBEMAIL)>" \
		default default 10y
assets/public.gpg.asc: secret/gpghome
	@gpg --homedir secret/gpghome \
		--export --armor \
		--output assets/public.gpg.asc \
		--yes \
		"$(DEBFULLNAME) <$(DEBEMAIL)>"
secret/secret.gpg.asc: secret/gpghome secret/passphrase
	@gpg --homedir secret/gpghome \
		--pinentry-mode loopback \
		--passphrase "$$(cat secret/passphrase)" \
		--export-secret-keys --armor \
		--output secret/secret.gpg.asc \
		--yes \
		"$(DEBFULLNAME) <$(DEBEMAIL)>"

################################################################################
# Clean (Manual)
################################################################################

.PHONY: clean
clean:
	@docker system prune -f

.PHONY: distclean
distclean: clean
	@sudo rm -fr $(BUILD_DIR)
