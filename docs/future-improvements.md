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
