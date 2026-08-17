# Reflection

## What did you get wrong?

I added a pod-level `securityContext` with `runAsNonRoot: true` and `runAsUser: 1000` to the kk-payments Deployment because Kubernetes security best practices say to do this. I never checked what user the container image actually runs as. The kk-payments image is nginx-based, it runs nginx inside the container, and nginx needs to bind to ports and write to `/var/cache/nginx/`. When forced to run as UID 1000, nginx could not create `/var/cache/nginx/client_temp` and crashed immediately with exit code 1. The pipeline saw the deployment as `unchanged` (the spec was already applied), but the rolling update was stuck with two new pods in CrashLoopBackOff with 13 restarts, two old pods still running fine from before the change. The `rollout status` command timed out and the pipeline failed.

The fix was removing four lines. But the real mistake was applying a "best practice" without understanding the runtime environment it would run in. A ten-second check would have shown the image runs as root and that `runAsNonRoot` would break it. I would do this differently by validating the image's default user and filesystem requirements before applying any securityContext, not after the pods crash.

## What is the most important thing you learned?

Infrastructure code is not like application code and you cannot test it in isolation. Application code fails at compile time or in a unit test. Infrastructure code fails during the apply time, in the cluster, against the actual runtime. A YAML manifest can be syntactically valid, logically correct, and still break the system because it conflicts with something invisible from the manifest alone: the container image's internals, an admission webhook that is not installed, a NetworkPolicy that blocks expected traffic.

## What would a second pass look like?

**Add production monitoring.** The PrometheusRule and observability resources exist only in the staging overlay. A second pass would create a production-specific PrometheusRule (identical expression, filtered to the production namespace) and include `../../observability` in the production kustomization so that production has the same error-rate guardrail that staging has.


