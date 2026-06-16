FROM golang:1.22-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags "-s -w" -o /sideweed .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=builder /sideweed /usr/local/bin/sideweed
EXPOSE 8880
ENTRYPOINT ["sideweed"]
