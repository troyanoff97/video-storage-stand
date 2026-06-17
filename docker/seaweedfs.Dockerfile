# Build SeaweedFS from local fork checkout (./seaweedfs).
# Context: ./seaweedfs
FROM golang:1.22-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY weed/ ./weed/

ARG GIT_COMMIT=local
RUN CGO_ENABLED=0 go build -C weed \
    -ldflags "-s -w -extldflags -static -X github.com/seaweedfs/seaweedfs/weed/util.COMMIT=${GIT_COMMIT}" \
    -o /weed .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates curl fuse
COPY --from=builder /weed /usr/bin/weed
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/recovery-disk-entrypoint.sh /recovery-disk-entrypoint.sh
COPY docker/filer.toml /etc/seaweedfs/filer.toml
RUN chmod +x /entrypoint.sh /recovery-disk-entrypoint.sh
WORKDIR /data
VOLUME /data
EXPOSE 9333 8080 8888 8333
ENTRYPOINT ["/entrypoint.sh"]
