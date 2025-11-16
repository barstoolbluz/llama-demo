# LLaMA Kubernetes Deployment

Kubernetes manifests for deploying LLaMA 2 7B inference server using Flox imageless containers.

## Overview

This deployment uses Flox's containerd runtime shim to run the `llama-runtime` environment directly on Kubernetes without building or pushing container images. The environment is pulled from FloxHub at pod startup.

## Architecture

```
┌──────────────────────────────────────────────┐
│         Kubernetes Cluster                   │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │  RuntimeClass: flox                    │ │
│  │  - Routes pods to Flox runtime shim    │ │
│  │  - Schedules on labeled nodes          │ │
│  └────────────────────────────────────────┘ │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │  Deployment: llama-inference           │ │
│  │  - Replicas: 2                         │ │
│  │  - Environment: owner/llama-runtime    │ │
│  │  - Image: flox/empty:1.0.0 (stub)      │ │
│  │  - Health checks: /health endpoint     │ │
│  └────────────────────────────────────────┘ │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │  Service: llama-inference              │ │
│  │  - Type: ClusterIP                     │ │
│  │  - Port: 8000                          │ │
│  └────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

## Prerequisites

### 1. Flox Runtime Installation on Cluster Nodes

Install Flox on each K8s node:
```bash
# See https://flox.dev/docs/install for your platform
curl -fsSL https://flox.dev/install | bash
```

### 2. Install Containerd Runtime Shim

**Automatic installation** (recommended):
```bash
# Run on each node
sudo flox activate -r flox/containerd-shim-flox-installer --trust
```

**Manual installation** (for k3s or custom containerd):
```bash
# Create environment with shim
mkdir containerd-shim-flox && cd containerd-shim-flox
flox init -b
flox install containerd-shim-flox-2x  # Use -17 for containerd 1.7

# Symlink to system path
sudo ln -s $PWD/.flox/run/x86_64-linux.containerd-shim-flox.run/bin/containerd-shim-flox-v2 \
  /usr/local/bin/containerd-shim-flox-v2
```

### 3. Configure Containerd

Add to `/etc/containerd/config.toml`:

**For containerd 2.x**:
```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.flox]
    runtime_path = "/usr/local/bin/containerd-shim-flox-v2"
    runtime_type = "io.containerd.runc.v2"
    pod_annotations = [ "flox.dev/*" ]
    container_annotations = [ "flox.dev/*" ]
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.flox.options]
    SystemdCgroup = true
```

**For containerd 1.x** (k3s):
```toml
[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.flox]
    runtime_path = "/usr/local/bin/containerd-shim-flox-v2"
    runtime_type = "io.containerd.runc.v2"
    pod_annotations = [ "flox.dev/*" ]
    container_annotations = [ "flox.dev/*" ]
[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.flox.options]
    SystemdCgroup = true
```

Restart containerd:
```bash
sudo systemctl restart containerd
# For k3s: sudo systemctl restart k3s
```

Verify installation:
```bash
containerd config dump | grep -A 10 "flox"
```

### 4. Label Nodes

Label nodes that have Flox runtime installed:
```bash
kubectl label node <node-name> "flox.dev/enabled=true"

# Label all nodes (if all have Flox):
kubectl label nodes --all "flox.dev/enabled=true"
```

### 5. Publish Runtime Environment to FloxHub

```bash
cd ../llama-runtime
flox push
# Environment available as: owner/llama-runtime
```

## Deployment

### 1. Create RuntimeClass

```bash
kubectl apply -f runtimeclass.yaml
```

Verify:
```bash
kubectl get runtimeclass flox
```

### 2. Update Deployment Manifest

Edit `deployment.yaml` and update the FloxHub environment reference:

```yaml
annotations:
  flox.dev/environment: "your-username/llama-runtime"
```

### 3. Deploy Application

```bash
# Apply all manifests
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

### 4. Verify Deployment

```bash
# Check pods
kubectl get pods -l app=llama-inference

# Check pod events
kubectl describe pod -l app=llama-inference

# View logs
kubectl logs -l app=llama-inference

# Check service
kubectl get svc llama-inference
```

## Usage

### Access Service from Within Cluster

```bash
# Port-forward for testing
kubectl port-forward svc/llama-inference 8000:8000

# Test health endpoint
curl http://localhost:8000/health

# Test inference
curl -X POST http://localhost:8000/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Once upon a time", "max_length": 50}'

# View API docs
open http://localhost:8000/docs
```

### Access via Service DNS (from within cluster)

```bash
# From another pod
curl http://llama-inference.default.svc.cluster.local:8000/health
```

### External Access (Optional)

Uncomment and apply the Ingress section in `service.yaml`:

```bash
kubectl apply -f service.yaml

# Access via ingress
curl https://llama.example.com/health
```

## Updating the Environment

### Update Packages

```bash
cd ../llama-runtime
flox install updated-package
flox push
# This creates a new generation (e.g., @13)
```

### Deploy Update

**Development/staging** (auto-updates):
```yaml
flox.dev/environment: "owner/llama-runtime"  # Always pulls latest
```
```bash
kubectl rollout restart deployment/llama-inference
```

**Production** (pinned generation):
```yaml
# Update to new generation after testing
flox.dev/environment: "owner/llama-runtime@13"
```
```bash
kubectl apply -f deployment.yaml
```

### Rollback

```bash
# Edit deployment to previous generation
kubectl edit deployment llama-inference
# Change: flox.dev/environment: "owner/llama-runtime@12"

# Or rollback deployment
kubectl rollout undo deployment/llama-inference
```

## Scaling

### Horizontal Scaling

```bash
# Scale replicas
kubectl scale deployment llama-inference --replicas=5

# Autoscaling (requires metrics-server)
kubectl autoscale deployment llama-inference \
  --min=2 --max=10 --cpu-percent=70
```

### Vertical Scaling

Edit resource requests/limits in `deployment.yaml`:
```yaml
resources:
  requests:
    memory: "16Gi"
    cpu: "4000m"
  limits:
    memory: "32Gi"
    cpu: "8000m"
```

## Monitoring

### Pod Logs

```bash
# Follow logs from all pods
kubectl logs -f -l app=llama-inference

# Logs from specific pod
kubectl logs -f llama-inference-<pod-id>

# Previous pod logs (if crashed)
kubectl logs --previous llama-inference-<pod-id>
```

### Health Checks

```bash
# Test liveness probe
kubectl exec -it llama-inference-<pod-id> -- curl localhost:8000/health

# View probe status
kubectl describe pod llama-inference-<pod-id> | grep -A 10 "Liveness\|Readiness"
```

### Metrics

```bash
# Resource usage
kubectl top pods -l app=llama-inference

# Node metrics
kubectl top nodes -l flox.dev/enabled=true
```

## Troubleshooting

### Pods Stuck in ContainerCreating

**Check events**:
```bash
kubectl describe pod llama-inference-<pod-id>
```

**Common issues**:
1. **Shim not installed**: Verify with `containerd config dump | grep flox`
2. **Node not labeled**: Check `kubectl get nodes -L flox.dev/enabled`
3. **Environment not found**: Verify `flox show owner/llama-runtime`

**Check containerd logs**:
```bash
journalctl -u containerd -n 100
# For k3s: journalctl -u k3s -n 100
```

### Pods Failing Health Checks

```bash
# Check if server is running
kubectl exec -it llama-inference-<pod-id> -- ps aux

# Check server logs
kubectl logs llama-inference-<pod-id>

# Test health endpoint manually
kubectl exec -it llama-inference-<pod-id> -- curl -v localhost:8000/health
```

### Model Not Found

```bash
# Check MODEL_PATH in pod
kubectl exec -it llama-inference-<pod-id> -- env | grep MODEL_PATH

# Verify model files exist
kubectl exec -it llama-inference-<pod-id> -- ls -la /nix/store/.../share/models/

# Check if llama-model package is installed in environment
flox show owner/llama-runtime
```

### Environment Pull Failures

```bash
# Check FloxHub authentication on node
ssh node-name
flox auth status

# Re-authenticate
flox auth login
```

## Production Considerations

### Node Provisioning

Include shim installation in node bootstrap:
```bash
#!/bin/bash
# In node startup script
curl -fsSL https://flox.dev/install | bash
sudo flox activate -r flox/containerd-shim-flox-installer --trust
```

### Security

**Private environments** - Configure FloxHub authentication:
```bash
# On each node
export FLOXHUB_TOKEN=<service-account-token>
flox auth login --token $FLOXHUB_TOKEN
```

**Network policies** - Restrict pod network access:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: llama-inference
spec:
  podSelector:
    matchLabels:
      app: llama-inference
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}
      ports:
        - port: 8000
```

### Resource Management

**Resource quotas**:
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: llama-quota
spec:
  hard:
    requests.cpu: "20"
    requests.memory: "80Gi"
    limits.cpu: "40"
    limits.memory: "160Gi"
```

**Pod disruption budgets**:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: llama-inference
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: llama-inference
```

### High Availability

- Deploy across multiple availability zones
- Use pod anti-affinity to spread pods across nodes
- Set minAvailable in PodDisruptionBudget
- Use generation pinning for production deployments

## Local Testing

### kind (Kubernetes in Docker)

```bash
# Create cluster
kind create cluster --name llama-test

# Load Flox runtime (if using local builds)
# Note: Flox runtime shim must be installed on kind nodes

# Deploy
kubectl apply -f runtimeclass.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Test
kubectl port-forward svc/llama-inference 8000:8000
curl http://localhost:8000/health
```

### k3s (Lightweight Kubernetes)

```bash
# Install k3s
curl -sfL https://get.k3s.io | sh -

# Install Flox runtime shim (see Prerequisites)

# Deploy
kubectl apply -f runtimeclass.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

## See Also

- `../llama-build/` - Build environment for creating packages
- `../llama-runtime/` - Runtime environment configuration
- FLOX.md §14 - Complete Kubernetes deployment guide
- https://flox.dev/docs/k8s - Platform-specific K8s setup guides
