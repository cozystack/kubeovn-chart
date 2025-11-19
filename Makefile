KUBEOVN_TAG=$(shell awk '$$1 == "appVersion:" {print $$2}' chart/charts/kube-ovn/Chart.yaml)
REGISTRY ?= ghcr.io/cozystack/cozystack
PUSH := 1
LOAD := 0
BUILDER ?=
PLATFORM ?=
BUILDX_EXTRA_ARGS ?=
BUILDX_ARGS := --provenance=false --push=$(PUSH) --load=$(LOAD) \
  --label org.opencontainers.image.source=https://github.com/cozystack/cozystack \
  $(if $(strip $(BUILDER)),--builder=$(BUILDER)) \
  $(if $(strip $(PLATFORM)),--platform=$(PLATFORM)) \
  $(BUILDX_EXTRA_ARGS)

update:
	rm -rf chart/charts && mkdir -p chart/charts/kube-ovn
	tag=$$(git ls-remote --tags --sort="v:refname" https://github.com/kubeovn/kube-ovn | awk -F'[/^]' '{print $$3}' | grep '^v1\.14\.' | tail -n1 ) && \
	curl -sSL https://github.com/kubeovn/kube-ovn/archive/refs/tags/$${tag}.tar.gz | \
	tar -C ./chart/ -xzvf - --strip 1 kube-ovn-$${tag#*v}/charts/kube-ovn
	patch --no-backup-if-mismatch -p4 -d ./chart/ < patches/cozyconfig.diff
	patch --no-backup-if-mismatch -p4 -d ./chart/ < patches/mtu.diff
	version=$$(awk '$$1 == "appVersion:" {print $$2}' chart/charts/kube-ovn/Chart.yaml) && \
	sed -i "s/ARG VERSION=.*/ARG VERSION=$${version}/" docker/Dockerfile && \
	sed -i "s/ARG TAG=.*/ARG TAG=$${version}/" docker/Dockerfile

image:
	docker buildx build ./docker/ \
		--tag $(REGISTRY)/kubeovn:v$(KUBEOVN_TAG) \
		--cache-from type=registry,ref=$(REGISTRY)/kubeovn:latest \
		--cache-to type=inline \
		--metadata-file kubeovn.json \
		$(BUILDX_ARGS)
	REGISTRY="$(REGISTRY)" \
		yq -i '.global.registry.address = strenv(REGISTRY)' chart/values.yaml
	REPOSITORY="kubeovn" \
		yq -i '.global.images.kubeovn.repository = strenv(REPOSITORY)' chart/values.yaml
	TAG="v$(KUBEOVN_TAG)@$$(yq e '."containerimage.digest"' kubeovn.json -o json -r)" \
		yq -i '.global.images.kubeovn.tag = strenv(TAG)' chart/values.yaml
	rm -f kubeovn.json
