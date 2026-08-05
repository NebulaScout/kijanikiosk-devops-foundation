# Post-Incident Review: kk-payments wrong-environment deployment

## 1) Incident Summary

The KijaniKiosk staging payment service was unavailable for 48 seconds during an investor demonstration. A deployment that should have stayed in the demo path instead affected staging, and service was restored by reverting the deployment.

## 2) Timeline

10:14  Nia begins the investor walkthrough of the staging experience.

10:15  Amina starts the deployment with the wrong environment value selected.

10:15  The deployment process begins applying changes to staging.

10:16  Nia's browser receives an error from the staging proxy.

10:16  Tendo receives a message from Nia that something is wrong.

10:17  Tendo checks the terminal history and identifies the wrong environment value.

10:17  Tendo reverts the staging configuration manually.

10:18  The staging service restarts on the previous configuration.

10:18  The staging proxy returns normal responses again.

10:18  48 seconds of user-visible downtime ends.

## 3) Root Cause

Why did staging become unavailable during the demonstration?
Because the deployment process was pointed at staging instead of the demo target.

Why was the deployment process pointed at staging?
Because the environment target was entered as a manual value at runtime and the wrong value was selected.

Why was a manual value enough to choose the target?
Because the release tooling accepted the environment value without checking it against the demo context.

Why did the tooling accept any runtime environment value?
Because the deployment path reused a shared configuration mechanism that was designed to work for more than one environment.

Why did the shared configuration mechanism remain in place?
Because there was no structural control that bound the release to the approved environment for the demonstration.

Root cause: the deployment system accepts an environment target at runtime with no structural validation against the demonstration context, so a single wrong value can redirect a release to staging.

## 4) Contributing Factors

- The deployment was started from a terminal during a high-pressure investor demonstration, which increased the chance of a wrong input.
- The environment value came from shared configuration rather than a locked, environment-scoped release input.
- The same release path could reach staging or the demo target, so the wrong environment was still considered valid by the tooling.
- There was no automated pre-flight check that compared the requested target with the approved demonstration environment before changes were applied.

## 5) What Went Well

The team identified the wrong environment quickly and reverted the change without waiting for the problem to spread. The service checks came back clean after the rollback, which confirmed that the staging environment was stable again.

## 6) Action Items

| Owner | Action | Target date |
| --- | --- | --- |
| Platform Engineer | Add environment-scoped secrets to the deployment workflow so demo credentials cannot reach staging infrastructure. | 2026-08-07 |
| Release Manager | Remove the runtime environment parameter from the deploy entry point and derive the target from the approved release path. | 2026-08-07 |
| Site Reliability Engineer | Add a pre-flight validation job that rejects any release whose target environment does not match the demonstration context. | 2026-08-08 |
| Incident Commander | Add a two-person approval step for investor demonstrations before the deployment job is allowed to start. | 2026-08-08 |

