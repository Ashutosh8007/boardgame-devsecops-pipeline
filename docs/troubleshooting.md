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

## SonarQube Occasionally Unreachable During Heavy Pipeline Runs (Docker Build/Push)

**Symptom:** SonarQube Analysis stage fails with `Failed to query server
version: Call to URL [.../api/v2/analysis/version] failed: null`, even
though SonarQube is confirmed healthy immediately before and after
(`docker ps` shows it `Up`, `curl` returns 200).

**Root cause:** Same underlying resource constraint as the earlier
SonarQube timeout issue (see above), but triggered by a different source
of load - a full pipeline run now includes `docker build`, a Trivy image
scan, and `docker push`, all of which are CPU/network-intensive. This
transient load appears to be enough to make SonarQube briefly
unresponsive to new connections without actually crashing the container.

**Resolution:** No additional fix applied. The existing `catchError`
wrapper around the SonarQube Analysis stage already handles this
correctly - the build is marked `UNSTABLE`, not `FAILURE`, and all other
stages (Build, Test, Trivy scans, Docker push) complete unaffected. This
is treated as an accepted, documented characteristic of running the full
pipeline on a resource-constrained WSL environment, consistent with the
project's stated hardware-constraint framing.

## Free-Tier Instance Type Mismatch (t2.micro Rejected by AWS)

**Symptom:** `terraform apply` failed creating the EC2 instance with
`InvalidParameterCombination: The specified instance type is not eligible
for Free Tier`, despite `t2.micro` being the historically standard
free-tier instance type.

**Root cause:** AWS free-tier eligible instance types vary by account
and region and have shifted over time; this account's free tier in
`ap-south-1` no longer includes `t2.micro`.

**Diagnosis approach:** Queried AWS directly rather than guessing at a
replacement: `aws ec2 describe-instance-types --filters
Name=free-tier-eligible,Values=true --region ap-south-1`, which returned
`t3.micro`, `t4g.micro`, `t3.small`, `t4g.small` as actually eligible.

**Fix:** Changed `instance_type` in `main.tf` from `t2.micro` to
`t3.micro` - same 1 vCPU/1GB RAM specification as originally planned in
Phase 1, so the project's resource-constraint framing remains accurate;
only the exact instance family name changed.

## K3s Severe Memory/I/O Contention on First Boot (t3.micro, 913Mi RAM)

**Symptom:** Shortly after installing K3s, `kubectl` commands (even run
locally on the instance via `sudo k3s kubectl`) failed with `Unable to
connect to the server: net/http: TLS handshake timeout`. System pods
(coredns, metrics-server, local-path-provisioner) were stuck in
`ContainerCreating` far longer than expected.

**Root cause:** K3s's control plane (API server, controller-manager,
scheduler, containerd) alone consumed ~500-550Mi of the instance's
913Mi total RAM, leaving under 30Mi available. `top` showed 80%+ CPU
time in I/O wait and a load average above the instance's 2 vCPUs,
indicating the system was thrashing rather than just slow.

**Diagnosis approach:**
1. Ruled out a hard OOM kill first: `sudo dmesg | grep -i "killed
   process\|out of memory"` returned empty - the process was straining,
   not crashed
2. Confirmed real resource pressure directly with `free -h` and `top -b
   -n 1`, rather than assuming from symptoms alone
3. Checked `systemctl status k3s` to confirm the service itself was
   still `active (running)` despite the connectivity failures

**Fix:** Added a 1GB swap file (`fallocate` + `mkswap` + `swapon`,
persisted via `/etc/fstab`) to give the kernel breathing room to page
out infrequently-used memory instead of the system grinding to a halt
under zero-swap pressure. This is standard, accepted practice for
memory-constrained Kubernetes nodes, not a workaround.

## Traefik (K3s's Bundled Ingress Controller) Failed to Install Under Resource Pressure

**Symptom:** The `helm-install-traefik` Job pod repeatedly failed
(`Error`, then `CrashLoopBackOff`) during initial K3s startup. Its logs
showed the `helm install` command starting but never completing or
producing an error - consistent with the process being killed or
timing out mid-execution rather than failing on a configuration issue.

**Root cause:** Same resource starvation as above - Traefik's Helm
install job competed for the same critically limited memory/CPU during
the exact window K3s's own control plane was already straining to
start.

**Decision:** Rather than fight to keep Traefik stable on a 913Mi node,
disabled it entirely via K3s's own config (`disable: traefik` in
`/etc/rancher/k3s/config.yaml`) and used a plain Kubernetes `Service`
of type `NodePort` to expose the app instead. This is a deliberate
architectural tradeoff, not a limitation being hidden: NodePort has a
smaller memory footprint and is a better fit for this project's stated
hardware constraints than limping an Ingress controller along on
insufficient resources. Ingress can be revisited later if the resource
picture changes (see docs/future-improvements.md).

## kubectl Remote Access: Kubeconfig Paste Corruption and TLS SAN Mismatch

**Symptom (1):** After manually copying K3s's kubeconfig into
`~/.kube/config` on the WSL machine, `kubectl` failed with `yaml: line
20: could not find expected ':'`.

**Root cause (1):** A manual copy/paste into `nano` picked up a stray
shell prompt line (`ubuntu@ip-...:~$`) from the terminal output,
landing in the middle of the YAML file and breaking its structure.

**Fix (1):** Abandoned manual paste entirely. Pulled the file
programmatically instead: `ssh -i ~/.ssh/boardgame-ec2 ubuntu@<ip>
"sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config` - a direct pipe
with no human transcription step, eliminating the corruption risk
entirely.

**Symptom (2):** After fixing the YAML and pointing `server:` at the
instance's public IP, `kubectl` failed differently: `tls: failed to
verify certificate: x509: certificate is valid for 10.43.0.1,
127.0.0.1, 172.31.35.192, ::1, not <public-ip>`.

**Root cause (2):** K3s generates its TLS certificate at install time
using only the addresses it knows about then (internal cluster IP,
localhost, private IP) - the instance's public IP isn't included by
default, so a client connecting via the public IP correctly fails
certificate verification (TLS working as intended, not a bug).

**Fix (2):** Added the public IP as a `tls-san` entry in
`/etc/rancher/k3s/config.yaml`, restarted K3s to regenerate its
certificate with the new SAN included, then re-pulled a fresh
kubeconfig (the old one's cached CA data no longer matched). Note:
switching to an Elastic IP later required repeating this once more
(new IP, same fix) - documented separately below.

## Elastic IP Required for Stable Access Across EC2 Stop/Start Cycles

**Symptom:** Recognized before hitting it directly: AWS assigns a new
public IP to a `t3.micro` instance every time it's stopped and
restarted (EBS-backed instances persist disk state but not their public
IP by default). This would have broken SSH, `kubectl`'s TLS trust (the
old IP baked into `tls-san`), and the app's public NodePort URL on
every restart.

**Fix:** Added an `aws_eip` resource in Terraform, associated with the
instance. This required one final repeat of the `tls-san`/kubeconfig
fix above (for the new, now-permanent Elastic IP), after which the
address never changes again across stop/start cycles - a
one-time cost for a permanent fix, applied via Terraform rather than a
manual console click to keep the whole instance lifecycle in code.

## (More entries added as encountered)

## kubectl Times Out After Home IP Address Changes (i/o timeout, not TLS/refused)

**Symptom:** `kubectl get nodes` fails with `dial tcp <elastic-ip>:6443: i/o
timeout` - distinct from a TLS error or "connection refused". The EC2
instance is confirmed `running` via `aws ec2 describe-instances`.

**Root cause:** The security group's SSH and K3s-API ingress rules are
locked to the operator's IP at the time of the last `terraform apply`
(fetched via `data.http.my_ip`). Home ISP IP addresses can change between
sessions; when they do, the security group silently drops all traffic
from the new IP - AWS security groups don't reject with an error, they
just don't respond, which is why the symptom is a timeout rather than a
clear "access denied".

**Diagnosis approach:** Compared the current IP (`curl -s
https://checkip.amazonaws.com`) against what the security group actually
allows (`aws ec2 describe-security-groups ... --query
'SecurityGroups[0].IpPermissions[?ToPort==\`6443\`].IpRanges[].CidrIp'`)
rather than assuming the instance itself was the problem.

**Fix:** Re-ran `terraform plan`/`apply` with no code changes needed -
`data.http.my_ip` re-fetches the current IP automatically, so Terraform
correctly proposed swapping the stale IP for the current one in both the
SSH and K3s-API security group rules. This is a recurring, expected
maintenance step on a home network, not a one-time fix - worth checking
first whenever kubectl times out (rather than TLS-errors) after a break.
