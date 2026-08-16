# kk-payments staging observability

`kk-payments-error-rate-prometheusrule.yml` fires the critical
`KKPaymentsHighErrorRate` alert when more than 5% of requests to the staging
Ingress return HTTP 5xx continuously for two minutes.

The rule relies on the `nginx_ingress_controller_requests` counter, emitted by
the Ingress NGINX controller. It is intentionally scoped to
`namespace="kijani-staging"` and `service="kk-payments"`, so production traffic
cannot affect the staging promotion gate.

## Required cluster services

This capstone uses the following standard Helm release names. The Jenkinsfile
uses them to verify prerequisites and to query alert state:

- Ingress NGINX service: `ingress-nginx/ingress-nginx-controller`
- kube-prometheus-stack Prometheus service:
  `monitoring/kube-prometheus-stack-prometheus`

Install them in a local Minikube cluster before running the release pipeline:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.metrics.enabled=true

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values kube-prometheus-stack-values.yml
```

The Prometheus values make the operator discover the labelled `PrometheusRule`
in `kijani-staging`. Confirm the rule is accepted after a staging deployment:

```bash
kubectl -n kijani-staging get prometheusrule kk-payments-staging-alerts
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

In a second terminal, open `http://127.0.0.1:9090/rules` and locate
`KKPaymentsHighErrorRate`.
