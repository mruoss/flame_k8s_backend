# FLAMEK8sBakend

A [FLAME](https://github.com/phoenixframework/flame/tree/main) Backend for
Kubernetes. Manages pods as runners in the cluster the app is running in.

[![Module Version](https://img.shields.io/hexpm/v/flame_k8s_backend.svg)](https://hex.pm/packages/flame_k8s_backend)
[![Last Updated](https://img.shields.io/github/last-commit/mruoss/flame_k8s_backend.svg)](https://github.com/mruoss/flame_k8s_backend/commits/main)

[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/flame_k8s_backend/)
[![Total Download](https://img.shields.io/hexpm/dt/flame_k8s_backend.svg)](https://hex.pm/packages/flame_k8s_backend)
[![License](https://img.shields.io/hexpm/l/flame_k8s_backend.svg)](https://github.com/mruoss/flame_k8s_backend/blob/main/LICENSE)

The current implementation is very basic and more like a proof of concept.
More configuration options (resources, etc.) will follow.

## Installation

```elixir
def deps do
  [
    {:flame_k8s_backend, "~> 0.1.0"}
  ]
end
```

## Requirements

### Env Variables

In order for the runners to be able to join the cluster, you need to configure
a few environment variables on your pod/deployment:

The `POD_NAME` and `POD_NAMESPACE` are used by the backend to get informations
from your pod and use them for the runner pods (e.g. env variables).

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  selector:
    matchLabels:
      app: myapp
  template:
    spec:
      metadata:
        app: myapp
      containers:
        - env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: metadata.namespace
```

### RBAC

Your application needs run as a service account with permissions to manage
pods:

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp
  namespace: michael-playground
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: michael-playground
  name: pod-mgr
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "get", "list", "delete", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: myapp-pod-mgr
  namespace: michael-playground
subjects:
  - kind: ServiceAccount
    name: myapp
    namespace: michael-playground
roleRef:
  kind: Role
  name: pod-mgr
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      serviceAccountName: flame-test
```

### Clustering

Your application needs to be able to form a cluster with your runners. Pass the
following variables to your pods:

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - env:
            - name: POD_IP
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: status.podIP
            - name: RELEASE_DISTRIBUTION
              value: name
            - name: RELEASE_NODE
              value: flame_test@$(POD_IP)
```
