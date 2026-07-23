# KijaniKiosk CI Pipeline Board Documentation

Every time a developer finishes work on the KijaniKiosk application and pushes their changes to the shared repository, an automated process takes over. That process is called a pipeline and it checks the code, builds it, verifies it works, and stores a copy in a secure registry. No human clicks are required after the push. The pipeline runs on its own, takes about two minutes, and does exactly the same thing every time. This document explains what happens between that push and the appearance of a versioned artifact in the registry.

## From Code Push to Versioned Artifact

When a developer pushes code, the pipeline performs six sequential steps. Each step confirms something specific before handing off to the next. If any step fails, the pipeline stops immediately and it does not attempt to build broken code, test incomplete features, or publish something that did not compile. The result is that only verified, tested code ever reaches the registry.

The table below shows each stage, what it does, and what it confirms:

| Stage | What Happens | What It Confirms |
|-------|-------------|-----------------|
| **Initialize** | Reads the version number and commit identifier from the source code | The pipeline knows exactly which version it is building |
| **Install Dependencies** | Downloads every library the application needs, in exact locked versions | The full set of third-party code is present and reproducible |
| **Lint** | Runs automated code-quality checks across all source files | The code meets quality standards before build resources are spent |
| **Build** | Compiles source code into the production bundle and verifies the output is not empty | The code compiles cleanly and produces a valid artifact |
| **Verify** | Runs unit tests and a security vulnerability scan at the same time | The application behaves correctly and contains no known high-severity security flaws |
| **Archive and Publish** | Stores the build output in a versioned registry with tracking | Every published version is traceable and ready for deployment |

After the final stage completes, a compressed, versioned package sits in the registry, ready for deployment. This compressed version is what we call an artifact. Each artifact is tagged with its version number and commit hash, so anyone can identify exactly which code is deployed at any time. The artifact is also fingerprinted, meaning the registry can confirm later whether a specific version was genuinely produced by this pipeline.

## What Happens When Something Goes Wrong

The pipeline is designed around a simple principle: if one step fails, nothing after it runs. This means problems are caught early and never reach deployment. If a developer introduces a syntax error, the Lint stage catches it before the build stage runs. If the build fails, no tests execute and nothing is published. If a test fails, the artifact is not stored in the registry. At every point, the pipeline prevents partially broken code from reaching the people who depend on it.

When this happens, the developer sees a clear message indicating which stage failed and the specific error that caused it. The failed build number is logged for audit purposes. The workspace is automatically cleaned so the next run starts from a known state. No manual intervention is needed from the platform team as the developer fixes the issue locally, pushes again, and the pipeline re-runs from the beginning.

Every successful run after a failure produces a clean artifact. There is no residual contamination from the previous failed attempt. The registry only ever contains artifacts that passed every check. This gives the team confidence that any version in the registry was built through the full verification sequence and is safe to deploy.

## What This Pipeline Does Not Yet Do

This pipeline covers the path from code push to a stored artifact, but it does not yet handle deployment to live environments, automated rollback if a published artifact later proves faulty, real-time monitoring of application health after release, or integration with issue tracking to automatically link changes to business requirements. It also does not include performance or load testing, which would be important before handling production traffic. The pipeline establishes the foundation as these capabilities are natural next steps as the platform matures.
