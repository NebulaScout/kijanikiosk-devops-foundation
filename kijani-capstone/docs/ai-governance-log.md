# AI Governance Log

## Entry 1: Kubernetes Manifests and Kustomize Overlays

- **Date:** 2026-08-16
- **Tool used:** Copilot
- **Task description:** How can I create Kubernetes manifests  for staging and production environments for the kk-payments service while keeping the code DRY.
- **What was provided to the AI:** Previous kubernetes deployment manifests.
- **What the AI produced:** A base Deployment with resource requests/limits, readiness and liveness probes on /health, rolling update strategy, and conventional app.kubernetes.io labels; a ClusterIP Service mapping port 3001; a staging overlay with namespace override to kijani-staging, nginx Ingress for staging.kijani.local, ConfigMapGenerator from .properties files, and observability resources; a production overlay with namespace override to default and base-only resources; and a secrets template example
- **What it got right:** Correct use of app.kubernetes.io conventional labels (name, component, part-of), readiness/liveness probes targeting /health with appropriate timings, rolling update strategy with maxSurge and maxUnavailable set to 1, proper kustomize overlay structure inheriting from base, separate ConfigMapGenerator entries for environment-specific configuration, and imagePullSecrets for private registry access
- **What it got wrong:** The Ingress manifest triggers the nginx ingress controller admission webhook, but there is no documentation or preflight check that ingress-nginx must be installed first, which directly caused a failed deployment with "service ingress-nginx-controller-admission not found"
- **What you changed before applying the output:** documented the ingress-nginx prerequisite in the project README and added a preflight check stage to the Jenkinsfile

## Entry 2: Jenkinsfile CI/CD Pipeline

- **Date:** 2026-08-16
- **Tool used:** Copilot
- **Task description:** How can I modify my existing Jenkinsfile to include a monitoring stage that queries Prometheus for alert state after staging deployment, and block production promotion if critical alerts are firing
- **What was provided to the AI:** The requirement to add a PrometheusRule for high error rate detection on the kk-payments service in staging(fire when error rate exceeds 5% for 2 minutes), and to modify the Jenkinsfile to gate production promotion on the alert state, blocking deployment if the alert is firing
- **What the AI produced:** A Jenkinsfile with three new stages: Verify Monitoring Prerequisites, Smoke Test Staging, and Evaluate Staging Alert State 
- **What it got right:** Credential wrapping with withCredentials for kubeconfig handling, flattened kubeconfig via kubectl config view --raw --flatten for portability across contexts, strict error handling with set -euo pipefail, build timeout of 30 minutes and build discarder keeping last 20, branch-gated deploy stages that only run on develop, proper trap cleanup of temporary files and background processes, and background port-forward with readiness polling before querying Prometheus
- **What it got wrong:** The grep pattern for the Prometheus ALERTS API response needed to be escaped properly to avoid Groovy compilation errors.
- **What you changed before applying the output:** Escaped the grep pattern in the Jenkinsfile to avoid Groovy compilation errors, and added a note that the PrometheusRule must be created in the staging namespace before running the pipeline

