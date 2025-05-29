#!/usr/bin/env bash
set -euo pipefail

# Carica variabili da .env se presente
if [[ -f .env ]]; then
  source .env
fi

# Login automatico se configurato
if [[ -n "${DOCKER_USERNAME:-}" && -n "${DOCKER_PASSWORD:-}" ]]; then
  echo "$DOCKER_PASSWORD" | docker login docker.io \
    --username "$DOCKER_USERNAME" --password-stdin
fi

# Parametri
IMAGE="${IMAGE:-nicbad/meshspy}"
TAG="${TAG:-latest}"
GOOS="linux"

# Architetture separate
ARCH_ARMV6="linux/arm/v6"
PLATFORMS_PARALLEL="linux/arm/v7,linux/amd64,linux/386,linux/arm64"

PROTO_REPO="https://github.com/meshtastic/protobufs.git"
TMP_DIR=".proto_tmp"
PROTO_MAP_FILE=".proto_compile_map.sh"
rm -f "$PROTO_MAP_FILE"

echo "📥 Recupero tag disponibili da $PROTO_REPO"
git ls-remote --tags "$PROTO_REPO" | awk '{print $2}' |
  grep -E '^refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's|refs/tags/||' | sort -V | while read -r PROTO_VERSION; do
  if [[ "$(printf '%s\n' "$PROTO_VERSION" v2.0.14 | sort -V | head -n1)" != "v2.0.14" ]]; then
    echo "⏩ Salto $PROTO_VERSION (proto non standard)"
    continue
  fi
  PROTO_DIR="internal/proto/${PROTO_VERSION}"
  if [[ -d "${PROTO_DIR}" ]]; then
    echo "✔️ Proto già presenti: $PROTO_DIR"
    continue
  fi

  echo "📥 Scaricando proto $PROTO_VERSION…"
  rm -rf "$TMP_DIR"
  git clone --depth 1 --branch "$PROTO_VERSION" "$PROTO_REPO" "$TMP_DIR"
  mkdir -p "/tmp/proto-${PROTO_VERSION}-copy"
  cp -r "$TMP_DIR/meshtastic" "/tmp/proto-${PROTO_VERSION}-copy/"
  curl -sSL https://raw.githubusercontent.com/nanopb/nanopb/master/generator/proto/nanopb.proto \
    -o "/tmp/proto-${PROTO_VERSION}-copy/nanopb.proto"

  echo "$PROTO_VERSION" >> "$PROTO_MAP_FILE"
  rm -rf "$TMP_DIR"
done

# Compilazione dei proto
if [[ -s "$PROTO_MAP_FILE" ]]; then
  echo "📦 Compilazione .proto in un unico container…"
  docker run --rm \
    -v "$PWD":/app \
    -v /tmp:/tmp \
    -w /app \
    golang:1.21-bullseye bash -c '
      set -e
      apt-get update
      apt-get install -y unzip curl git protobuf-compiler
      go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.30.0
      export PATH=$PATH:$(go env GOPATH)/bin
      while read -r version; do
        rm -rf internal/proto/$version
        mkdir -p internal/proto/$version
        for f in /tmp/proto-$version-copy/*.proto /tmp/proto-$version-copy/meshtastic/*.proto; do
          [[ -f "$f" ]] || continue
          protoc \
            --experimental_allow_proto3_optional \
            -I /tmp/proto-$version-copy \
            --go_out=internal/proto/$version \
            --go_opt=paths=source_relative \
            --go_opt=Mnanopb.proto=meshspy/internal/proto/$version \
            "$f" || true
        done
      done < '"$PROTO_MAP_FILE"'
    '
  rm -f "$PROTO_MAP_FILE"
fi

# Verifica o rigenera go.mod
REQUIRES_GO=$(grep '^go [0-9]\.' go.mod 2>/dev/null | cut -d' ' -f2 || echo "")
if [[ ! -f go.mod || "$REQUIRES_GO" != "1.21" ]]; then
  echo "🛠 Generating or fixing go.mod and go.sum…"
  rm -f go.mod go.sum
  docker run --rm \
    -v "${PWD}":/app -w /app \
    golang:1.21-alpine sh -c "\
      go mod init ${IMAGE#*/} && \
      go get github.com/eclipse/paho.mqtt.golang@v1.5.0 github.com/tarm/serial@latest google.golang.org/protobuf@v1.30.0 && \
      go mod tidy"
fi

# Build multipiattaforma
declare -A GOARCH=( [armv6]=arm [armv7]=arm [arm64]=arm64 [amd64]=amd64 [386]=386 )
declare -A GOARM=(  [armv6]=6     [armv7]=7 )
declare -A MAN_OPTS=(
    [armv6]="--os linux --arch arm --variant v6"
  [armv7]="--os linux --arch arm --variant v7"
  [arm64]="--os linux --arch arm64"
  [amd64]="--os linux --arch amd64"
  [386]="--os linux --arch 386"
)

# Setup buildx
if ! docker buildx inspect meshspy-builder &>/dev/null; then
  docker buildx create --name meshspy-builder --use
fi
docker buildx use meshspy-builder
docker buildx inspect --bootstrap

# 🔨 Build ARMv6 separata (immagine base compatibile)
echo "🐹 Build ARMv6 con arm32v6/golang:1.22.9-alpine"
docker buildx build \
  --platform "$ARCH_ARMV6" \
  --push \
  -t "${IMAGE}:${TAG}-armv6" \
  --build-arg BASE_IMAGE=arm32v6/golang:1.22.9-alpine \
  .

# 🚀 Build parallela per tutte le altre architetture
echo "🚀 Build & push multipiattaforma per: $PLATFORMS_PARALLEL"
docker buildx build \
  --platform "$PLATFORMS_PARALLEL" \
  --push \
  -t "${IMAGE}:${TAG}" \
  --build-arg BASE_IMAGE=golang:1.21-bullseye \
  .

# (Opzionale) 👉 Unione ARMv6 nel manifest principale
echo "🔗 Creazione manifest multipiattaforma completo (facoltativo)"
docker manifest create "${IMAGE}:${TAG}" \
  "${IMAGE}:${TAG}-armv6" \
  "${IMAGE}:${TAG}"

docker manifest push "${IMAGE}:${TAG}"

echo "✅ Done! Multiarch image ready: ${IMAGE}:${TAG}"
