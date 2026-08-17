# KijaniKiosk Track A Capstone

This directory contains the production-approaching, multi-environment deployment
implementation for KijaniKiosk. The `kk-payments` service is deployed to both a
`kijani-staging` namespace (with network isolation and resource quotas) and the
`default` production namespace, managed through Terraform, Ansible, Kustomize,
and a Jenkins CI/CD pipeline with an observability-based promotion gate.

## Prerequisites

Install the following tools before starting. Versions listed are the minimum
tested against this repository.

| Tool | Minimum version | Purpose |
|---|---|---|
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.31 | Cluster interaction |
| [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) | 5.4.3 | Manifest overlay rendering |
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.6.0 | Namespace provisioning |
| [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) | 2.15+ | Namespace configuration |
| [Helm](https://helm.sh/docs/intro/install/) | 3.x | Ingress and monitoring charts |
| [Minikube](https://minikube.sigs.k8s.io/docs/start/) | 1.32+ | Local Kubernetes cluster |
| [Jenkins](https://www.jenkins.io/doc/) | 2.400+ | CI/CD pipeline (optional for local dev) |

Verify your installations:

```bash
kubectl version --client
kustomize version
terraform version
ansible --version
helm version
minikube version
```

## Cluster bootstrap

Start a local Minikube cluster with sufficient resources for all workloads:

```bash
minikube start --cpus=4 --memory=8192 --driver=docker
```

Add the required Helm repositories and install the Ingress NGINX controller
and kube-prometheus-stack. These are mandatory for the pipeline's smoke tests
and observability guardrail.

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.metrics.enabled=true

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values k8s/observability/kube-prometheus-stack-values.yml
```

The Prometheus values file configures the operator to discover `PrometheusRule`
resources across all namespaces, which is required for the staging alert
guardrail to function.

Wait for the controllers to become ready:

```bash
kubectl wait --for=condition=Available deployment/ingress-nginx-controller \
  -n ingress-nginx --timeout=120s

kubectl wait --for=condition=Available deployment/kube-prometheus-stack-prometheus \
  -n monitoring --timeout=120s
```

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

Verify the namespace and its guardrails:

```bash
kubectl get ns kijani-staging --show-labels
kubectl get resourcequota -n kijani-staging
kubectl get limitrange -n kijani-staging
kubectl get networkpolicy -n kijani-staging
```

## Step 2: create secrets

Create the required secrets in each target namespace **before** deploying.
Never commit real secret values to the repository.

### kk-payments-secrets

Copy the example template and fill in real values for each environment:

```bash
cp k8s/base/kk-payments-secrets.yaml.example kk-payments-secrets.yaml
```

Edit `kk-payments-secrets.yaml` and set `DB_PASSWORD`, `STRIPE_API_KEY`, and
`JWT_SECRET` for staging, then apply it:

```bash
kubectl apply -f kk-payments-secrets.yaml -n kijani-staging
```

Repeat with production values for the `default` namespace:

```bash
kubectl apply -f kk-payments-secrets.yaml -n default
```

### kijani-registry-credentials

The Deployment references an `imagePullSecret` named `kijani-registry-credentials`
to pull the `nebulascout/kk-payments` image. Create it in each namespace:

```bash
kubectl create secret docker-registry kijani-registry-credentials \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<your-dockerhub-username> \
  --docker-password=<your-dockerhub-token> \
  -n kijani-staging

kubectl create secret docker-registry kijani-registry-credentials \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<your-dockerhub-username> \
  --docker-password=<your-dockerhub-token> \
  -n default
```

Verify both secrets exist:

```bash
kubectl get secret kk-payments-secrets -n kijani-staging
kubectl get secret kijani-registry-credentials -n kijani-staging
kubectl get secret kk-payments-secrets -n default
kubectl get secret kijani-registry-credentials -n default
```

## Step 3: deploy the shared payment workload

The `k8s/base` directory contains the single, namespace-neutral Deployment and
Service used by both environments. Kustomize overlays provide the namespace and
environment-specific ConfigMap values. The `DB_HOST` values are deliberately
different: staging uses `postgres-staging.kijani.internal`, while production
uses `postgres-prod.kijani.internal`.

Render or apply an environment explicitly:

```bash
kubectl kustomize k8s/overlays/staging
kubectl apply -k k8s/overlays/staging

kubectl kustomize k8s/overlays/production
kubectl apply -k k8s/overlays/production
```

Kustomize generates the ConfigMap name and updates the Deployment's
`configMapRef` to that generated name, which ensures a configuration change
causes a new rollout without duplicating the Deployment manifest.

Verify the deployment rolled out successfully:

```bash
kubectl get deploy,svc -n kijani-staging
kubectl rollout status deploy/kk-payments -n kijani-staging --timeout=120s

kubectl get deploy,svc -n default
kubectl rollout status deploy/kk-payments -n default --timeout=120s
```

## Step 4: Jenkins promotion flow

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

## Step 5: observability promotion guardrail

The staging overlay includes a `PrometheusRule` for the critical
`KKPaymentsHighErrorRate` alert. It uses the Ingress NGINX request counter and
fires when staging 5xx responses exceed 5% for two minutes. The Jenkins
pipeline waits 150 seconds after the smoke test, then queries Prometheus for
the rule's firing series. A firing alert fails the build before the approval
gate is reached.

The pipeline verifies the PrometheusRule CRD, ingress controller, and Prometheus
service explicitly, so it cannot silently bypass this guardrail.

Verify the monitoring stack and alert rule:

```bash
kubectl get prometheusrule kk-payments-staging-alerts -n kijani-staging
kubectl get svc -n ingress-nginx
kubectl get svc -n monitoring
```

Port-forward to Prometheus and confirm the rule is loaded:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

Open `http://127.0.0.1:9090/rules` in a browser and locate
`KKPaymentsHighErrorRate` under the staging rules.

Full observability setup details are in
[`k8s/observability/README.md`](k8s/observability/README.md).

## Troubleshooting

### `CreateContainerConfigError` — secrets not found

The pod events will show `secret "kk-payments-secrets" not found`. This means
the secrets from [Step 2](#step-2-create-secrets) have not been created in the
target namespace. Create them before applying the Kustomize overlay.

### `ImagePullBackOff` — registry credentials missing

The Deployment references `imagePullSecret: kijani-registry-credentials`. If
this secret does not exist in the namespace, the kubelet cannot pull the
`nebulascout/kk-payments` image. Create the `docker-registry` secret as shown
in [Step 2](#step-2-create-secrets).

### Ansible fails — namespace does not exist

The Ansible playbook requires the `kijani-staging` namespace to already exist.
Run the Terraform apply step first. The playbook will fail with a clear error
if the namespace is missing.

### PrometheusRule not found in Prometheus UI

Ensure the kube-prometheus-stack was installed with the custom values file
(`k8s/observability/kube-prometheus-stack-values.yml`), which enables
cross-namespace rule discovery. Reinstall with:

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/observability/kube-prometheus-stack-values.yml
```

### Cross-namespace traffic blocked (expected)

Staging NetworkPolicies deny all ingress from outside the namespace. Pods in
`kijani-staging` cannot reach pods in `default` and vice versa. This is
intentional — only the Ingress NGINX controller is permitted to route traffic
into staging.
