#!/usr/bin/env bash
set -euo pipefail

# 1) Carica variabili da .env se presente
if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
fi

# 2) Login automatico
if [[ -n "${DOCKER_USERNAME:-}" && -n "${DOCKER_PASSWORD:-}" ]]; then
  echo "$DOCKER_PASSWORD" | docker login docker.io \
    --username "$DOCKER_USERNAME" --password-stdin
fi

# 3) Parametri (override in .env o CLI)
IMAGE="${IMAGE:-nicbad/meshspy}"
TAG="${TAG:-latest}"
GOOS="linux"
ARCHS=(amd64 386 armv6 armv7 arm64)

# 4) Se manca go.mod, lo generiamo
if [[ ! -f go.mod ]]; then
  echo "🛠 Generating go.mod and go.sum…"
  docker run --rm \
    -v "${PWD}":/app -w /app \
    golang:1.21-alpine sh -c "\
      go mod init ${IMAGE#*/} && \
      go get github.com/eclipse/paho.mqtt.golang@v1.5.0 github.com/tarm/serial@latest && \
      go mod tidy"
fi

# 5) Mappe per build-arg e annotazioni
declare -A GOARCH=( [amd64]=amd64 [386]=386 [armv6]=arm [armv7]=arm [arm64]=arm64 )
declare -A GOARM=(  [armv6]=6     [armv7]=7                )
declare -A MAN_OPTS=(
  [amd64]="--os linux --arch amd64"
  [386]="--os linux --arch 386"
  [armv6]="--os linux --arch arm --variant v6"
  [armv7]="--os linux --arch arm --variant v7"
  [arm64]="--os linux --arch arm64"
)

echo "🛠 Building & pushing single-arch images for: ${ARCHS[*]}"
for arch in "${ARCHS[@]}"; do
  TAG_ARCH="${IMAGE}:${TAG}-${arch}"
  echo " • Building $TAG_ARCH"

  # build mono-arch
  build_args=( --no-cache -t "$TAG_ARCH" )
  build_args+=( --build-arg "GOOS=$GOOS" )
  build_args+=( --build-arg "GOARCH=${GOARCH[$arch]}" )
  if [[ -n "${GOARM[$arch]:-}" ]]; then
    build_args+=( --build-arg "GOARM=${GOARM[$arch]}" )
  fi
  build_args+=( . )
  docker build "${build_args[@]}"

  # push slice
  echo " → Pushing $TAG_ARCH"
  docker push "$TAG_ARCH"
done

echo "📦 Preparing manifest ${IMAGE}:${TAG}"
# rimuove eventuale manifest esistente
docker manifest rm "${IMAGE}:${TAG}" >/dev/null 2>&1 || true

# crea manifest multi-arch
manifest_args=( manifest create "${IMAGE}:${TAG}" )
for arch in "${ARCHS[@]}"; do
  manifest_args+=( "${IMAGE}:${TAG}-${arch}" )
done
docker "${manifest_args[@]}"

echo "⚙️ Annotating slices"
for arch in "${ARCHS[@]}"; do
  docker manifest annotate "${IMAGE}:${TAG}" \
    "${IMAGE}:${TAG}-${arch}" ${MAN_OPTS[$arch]}
done

echo "🚀 Pushing multi-arch manifest ${IMAGE}:${TAG}"
docker manifest push "${IMAGE}:${TAG}"

echo "✅ Done! Multi-arch image available: ${IMAGE}:${TAG}"
