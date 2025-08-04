# Stage 1: Build
FROM golang:1.21.9-bookworm AS builder

#Add this line to enable auto-download of newer Go toolchain
ENV GOTOOLCHAIN=auto

WORKDIR /app
COPY . .
RUN go build -o app .

# Stage 2: Lean Runtime
FROM debian:bookworm-slim
RUN useradd -m appuser
USER appuser
COPY --from=builder /app/app /app/app
EXPOSE 8080
ENTRYPOINT ["/app/app"]





