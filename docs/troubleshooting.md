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

## (More entries added as encountered)
