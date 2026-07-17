# Troubleshooting

Real issues encountered during this project, and how they were diagnosed and resolved.

## WSL2 Clock Skew Causing SonarQube/Elasticsearch Crashes

**Symptom:** SonarQube container exits with code 255. Logs show `absolute clock went backwards`, `timer thread slept for X hours`, `HikariPool thread starvation`, and `SocketTimeoutException` on Elasticsearch requests.

**Root cause:** WSL2's virtual machine clock pauses when the Windows host sleeps/hibernates. On resume, the clock jump confuses time-sensitive internal services (Elasticsearch thread pool, HikariCP connection pool), cascading into request timeouts and eventual container failure.

**Diagnosis approach:**
1. Checked `docker logs sonarqube --tail 50` for the actual error chain, rather than assuming OOM or misconfiguration
2. Ruled out memory exhaustion via `dmesg`/`journalctl` OOM checks
3. Identified the "clock went backwards" pattern as the actual root cause

**Fix:** Restart the container (`docker start sonarqube`). Avoid letting the host sleep during active work sessions. If recurring, `wsl --shutdown` from PowerShell fully resyncs the WSL VM clock.

## Docker Container Stuck on Removal ("did not receive an exit event")

**Symptom:** `kind delete cluster` (or any `docker rm -f`) fails on one container with `tried to kill container, but did not receive an exit event`.

**Root cause:** containerd/Docker daemon state desync, likely triggered by the same WSL2 VM instability as above.

**Fix (escalating):**
1. `docker kill <container>` then `docker rm <container>`
2. If still stuck, check for an orphaned process with `ps aux`, then `sudo systemctl restart docker`
3. If still stuck, `wsl --shutdown` as a last resort

## Lombok Compiler-Internals Crash on JDK 21

**Symptom:** Jenkins pipeline fails during `mvn clean compile` with:
`java.lang.NoSuchFieldError: Class com.sun.tools.javac.tree.JCTree$JCImport does not have member field 'com.sun.tools.javac.tree.JCTree qualid'`

**Root cause:** Lombok hooks directly into javac's internal (non-public) AST classes to generate boilerplate code at compile time. The project's inherited Lombok version (1.18.22, via the Spring Boot 2.5.6 parent POM's dependency management) predates JDK 21 and is incompatible with its internal compiler structure. This also explained why local Docker builds (using JDK 17 in the Dockerfile) succeeded while Jenkins (configured with JDK 21) failed — an environment/JDK version mismatch across the toolchain.

**Diagnosis approach:**
1. Read the actual stack trace rather than assuming a generic "build broke" — identified the error was in JVM-internal compiler classes, not application code
2. Recognized Lombok as the likely cause since it's the only dependency that manipulates javac internals
3. Confirmed the fix locally (`mvn clean compile`) before re-testing in Jenkins CI

**Fix:** Added an explicit `<lombok.version>1.18.32</lombok.version>` property in `pom.xml` to override the outdated version inherited from the Spring Boot parent POM.

## SonarQube Resource Contention on Constrained WSL Environment

**Symptom:** SonarQube scans intermittently fail with `SocketTimeoutException`
or connection resets during analysis (loading quality profiles, active rules,
or report upload), despite SonarQube itself being confirmed healthy
(`curl` returns 200, logs show "SonarQube is operational").

**Root cause:** SonarQube Community Edition runs three separate internal JVM
processes (Elasticsearch, Compute Engine, Web Server), together consuming
~1.5GB RAM and spiking to 200%+ CPU during analysis. On this project's WSL
environment (3.7GB total, shared with Jenkins and Maven builds), this leaves
insufficient headroom for SonarQube to respond to scanner requests within
default timeouts.

**Diagnosis approach (ruled out several causes before confirming root cause):**
1. Initially suspected a JDK/JaCoCo version incompatibility - confirmed and
   fixed separately (JaCoCo 0.8.7 -> 0.8.11 for JDK 21 bytecode support)
2. Suspected unused bundled language analyzers (Go, Python, PHP, etc.) added
   overhead - investigated via `docker exec sonarqube ls
   /opt/sonarqube/extensions/plugins/`, found these are bundled into
   SonarQube Community Edition's core distribution, not separately removable
3. Confirmed actual resource pressure directly: `docker stats --no-stream
   sonarqube` showed 270% CPU / 1.5GB RAM during a scan, with system-wide
   `free -h` showing under 100MB available
4. Increased `sonar.ws.timeout` to 300s as a partial mitigation - reduced
   but did not eliminate failures under peak load

**Resolution:** Rather than let this known infrastructure constraint fail
the entire pipeline, the Jenkinsfile wraps the SonarQube Analysis and
Quality Gate stages in `catchError(buildResult: 'UNSTABLE')`. A resource
timeout marks the build UNSTABLE (visible, honest signal) rather than
FAILURE, allowing the pipeline to still complete Build/Test/deploy stages.

**Real fix (not applied, by choice):** Increasing WSL's memory allocation
via `.wslconfig` (e.g. from 3.7GB to 6GB) would very likely resolve this
completely, since SonarQube has been confirmed to complete full scans
successfully when resource contention is lower. This wasn't applied because
this project's constraint is deliberately fixed at what's realistically
available on the target hardware profile, matching the AWS EC2 t2.micro
constraint the whole project is designed around. In a real production setup,
SonarQube would run on dedicated infrastructure, not share a workstation
with CI tooling - this limitation is specific to the resource-constrained
learning environment, not the tool or the pipeline design.

## Jenkins timeout Step Bypasses catchError, Forces Build ABORTED

**Symptom:** Even with SonarQube Analysis wrapped in `catchError` to prevent
hard failures, a separate `waitForQualityGate` step inside a `timeout` block
still resulted in `Finished: ABORTED` instead of the intended `UNSTABLE`.

**Root cause:** Jenkins' `timeout` step, when it expires, sets the overall
build result to ABORTED directly as part of its interrupt signal - this
happens before `catchError` can intercept and downgrade it. `catchError` is
designed for regular step failures/exceptions, not `timeout`-driven aborts.

**Fix:** Removed the blocking `waitForQualityGate` step entirely. The
SonarQube Analysis stage (still wrapped in `catchError`) reliably completes
and uploads the scan report; Quality Gate results are viewable directly on
the SonarQube dashboard without Jenkins needing to poll and block on them.

## (More entries added as encountered)
