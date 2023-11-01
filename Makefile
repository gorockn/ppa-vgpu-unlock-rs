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
SECRET_DIR   = $(CURDIR)/secret
PUBLIC_DIR   = $(CURDIR)/public

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
all: package

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

.PHONY: builder
builder:
ifeq ($(shell docker images -q $(DOCKER_IMAGE_BUILDER_TAG)),)
	@docker build $(DOCKER_BUILD_ARGS) --tag $(DOCKER_IMAGE_BUILDER_TAG) .
endif

.PHONY: package
package: extract builder
ifeq ($(wildcard $(BUILD_DIR)/target/debian/*.deb),)
	@docker run --rm -v "$(BUILD_DIR):/build" $(DOCKER_IMAGE_BUILDER_TAG) sh -c "cargo build --release && cargo deb"
endif
ifeq ($(wildcard $(BUILD_DIR)/target/debian/SHA256SUMS),)
	@docker run --rm -v "$(BUILD_DIR):/build" $(DOCKER_IMAGE_BUILDER_TAG) sh -c "cd target/debian && sha256sum *.deb > SHA256SUMS"
endif
ifeq ($(wildcard $(BUILD_DIR)/packages/$(DISTRIB)-$(CODENAME)/*.deb),)
	@mkdir -p $(BUILD_DIR)/packages/$(DISTRIB)-$(CODENAME)
	@cp $(BUILD_DIR)/target/debian/SHA256SUMS $(BUILD_DIR)/packages/$(DISTRIB)-$(CODENAME)/
	@cp $(BUILD_DIR)/target/debian/*.deb $(BUILD_DIR)/packages/$(DISTRIB)-$(CODENAME)/
endif

################################################################################
# Build Repository (CI Integration Phase)
################################################################################

define repogen
	@mkdir -p $(BUILD_DIR)/$(1)-$(2)
	@cp $(ASSETS_DIR)/apt-meta.conf $(BUILD_DIR)/$(1)-$(2)/meta.conf
	@cp $(ASSETS_DIR)/apt-repos.conf $(BUILD_DIR)/$(1)-$(2)/repos.conf
	@sed -i -E 's/___SUITE___/$(1)/' $(BUILD_DIR)/$(1)-$(2)/meta.conf
	@sed -i -E 's/___SUITE___/$(1)/' $(BUILD_DIR)/$(1)-$(2)/repos.conf
	@sed -i -E 's/___CODENAME___/$(2)/' $(BUILD_DIR)/$(1)-$(2)/meta.conf
	@sed -i -E 's/___CODENAME___/$(2)/' $(BUILD_DIR)/$(1)-$(2)/repos.conf
	@mkdir -p $(PUBLIC_DIR)/dists/$(1)/$(2)/main/binary-all
	@mkdir -p $(PUBLIC_DIR)/dists/$(1)/$(2)/main/binary-i386
	@mkdir -p $(PUBLIC_DIR)/dists/$(1)/$(2)/main/binary-amd64
	@mkdir -p $(PUBLIC_DIR)/dists/$(1)/$(2)/main/binary-armhf
	@mkdir -p $(PUBLIC_DIR)/dists/$(1)/$(2)/main/binary-arm64
	@mkdir -p $(PUBLIC_DIR)/pool/$(1)/$(2)/main
	@cp $(BUILD_DIR)/packages/$(1)-$(2)/*.deb $(PUBLIC_DIR)/pool/$(1)/$(2)/main/
	@cd $(PUBLIC_DIR) && apt-ftparchive \
		generate $(BUILD_DIR)/$(1)-$(2)/repos.conf
	@cd $(PUBLIC_DIR) && apt-ftparchive \
		-c $(BUILD_DIR)/$(1)-$(2)/meta.conf \
		release \
		$(PUBLIC_DIR)/dists/$(1)/$(2) \
		> $(PUBLIC_DIR)/dists/$(1)/$(2)/Release
endef

.PHONY: repogen
repogen:
ifneq ($(wildcard $(BUILD_DIR)/packages/ubuntu-jammy/*.deb),)
	@$(call repogen,ubuntu,jammy)
endif
ifneq ($(wildcard $(BUILD_DIR)/packages/ubuntu-focal/*.deb),)
	@$(call repogen,ubuntu,focal)
endif
ifneq ($(wildcard $(BUILD_DIR)/packages/debian-bookworm/*.deb),)
	@$(call repogen,debian,bookworm)
endif
ifneq ($(wildcard $(BUILD_DIR)/packages/debian-bullseye/*.deb),)
	@$(call repogen,debian,bullseye)
endif

define reposign
	@gpg --homedir $(SECRET_DIR)/gpghome \
		--pinentry-mode loopback \
		--passphrase "$$(cat $(SECRET_DIR)/passphrase)" \
		--clearsign \
		-o $(PUBLIC_DIR)/dists/$(1)/$(2)/InRelease \
		$(PUBLIC_DIR)/dists/$(1)/$(2)/Release
	@gpg --homedir $(SECRET_DIR)/gpghome \
		--pinentry-mode loopback \
		--passphrase "$$(cat $(SECRET_DIR)/passphrase)" \
		-abs \
		-o $(PUBLIC_DIR)/dists/$(1)/$(2)/Release.gpg \
		$(PUBLIC_DIR)/dists/$(1)/$(2)/Release
endef

.PHONY: reposign
reposign: repogen
ifneq ($(wildcard $(SECRET_DIR)/gpghome/trustdb.gpg),)
	@mkdir -p -m 0700 $(SECRET_DIR)/gpghome
	@gpg --homedir $(SECRET_DIR)/gpghome \
		--pinentry-mode loopback \
		--passphrase "$$(cat $(SECRET_DIR)/passphrase)" \
		--import \
		--allow-secret-key-import \
		$(SECRET_DIR)/secret.gpg.asc
endif
ifneq ($(wildcard $(PUBLIC_DIR)/dists/ubuntu/jammy/Release),)
	$(call reposign,ubuntu,jammy)
endif
ifneq ($(wildcard $(PUBLIC_DIR)/dists/ubuntu/focal/Release),)
	$(call reposign,ubuntu,focal)
endif
ifneq ($(wildcard $(PUBLIC_DIR)/dists/debian/bookworm/Release),)
	$(call reposign,debian,bookworm)
endif
ifneq ($(wildcard $(PUBLIC_DIR)/dists/debian/bullseye/Release),)
	$(call reposign,debian,bullseye)
endif

.PHONY: artifacts
artifacts: reposign
ifneq ($(wildcard $(PUBLIC_DIR)/index.html),)
	@cp $(ASSETS_DIR)/index.html $(PUBLIC_DIR)/index.html
endif
ifneq ($(wildcard $(PUBLIC_DIR)/public.gpg.asc),)
	@cp $(ASSETS_DIR)/public.gpg.asc $(PUBLIC_DIR)/public.gpg.asc
endif

################################################################################
# Generate GPG Keys (Manual)
################################################################################

.PHONY: generate-gpg
generate-gpg: $(ASSETS_DIR)/public.gpg.asc $(SECRET_DIR)/secret.gpg.asc
$(SECRET_DIR)/passphrase:
	@mkdir -p -m 0700 $(SECRET_DIR)
	@pwgen -ncys1 64 > $(SECRET_DIR)/passphrase
	@chmod 0600 $(SECRET_DIR)/passphrase
$(SECRET_DIR)/gpghome: $(SECRET_DIR)/passphrase
	@mkdir -p -m 0700 $(SECRET_DIR)/gpghome
	@gpg --homedir $(SECRET_DIR)/gpghome \
		--pinentry-mode loopback \
		--passphrase "$$(cat $(SECRET_DIR)/passphrase)" \
		--quick-generate-key "$(DEBFULLNAME) <$(DEBEMAIL)>" \
		default default 10y
$(ASSETS_DIR)/public.gpg.asc: $(SECRET_DIR)/gpghome
	@gpg --homedir $(SECRET_DIR)/gpghome \
		--export --armor \
		--output $(ASSETS_DIR)/public.gpg.asc \
		--yes \
		"$(DEBFULLNAME) <$(DEBEMAIL)>"
$(SECRET_DIR)/secret.gpg.asc: $(SECRET_DIR)/gpghome $(SECRET_DIR)/passphrase
	@gpg --homedir $(SECRET_DIR)/gpghome \
		--pinentry-mode loopback \
		--passphrase "$$(cat $(SECRET_DIR)/passphrase)" \
		--export-secret-keys --armor \
		--output $(SECRET_DIR)/secret.gpg.asc \
		--yes \
		"$(DEBFULLNAME) <$(DEBEMAIL)>"

################################################################################
# Clean (Manual)
################################################################################

.PHONY: clean
clean:
	@docker system prune -f
	@sudo rm -fr $(BUILD_DIR)
	@sudo rm -fr $(PUBLIC_DIR)
