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

## (More entries added as encountered)
