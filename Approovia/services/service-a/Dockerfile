# Multi-stage build for lean and secure images
FROM golang:1.21-alpine AS builder

# Install ca-certificates and create non-root user
RUN apk add --no-cache ca-certificates tzdata
RUN adduser -D -g '' appuser

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum* ./
RUN go mod download

# Copy source code
COPY . .

# Build binary - let Docker detect the target architecture automatically
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags='-w -s -extldflags "-static"' \
    -a -installsuffix cgo \
    -o service-a .

# Final stage - use alpine instead of scratch for better compatibility
FROM alpine:latest

# Install ca-certificates and create user
RUN apk --no-cache add ca-certificates tzdata && \
    addgroup -g 1001 appgroup && \
    adduser -u 1001 -G appgroup -s /bin/sh -D appuser

# Copy binary and make it executable
COPY --from=builder /app/service-a /usr/local/bin/service-a
RUN chmod +x /usr/local/bin/service-a

# Use non-root user for security
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run binary
ENTRYPOINT ["/usr/local/bin/service-a"]
