# Future Improvements

Ideas for extending this project beyond its current scope — documented but intentionally not built now, given hardware constraints.

- Migrate SonarQube's embedded H2 metadata store to external Postgres
- Migrate application's H2 in-memory DB to external Postgres, managed via Kubernetes Secrets
- Add lightweight monitoring (evaluated in Phase 14 — Prometheus/Grafana are too heavy for t2.micro; exploring alternatives)
- Horizontal Pod Autoscaling once multi-node or larger instance is available
- Migrate from Jenkins on WSL to a more portable CI runner
