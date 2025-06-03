# syntax=docker/dockerfile:1.4

###########################
# 🔨 STAGE: Builder
###########################

ARG BASE_IMAGE
FROM ${BASE_IMAGE:-golang:1.21-bullseye} AS builder

ARG GOOS=linux
ARG GOARCH=arm
ARG GOARM=6

ENV CGO_ENABLED=0 \
    GOOS=${GOOS} \
    GOARCH=${GOARCH} \
    GOARM=${GOARM}

WORKDIR /app

# 🔁 Installa git condizionalmente (Alpine vs Debian)
RUN echo "🔧 Installing git depending on base image: ${BASE_IMAGE}" && \
    if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && apt-get install -y git protobuf-compiler curl unzip; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache git protobuf protoc curl unzip; \
    else \
        echo "❌ Unsupported package manager" && exit 1; \
    fi

# Scarica i moduli Go del progetto principale
COPY go.mod ./
COPY go.sum ./
RUN go mod download

# Copia i sorgenti principali
COPY . .

# ✅ Installa protoc-gen-go e compila i file .proto
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.30.0
ENV PATH="${PATH}:/go/bin"
RUN mkdir -p meshspy/proto/local && \
    protoc --proto_path=proto \
           --go_out=meshspy/proto/local \
           --go_opt=paths=source_relative \
           proto/data.proto

# ✅ COMPILA meshspy
RUN go build -ldflags="-s -w" -o meshspy ./cmd/meshspy

# ✅ CLONA E COMPILA meshtastic-go
RUN git clone https://github.com/lmatte7/meshtastic-go.git /tmp/meshtastic-go \
    && cd /tmp/meshtastic-go \
    && go build -ldflags="-s -w" -o /usr/local/bin/meshtastic-go \
    && chmod +x /usr/local/bin/meshtastic-go

###########################
# 🏁 STAGE: Runtime finale
###########################

FROM alpine:3.18

WORKDIR /app

# Copia binario principale
COPY --from=builder /app/meshspy .

# Copia binario meshtastic-go
COPY --from=builder /usr/local/bin/meshtastic-go /usr/local/bin/meshtastic-go

COPY proto/ ./proto/

###########################
# 🛠️ ENV: Runtime config
###########################

# Copia il file .env.runtime nel container (se presente)
RUN echo "copio .env.runtime"
COPY .env.runtime /app/.env.runtime
RUN echo "copiato .env.runtime"
RUN echo "copio .env.example"
COPY .env.example /app/.env.example
RUN echo "copiato .env.example"

# Avvio del servizio principale
ENTRYPOINT ["./meshspy"]
