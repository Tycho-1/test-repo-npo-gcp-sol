FROM golang:1.23 AS builder

# Create and change to the app directory.
WORKDIR /app

# Retrieve application dependencies.
# This allows the container build to reuse cached dependencies.
COPY go.* ./
RUN go mod download

# Copy local code to the container image.
COPY .  ./

#WORKDIR /app/cmd/webserver
# Build the binary.
# -mod=readonly switch is used to force failure of the build if the go.mod file needs changes to succeed.
# see https://golang.org/cmd/go/#hdr-Preliminary_module_support for more details.
RUN GO111MODULE=on CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build bq_load_json_file.go   

# Use the Google Distroless image for a minimal container.
FROM gcr.io/distroless/static

# Copy the binary to the production image from the builder stage.
COPY --from=builder /app/bq_load_json_file /bq_load_json_file

# Run the app on container startup.
CMD ["/bq_load_json_file"]
