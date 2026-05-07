FROM --platform=${BUILDPLATFORM} golang:1.25 AS builder

ARG TARGETARCH
ARG VERSION=v0.0.0-fork

WORKDIR /workspace

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build \
    -ldflags "-X main.version=${VERSION} -X main.buildHash=$(git rev-parse HEAD 2>/dev/null || echo unknown) -X main.buildDate=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    -o bin/controller ./cmd/controller

FROM gcr.io/distroless/static:nonroot

WORKDIR /
COPY --from=builder /workspace/bin/controller ./bin/controller
USER 65532:65532

ENTRYPOINT ["./bin/controller"]
