# Fault Injection Log 

**Pipeline:** Jenkins declarative pipeline (`Jenkinsfile`)
**Agent:** `node:20` Docker container
**Pipeline Stages:**

|  | Stage | Command |
|---|-------|---------|
| 1 | Initialize Pipeline | `node -p "require('./package.json').version"` / `git rev-parse --short HEAD` |
| 2 | Install Dependencies | `npm ci --no-audit --no-fund` |
| 3 | Lint | `npm run lint` |
| 4 | Build Application | `npm run build` + dist directory verification + stash |
| 5 | Verify Build | Parallel: `vitest run` + `npm audit --audit-level=high` |
| 6 | Archive Artifacts | `archiveArtifacts` |
| 7 | Publish Artifacts | `npm publish` to Nexus |

> Jenkins declarative pipelines fail fast, when any stage fails, all subsequent sequential stages are skipped. The `post.always` block (workspace cleanup) always executes regardless of outcome.

---


## Fault Injection: Initialize Pipeline Stage

**Injected fault:** Corrupted `package.json` - changed `"version": "0.0.0"` to `"version":`  (missing value, invalid JSON).

**Command that failed:** `node -p "require('./package.json').version"`
**Error:** `SyntaxError: Unexpected token } in JSON`

### Observed Console Output

```
[Pipeline] stage { (Initialize Pipeline)}
[Pipeline] script {
  Initializing Pipeline for kijanikiosk
  Setting up environment variables
  [Pipeline] sh
  + node -p require('./package.json').version
  ERR! index  SyntaxError: Unexpected token } in JSON
[Pipeline] }
[Pipeline] // stage
```

### Stage Execution Summary

| Stage | Status |
|-------|--------|
| Initialize Pipeline | **FAILED** |
| Install Dependencies | Skipped |
| Lint | Skipped |
| Build Application | Skipped |
| Verify Build (Test + Security Audit) | Skipped |
| Archive Artifacts | Skipped |
| Publish Artifacts | Skipped |
| Post: cleanWs() | Ran |
| Post: failure notification | Ran |

**Pipeline result:** FAILURE

### Why this behaviour is correct

The Initialize stage extracts `PKG_VERSION` and `ARTIFACT_VERSION` that every downstream stage depends on; allowing the pipeline to proceed without valid version metadata would produce unversioned or malformed artifacts, so failing immediately prevents wasted compute and corrupt publishes.


---

## Fault Injection: Install Dependencies Stage

**Injected fault:** Deleted `package-lock.json` (the `npm ci` contract requires an exact lockfile).

**Command that failed:** `npm ci --no-audit --no-fund`
**Error:** `npm error The npm ci command requires a lockfile`

### Observed Console Output

```
[Pipeline] stage { (Initialize Pipeline)}
  Initializing Pipeline for kijanikiosk
  Setting up environment variables
[Pipeline] stage { (Install Dependencies)}
  Installing all dependencies
  [Pipeline] sh
  + npm ci --no-audit --no-fund
  npm error The `npm ci` command requires a lockfile.
  npm error Complete log: /root/.npm/_logs/...
[Pipeline] }
```

### Stage Execution Summary

| Stage | Status |
|-------|--------|
| Initialize Pipeline | Passed |
| Install Dependencies | **FAILED** |
| Lint | Skipped |
| Build Application | Skipped |
| Verify Build (Test + Security Audit) | Skipped |
| Archive Artifacts | Skipped |
| Publish Artifacts | Skipped |
| Post: cleanWs() | Ran |
| Post: failure notification | Ran |

**Pipeline result:** FAILURE

### Why this behaviour is correct

`npm ci` enforces deterministic installs from the lockfile; without it there is no reproducibility guarantee, so the pipeline correctly refuses to proceed and all downstream stages that depend on `node_modules` are safely skipped.

---

## Fault Injection: Lint Stage

**Injected fault:** Added `console.log("debugging");` to `src/App.tsx` to trigger the ESLint `no-console` rule.

**Command that failed:** `npm run lint` (ESLint exit code 1)
**Error:** `error  Unexpected console statement  no-console`

### Observed Console Output

```
[Pipeline] stage { (Initialize Pipeline)}
[Pipeline] stage { (Install Dependencies)}
  added 192 packages in 15s
[Pipeline] stage { (Lint)}
  Running ESLint on source files
  [Pipeline] sh
  + npm run lint

  > kijanikiosk@0.0.0 lint
  > eslint .

  /var/jenkins_home/workspace/kijani-kiosk-pipeline/src/App.tsx
    3:1  error  Unexpected console statement  no-console

  ✖ 1 problem (1 error, 0 warnings)

  npm error Lifecycle script `lint` failed with exit code 1.
[Pipeline] }
```

### Stage Execution Summary

| Stage | Status |
|-------|--------|
| Initialize Pipeline | Passed |
| Install Dependencies | Passed |
| Lint | **FAILED** |
| Build Application | Skipped |
| Verify Build (Test + Security Audit) | Skipped |
| Archive Artifacts | Skipped |
| Publish Artifacts | Skipped |
| Post: cleanWs() | Ran |
| Post: failure notification | Ran |

**Pipeline result:** FAILURE

### Why this behaviour is correct

Lint is placed before Build as a fail-fast gate; catching code-quality violations before compilation saves build time and prevents shipping code that violates team standards to the Nexus registry.


---

## Fault Injection: Build Application Stage

**Injected fault:** Added `const x: string = 42;` to `src/App.tsx` to produce a TypeScript type error.

**Command that failed:** `npm run build` (`tsc -b`)
**Error:** `TS2322: Type 'number' is not assignable to type 'string'`

### Observed Console Output

```
[Pipeline] stage { (Initialize Pipeline)}
[Pipeline] stage { (Install Dependencies)}
  added 192 packages in 15s
[Pipeline] stage { (Lint)}
[Pipeline] stage { (Build Application)}
  Building version 0.0.0
  [Pipeline] sh
  + npm run build

  > kijanikiosk@0.0.0 build
  > tsc -b && vite build

  src/App.tsx(4,7): error TS2322: Type 'number' is not assignable to type 'string'.

  npm error Lifecycle script `build` failed with exit code 2.
[Pipeline] }
```

### Stage Execution Summary

| Stage | Status |
|-------|--------|
| Initialize Pipeline | Passed |
| Install Dependencies | Passed |
| Lint | Passed |
| Build Application | **FAILED** |
| Verify Build (Test + Security Audit) | Skipped |
| Archive Artifacts | Skipped |
| Publish Artifacts | Skipped |
| Post: cleanWs() | Ran |
| Post: failure notification | Ran |

**Pipeline result:** FAILURE

### Why this behaviour is correct

The Build stage produces the `dist/` artifacts and stashes them for parallel verification; since `tsc -b` failed, no valid `dist/` directory exists, so skipping Verify Build (which unstashes `build-output`) and the archive/publish stages prevents cascading failures and avoids publishing a broken artifact.

---

## Fault Injection: Verify Build Stage

**Injected fault:** Added a deliberately failing test in `src/__tests__/smoke.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
describe('Smoke test', () => {
  it('intentional failure', () => { expect(true).toBe(false); });
});
```

**Command that failed:** `vitest run` (exit code 1) in the **Test** parallel branch.
**Error:** `AssertionError: expected true to be false`

### Observed Console Output

```

[Pipeline] echo
Stashing build output for parallel stages
[Pipeline] stash
Stashed 8 file(s)
[Pipeline] stage { (Verify Build)}
  [Pipeline] parallel {
    [Pipeline] stage { (Test)}
      Running Unit Tests
      + npm run test -- --passWithNoTests --reporter=junit --outputFile=junit-results.xml

      FAIL  src/__tests__/smoke.test.ts

      Tests  1 failed | 0 passed
      npm error Lifecycle script `test` failed with exit code 1.
    [Pipeline] stage { (Security Audit)}
      Running Security Audit (npm audit)
      + npm audit --audit-level=high
      found 0 vulnerabilities
    [Pipeline] }
[Pipeline] }
```

### Stage Execution Summary

| Stage | Status |
|-------|--------|
| Initialize Pipeline | Passed |
| Install Dependencies | Passed |
| Lint | Passed |
| Build Application | Passed |
| Verify Build (Test) | **FAILED** |
| Verify Build (Security Audit) | Passed |
| Archive Artifacts | Skipped |
| Publish Artifacts | Skipped |
| Post: cleanWs() | Ran |
| Post: failure notification | Ran |

**Pipeline result:** FAILURE

### Why this behaviour is correct

In Jenkins declarative pipelines, all branches of a parallel block execute concurrently; the Security Audit branch is an independent check that does not depend on test results, so it runs to completion even when the Test branch fails, while the pipeline correctly refuses to proceed to Archive/Publish because at least one verification branch failed.


---

## Summary

| | Fault Injection Stage | Fault Injected | Stages Ran | Stages Skipped | Pipeline Result | Return to Green |
|---|----------------------|----------------|------------|----------------|-----------------|-----------------|
| 1 | Initialize Pipeline | Corrupt `package.json` | 1 of 7 | 6 of 7 | FAILURE | Yes |
| 2 | Install Dependencies | Missing `package-lock.json` | 2 of 7 | 5 of 7 | FAILURE | Yes |
| 3 | Lint | ESLint `no-console` violation | 3 of 7 | 4 of 7 | FAILURE | Yes |
| 4 | Build Application | TypeScript type error | 4 of 7 | 3 of 7 | FAILURE | Yes |
| 5 | Verify Build | Failing vitest assertion | 5 of 7 | 2 of 7 | FAILURE | Yes |

**Observation:** Each fault caused exactly the stages downstream of the failure point to be skipped, and exactly the stages upstream to have run. This confirms the Jenkins declarative pipeline's sequential fail-fast model is functioning correctly and no stage is skipped prematurely, and no stage runs after a failure in its prerequisite.
