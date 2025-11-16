# LLaMA 2 7B Inference with Flox

End-to-end deployment of LLaMA 2 7B inference server using Flox for reproducible builds and imageless Kubernetes deployment.

## Project Structure

```
llama-demo/
├── llama-build/          # Build environment (Stage 2)
│   ├── .flox/
│   │   ├── pkgs/
│   │   │   ├── llama-model.nix    # Nix expression: Download & package LLaMA 2 model
│   │   │   └── llama-server.nix   # Nix expression: Build FastAPI inference server
│   │   └── env/
│   │       └── manifest.toml      # Build environment dependencies
│   └── server/
│       └── server.py              # FastAPI inference application
│
├── llama-runtime/        # Runtime environment (Stage 5)
│   ├── .flox/
│   │   └── env/
│   │       └── manifest.toml      # Runtime configuration & services
│   └── README.md                  # Runtime usage guide
│
├── k8s/                  # Kubernetes manifests (Stage 6)
│   ├── runtimeclass.yaml          # Flox RuntimeClass definition
│   ├── deployment.yaml            # LLaMA inference Deployment
│   ├── service.yaml               # ClusterIP Service
│   └── README.md                  # K8s deployment guide
│
└── README.md            # This file
```

## Overview

This project demonstrates a complete ML inference deployment pipeline using Flox:

1. **Build Stage** (`llama-build/`): Nix expression builds for reproducible packaging
2. **Runtime Stage** (`llama-runtime/`): Configured environment for running the server
3. **Deployment Stage** (`k8s/`): Kubernetes manifests for production deployment

### Key Features

- **Reproducible Builds**: Nix expressions with Fixed-Output Derivation (FOD) pattern
- **Imageless Containers**: Deploy directly from FloxHub without building Docker images
- **Version Management**: Environment generations provide audit trail and easy rollback
- **Fast Iteration**: Update dependencies → push to FloxHub → redeploy pods (no image builds)
- **Consistent Environments**: Same dependencies from local dev to production

## Quick Start

### Prerequisites

- [Flox](https://flox.dev/docs/install) installed
- HuggingFace account with access to LLaMA 2 model
- `HF_TOKEN` environment variable set

### 1. Build Packages

```bash
cd llama-build

# Build inference server (fast)
flox build llama-server
# Output: ./result-llama-server

# Build model package (requires HF_TOKEN and 25GB download)
export HF_TOKEN=your_token
flox build llama-model
# Output: ./result-llama-model
```

### 2. Test Runtime Environment

```bash
cd ../llama-runtime

# Install packages (after publishing to FloxHub)
flox install owner/llama-server owner/llama-2-7b-hf-model

# Or test with local builds
MODEL_PATH=/path/to/model flox activate --start-services

# Test server
curl http://localhost:8000/health
curl -X POST http://localhost:8000/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Once upon a time", "max_length": 50}'
```

### 3. Deploy to Kubernetes

```bash
cd ../k8s

# Prerequisites: Install Flox runtime on K8s nodes (see k8s/README.md)

# Push runtime environment to FloxHub
cd ../llama-runtime
flox push

# Deploy to cluster
cd ../k8s
kubectl apply -f runtimeclass.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Verify
kubectl get pods -l app=llama-inference
kubectl logs -l app=llama-inference
```

## Build System Architecture

### Stage 2: Nix Expression Builds

The build environment uses **Fixed-Output Derivation (FOD)** pattern for network access during build:

**llama-server.nix**:
```
┌─────────────────────────────────────────┐
│  FOD Stage: pipCache                    │
│  - Network access allowed               │
│  - Downloads: fastapi, uvicorn,         │
│    transformers, torch-cpu              │
│  - Output hash verified                 │
│  → /nix/store/.../pip-cache             │
└─────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────┐
│  Build Stage: llama-server              │
│  - No network access                    │
│  - Uses cached pip packages             │
│  - Creates Python venv in $out          │
│  - Installs server.py                   │
│  - Creates launcher script              │
│  → /nix/store/.../llama-server          │
└─────────────────────────────────────────┘
```

**llama-model.nix**:
```
┌─────────────────────────────────────────┐
│  FOD Stage: modelCache                  │
│  - Network access allowed               │
│  - Downloads 25GB LLaMA 2 model         │
│  - Requires HF_TOKEN                    │
│  - Output hash verified                 │
│  → /nix/store/.../model-cache           │
└─────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────┐
│  Build Stage: llama-2-7b-hf-model       │
│  - Copies model to standard path        │
│  → /nix/store/.../share/models/         │
└─────────────────────────────────────────┘
```

## Deployment Workflow

### Development → CI → Production

```
┌──────────────────────────────────────────────────────────────┐
│ 1. Local Development                                         │
│    cd llama-build                                            │
│    flox build llama-server                                   │
│    # Test build locally                                      │
└──────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────┐
│ 2. Publish to FloxHub                                        │
│    cd llama-build                                            │
│    flox publish llama-server llama-model                     │
│    # Packages available as: owner/llama-server@N             │
└──────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────┐
│ 3. Configure Runtime                                         │
│    cd llama-runtime                                          │
│    flox install owner/llama-server owner/llama-model         │
│    # Test runtime environment                                │
│    flox activate --start-services                            │
└──────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────┐
│ 4. Push Runtime to FloxHub                                   │
│    flox push                                                 │
│    # Environment: owner/llama-runtime@1                      │
└──────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────┐
│ 5. Deploy to Staging K8s                                     │
│    kubectl apply -f k8s/                                     │
│    # Annotation: flox.dev/environment: owner/llama-runtime   │
│    # Pods pull environment from FloxHub                      │
└──────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────┐
│ 6. Test & Validate                                           │
│    kubectl port-forward svc/llama-inference 8000:8000        │
│    curl http://localhost:8000/health                         │
│    # Run inference tests                                     │
└──────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────┐
│ 7. Deploy to Production                                      │
│    # Update deployment.yaml to pin generation                │
│    # flox.dev/environment: owner/llama-runtime@1             │
│    kubectl apply -f k8s/deployment.yaml                      │
└──────────────────────────────────────────────────────────────┘
```

### Updating Deployments

**Scenario: Add new dependency (e.g., boto3)**

```bash
# 1. Update runtime environment
cd llama-runtime
flox install boto3
flox push
# Creates generation @2

# 2. Update staging deployment
kubectl patch deployment llama-inference -p \
  '{"spec":{"template":{"metadata":{"annotations":{"flox.dev/environment":"owner/llama-runtime@2"}}}}}'

# 3. Test in staging
kubectl logs -f -l app=llama-inference

# 4. Promote to production (update deployment.yaml)
kubectl apply -f k8s/deployment.yaml

# 5. Rollback if needed (instant)
kubectl patch deployment llama-inference -p \
  '{"spec":{"template":{"metadata":{"annotations":{"flox.dev/environment":"owner/llama-runtime@1"}}}}}'
```

## Technical Details

### Build System: Nix Expression with FOD Pattern

**Why Nix expressions instead of manifest builds?**
- **Hermetic builds**: Isolated from host system state
- **Reproducibility**: Pure functional builds with content-addressed storage
- **Network control**: FOD pattern allows network access for downloads while maintaining reproducibility

**FOD Pattern Benefits**:
1. Download dependencies once during build
2. Verify output with cryptographic hash
3. Cache downloads in `/nix/store` for reuse
4. Build stage runs without network access using cached downloads

### Runtime: Service-Based Deployment

The runtime environment defines a service that:
1. Validates `MODEL_PATH` exists
2. Activates Python virtualenv (from llama-server package)
3. Runs uvicorn server with configurable host/port
4. Logs output to `$FLOX_ENV_CACHE/logs/`

### Kubernetes: Imageless Containers

Instead of Docker images, pods reference Flox environments:

**Traditional approach**:
```
Code → Dockerfile → docker build → docker push → kubectl apply
       ↓            ↓               ↓
     Rebuild      Slow (minutes)  Large images (GB)
```

**Flox approach**:
```
Code → flox push → kubectl apply
       ↓           ↓
     Fast (seconds)  No images
```

**Benefits**:
- No image registry needed
- Instant rollback (change generation number)
- Dependencies cached on nodes (`/nix/store`)
- Same environment local → CI → production

## API Reference

### Inference Server Endpoints

**Health Check**
```bash
GET /health
```

**Generate Text**
```bash
POST /generate
Content-Type: application/json

{
  "prompt": "Once upon a time",
  "max_length": 50,
  "temperature": 0.7
}
```

**API Documentation**
```bash
GET /docs       # Swagger UI
GET /redoc      # ReDoc
```

## Performance

### Resource Requirements

**Per Pod**:
- Memory: 8-16GB (model size: ~7GB, inference overhead: ~1-9GB)
- CPU: 2-4 cores (CPU inference)
- Storage: Minimal (packages cached in `/nix/store` on node)

**Per Node**:
- Storage: ~30GB for `/nix/store` cache (shared across all pods)
- First pod on node: Downloads packages (~2 minutes)
- Subsequent pods: Instant start (packages cached)

### Scaling Considerations

- Horizontal scaling: Add replicas (load balancing across pods)
- Vertical scaling: Increase memory for larger batch sizes
- GPU support: Add GPU nodes and update resource requests (future enhancement)

## Troubleshooting

### Build Issues

**llama-server build fails with hash mismatch**:
```bash
# Nix shows correct hash in error message
# Update outputHash in llama-server.nix with provided hash
```

**llama-model build fails (HF_TOKEN)**:
```bash
export HF_TOKEN=your_token
flox build llama-model
```

### Runtime Issues

**Server fails to start (MODEL_PATH not found)**:
```bash
# Check if model package is installed
flox list

# Or override MODEL_PATH
MODEL_PATH=/path/to/model flox activate -s
```

### Kubernetes Issues

**Pods stuck in ContainerCreating**:
```bash
# Verify Flox runtime shim installed
kubectl describe pod <pod-name>
ssh node-name
containerd config dump | grep flox
```

**Environment not found**:
```bash
# Verify environment pushed to FloxHub
flox show owner/llama-runtime

# Check authentication on nodes
ssh node-name
flox auth status
```

See `k8s/README.md` for detailed troubleshooting.

## Contributing

1. Make changes in appropriate environment
2. Test locally with `flox activate`
3. Build packages with `flox build`
4. Commit changes and push to git
5. Publish packages with `flox publish`
6. Update runtime environment and push to FloxHub

## License

This project demonstrates Flox capabilities for ML deployment.
- LLaMA 2 model: Meta's LLaMA 2 license
- Project code: MIT

## Resources

- [Flox Documentation](https://flox.dev/docs)
- [Flox Kubernetes Guide](https://flox.dev/docs/k8s)
- [LLaMA 2 Model](https://huggingface.co/meta-llama/Llama-2-7b-hf)
- [FLOX.md](../flox-md/FLOX.md) - Complete Flox reference guide

## Project Stages

- ✅ Stage 1: Initial setup and planning
- ✅ Stage 2: Build environment with Nix expressions (llama-build/)
- ✅ Stage 5: Runtime environment configuration (llama-runtime/)
- ✅ Stage 6: Kubernetes deployment manifests (k8s/)
- ⏳ Future: GPU support, model optimization, monitoring
