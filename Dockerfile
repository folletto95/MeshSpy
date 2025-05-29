# syntax=docker/dockerfile:1.4

###########################
# 🔨 STAGE: Builder
###########################

# Base immagine selezionata dinamicamente via --build-arg BASE_IMAGE
ARG BASE_IMAGE=golang:1.21-bullseye
FROM ${BASE_IMAGE} AS builder

ARG GOOS=linux
ARG GOARCH=amd64
ARG GOARM

ENV CGO_ENABLED=0 \
    GOOS=${GOOS} \
    GOARCH=${GOARCH} \
    GOARM=${GOARM}

WORKDIR /app

# Scarica i moduli Go
COPY go.mod ./
COPY go.sum ./
RUN go mod download

# Copia i sorgenti
COPY . .

# Compila il binario in modo statico e ottimizzato
RUN go build -ldflags="-s -w" -o meshspy .

###########################
# 🏁 STAGE: Runtime finale
###########################

FROM alpine:3.18

WORKDIR /app
COPY --from=builder /app/meshspy .

ENTRYPOINT ["./meshspy"]
