# LLaMA Runtime Environment

Runtime environment for deploying LLaMA 2 7B inference server. This environment is designed to consume the `llama-model` and `llama-server` packages built in the `llama-build` environment.

## Overview

This Flox environment provides a production-ready runtime for the LLaMA 2 inference server with:
- Configured environment variables for model path and server settings
- Service definition for running the inference server
- Logging and monitoring support
- Ready for Kubernetes deployment

## Environment Variables

### MODEL_PATH
Path to LLaMA 2 7B model files.

- **Default**: `${FLOX_ENV}/share/models/llama-2-7b-hf`
- **Override**: `MODEL_PATH=/path/to/model flox activate`
- **Required**: Yes (server will not start without a valid model path)

### Server Configuration

The server binds to `0.0.0.0:8000` (hardcoded in llama-server launcher script).
- Host: `0.0.0.0` (network-accessible)
- Port: `8000`

To use different host/port, you would need to rebuild llama-server with modified launcher script.

## Usage

### Prerequisites

The following packages must be installed or published to FloxHub:
- `llama-model` - LLaMA 2 7B model files (built in `../llama-build`)
- `llama-server` - FastAPI inference server (built in `../llama-build`)

To install from FloxHub after publishing:
```bash
flox install owner/llama-2-7b-hf-model owner/llama-server
```

### Running the Server

**Interactive mode** (with shell access):
```bash
flox activate --start-services
```

**Non-interactive mode** (run server directly):
```bash
flox activate -- llama-server
```

**With custom model path**:
```bash
MODEL_PATH=/path/to/model flox activate --start-services
```

**Note**: Host and port are hardcoded (0.0.0.0:8000) in the llama-server package.

### Server Endpoints

Once running, the server exposes:
- `GET /health` - Health check
- `POST /generate` - Generate text from prompt
- `GET /` - API information
- `GET /docs` - Interactive API documentation (Swagger UI)

### Logs

Server logs are written to: `$FLOX_ENV_CACHE/logs/llama-server.log`

To view logs:
```bash
tail -f .flox/cache/logs/llama-server.log
```

### Managing the Service

```bash
# Check service status
flox services status

# View service logs
flox services logs llama-server

# Restart service
flox services restart llama-server

# Stop all services
flox services stop
```

## Kubernetes Deployment

This environment is designed for imageless Kubernetes deployment using Flox's containerd runtime shim.

### Prerequisites

1. Push environment to FloxHub:
```bash
flox push
```

2. Install Flox runtime on K8s nodes and create RuntimeClass (see FLOX.md §14)

### Pod Configuration

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: llama-inference
  annotations:
    flox.dev/environment: "owner/llama-runtime"
spec:
  runtimeClassName: flox
  containers:
    - name: server
      image: flox/empty:1.0.0
      command: ["llama-server"]
      ports:
        - containerPort: 8000
      env:
        - name: MODEL_PATH
          value: "/nix/store/.../share/models/llama-2-7b-hf"  # Set by flox environment
```

See `../k8s/` directory for complete deployment manifests (Stage 6).

## Development Workflow

**Local testing**:
```bash
cd llama-runtime
flox activate --start-services
curl http://localhost:8000/health
```

**Update environment**:
```bash
flox install updated-package
flox push  # Creates new generation on FloxHub
```

**Deploy to K8s**:
```bash
kubectl apply -f ../k8s/deployment.yaml
# Pods automatically pull new generation from FloxHub
```

## Architecture

```
┌─────────────────────────────────────────┐
│         llama-runtime environment       │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │  Environment Variables           │  │
│  │  - MODEL_PATH                    │  │
│  │  (Server: 0.0.0.0:8000)          │  │
│  └──────────────────────────────────┘  │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │  Installed Packages              │  │
│  │  - llama-server (FastAPI + deps) │  │
│  │  - llama-model (25GB model files)│  │
│  └──────────────────────────────────┘  │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │  Service: llama-server           │  │
│  │  → Activates Python venv         │  │
│  │  → Validates MODEL_PATH          │  │
│  │  → Runs uvicorn server           │  │
│  │  → Logs to $FLOX_ENV_CACHE/logs  │  │
│  └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## See Also

- `../llama-build/` - Build environment for creating packages
- `../k8s/` - Kubernetes deployment manifests (Stage 6)
- FLOX.md §14 - Kubernetes deployment guide
- FLOX.md §8 - Services documentation
