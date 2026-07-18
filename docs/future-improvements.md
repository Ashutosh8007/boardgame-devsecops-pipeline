# Future Improvements

Ideas for extending this project beyond its current scope — documented but intentionally not built now, given hardware constraints.

- Migrate SonarQube's embedded H2 metadata store to external Postgres
- Migrate application's H2 in-memory DB to external Postgres, managed via Kubernetes Secrets
- Add lightweight monitoring (evaluated in Phase 14 — Prometheus/Grafana are too heavy for t2.micro; exploring alternatives)
- Horizontal Pod Autoscaling once multi-node or larger instance is available
- Migrate from Jenkins on WSL to a more portable CI runner

## Dependency Vulnerabilities Identified (Trivy Filesystem Scan)

A Trivy filesystem scan of `app/pom.xml` identified 70 known vulnerabilities
(48 HIGH, 22 CRITICAL) across the project's dependency tree, largely due to
the app being built on Spring Boot 2.5.6 (2021). Notable findings include:

- **CVE-2022-22965 (Spring4Shell)** - critical RCE via data binding on JDK 9+
- **CVE-2025-24813** - critical RCE in the bundled Tomcat version
- **CVE-2021-42392** - critical RCE in H2's web console
- **CVE-2026-40477** - critical Server-Side Template Injection in Thymeleaf

These are real, accurate findings, not scanner noise. Resolving them fully
would require upgrading Spring Boot (and its transitive dependency tree) to
a current major version - a significant refactor with real risk of breaking
application behavior, and out of scope for this DevSecOps pipeline project,
whose focus is the CI/CD tooling itself rather than the sample application's
long-term maintenance.

The Trivy stage is configured as informational (`--exit-code 0`) rather than
build-blocking, with full JSON results archived as a Jenkins build artifact
on every run - so findings remain visible and auditable rather than hidden,
even though the pipeline doesn't currently gate on them.

**Future improvement:** Upgrade to Spring Boot 3.x, re-scan, and switch the
Trivy stage to `--exit-code 1` on CRITICAL findings once the dependency tree
is genuinely current, making the scan an enforced quality gate rather than
a report-only stage.

## HTTPS and Domain Name for the Application

The app is currently reachable over plain HTTP at a static public IP
(`http://<elastic-ip>:30080`), stable across EC2 stop/start cycles thanks
to an Elastic IP (see docs/troubleshooting.md). Two natural next steps,
not yet implemented:

- **A real domain name** pointed at the Elastic IP, rather than a raw
  IP:port URL - makes the deployment presentable and is a prerequisite
  for TLS via Let's Encrypt (which requires a domain, not just an IP)
- **HTTPS for the application itself** - distinct from the TLS already
  in place for the Kubernetes API server (`tls-san`); the app's own
  traffic (browser to NodePort) is currently unencrypted

Both are natural fits for Phase 13 (Security) or as a post-Phase-15
enhancement, once Ingress is reconsidered (see the Traefik removal entry
in docs/troubleshooting.md for why it isn't in place yet).
