# KijaniKiosk Track A Capstone

This directory contains the production-approaching, multi-environment deployment
implementation for KijaniKiosk.

## Step 1: provision and configure staging

Terraform owns creation of the `kijani-staging` namespace. Ansible then applies
staging-only resource limits and network isolation. Production continues to use
Kubernetes' `default` namespace and is never managed by these staging commands.

```bash
cd terraform
terraform init
terraform apply

cd ../ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook kijani-staging.yml
```

Set `KUBECONFIG` for Ansible or `TF_VAR_kubeconfig_path` for Terraform when your
cluster configuration is not at `~/.kube/config`. Set `KUBE_CONTEXT` or
`TF_VAR_kubeconfig_context` to select a non-default context.

The Ansible playbook deliberately fails if Terraform has not first created the
namespace. Its NetworkPolicies deny traffic from other namespaces, including
`default`, while allowing communication among staging pods.

## Step 2: deploy the shared payment workload

The `k8s/base` directory contains the single, namespace-neutral Deployment and
Service used by both environments. Kustomize overlays provide the namespace and
environment-specific ConfigMap values. The `DB_HOST` values are deliberately
different: staging uses `postgres-staging.kijani.internal`, while production
uses `postgres-prod.kijani.internal`.

Create `kk-payments-secrets` and `kijani-registry-credentials` in each target
namespace before deployment; never commit their values. Then render or apply an
environment explicitly:

```bash
kubectl kustomize k8s/overlays/staging
kubectl apply -k k8s/overlays/staging

kubectl kustomize k8s/overlays/production
kubectl apply -k k8s/overlays/production
```

Kustomize generates the ConfigMap name and updates the Deployment's
`configMapRef` to that generated name, which ensures a configuration change
causes a new rollout without duplicating the Deployment manifest.

## Step 3: Jenkins promotion flow

Configure the Jenkins multibranch job with script path
`kijani-capstone/Jenkinsfile` and add a **Secret file** credential named
`kijanikiosk-kubeconfig`. The pipeline runs from the repository root and
references the manifests under `kijani-capstone/k8s`. Its kubeconfig identity
must be able to deploy to `kijani-staging` and `default`.

That secret file must be self-contained. If it still references Minikube-local
paths such as `~/.minikube/profiles/minikube/client.crt`, `client.key`, or
`ca.crt`, Jenkins will fail when the agent cannot resolve those files. Rebuild
the kubeconfig with embedded data before uploading it, for example:

```bash
kubectl config view --raw --flatten --minify > kubeconfig
```

Every branch validates both Kustomize overlays. A build on `develop` (including a
merge to `develop`) then runs the release sequence below:

1. Applies the staging overlay and waits for `kk-payments` to become ready.
2. Runs a disposable in-cluster curl pod against `http://kk-payments:3001/health`.
3. Presents a 15-minute production approval gate only if the preceding smoke
   test succeeded.
4. Applies the production overlay after an approved gate.

The smoke pod runs in `kijani-staging`, so it is permitted by the namespace's
internal-only NetworkPolicy. The Jenkins agent needs `kubectl` with Kustomize
support and permission to pull `curlimages/curl:8.12.1` in staging.

## Step 4: observability promotion guardrail

The staging overlay includes a `PrometheusRule` for the critical
`KKPaymentsHighErrorRate` alert. It uses the Ingress NGINX request counter and
fires when staging 5xx responses exceed 5% for two minutes. The Jenkins
pipeline waits 150 seconds after the smoke test, then queries Prometheus for
the rule's firing series. A firing alert fails the build before the approval
gate is reached.

Install the monitoring prerequisites described in
[`k8s/observability/README.md`](k8s/observability/README.md) before running the
pipeline. The pipeline verifies the PrometheusRule CRD, ingress controller, and
Prometheus service explicitly, so it cannot silently bypass this guardrail.
