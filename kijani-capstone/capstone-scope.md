# Capstone Scope Document

## Problem Statement
The KijaniKiosk deployment flow currently lacks an observability guardrail tied directly to rollout health. While infrastructure provisioning, Kubernetes deployment, and CI/CD automation are in place, promotion decisions are not consistently enforced using real-time health signals from staging. This creates release risk: a build can appear “deployed” from a pipeline perspective while service reliability is degraded (for example, failing readiness behavior, restart loops, or elevated 5xx responses). The capstone addresses this gap by implementing measurable rollout-health alerting and using it as a release gate before production promotion.

## Track
Track A (Infrastructure-first)

## What I Will Build
- **Prometheus rollout-health alert rules:** Add alerts for failed/stuck rollout behavior (e.g., unavailable replicas, restart spike, rollout timeout indicators) in the staging namespace for `kk-payments`.
- **Service reliability alert rule:** Add an error-rate alert that fires when HTTP 5xx ratio exceeds a defined threshold (target: >5% for 2 minutes) for the staging deployment.
- **CI/CD observability validation stage:** Extend the pipeline to evaluate critical alert state after staging deployment and before production promotion.
- **Promotion guardrail enforcement:** Block production promotion when critical rollout-health alerts are firing.
- **Staging rollback integration:** Trigger automated rollback in staging when rollout-health validation fails, and persist evidence in pipeline logs.

## What Is Out of Scope
- Full organization-wide observability platform redesign (dashboards for all services, all teams).
- End-to-end distributed tracing rollout across the entire KijaniKiosk system.
- Multi-region, multi-cluster resiliency architecture changes.
- Application business-logic refactoring unrelated to deployment health validation.

## Success Criteria
1. **Staging alert detection:** A merge to `main` deploys to staging and evaluates rollout-health alerts; pipeline records explicit PASS/FAIL based on alert state.
2. **Failure scenario response:** A deliberately introduced bad release condition in staging triggers at least one critical alert within 2 minutes.
3. **Release gate enforcement:** Production promotion is blocked automatically while critical staging rollout-health alerts are in `firing` state.
4. **Recovery path validation:** After rollback or fix, alerts return to non-firing state and production promotion can proceed through the defined approval gate.

