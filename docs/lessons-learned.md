# Lessons Learned

> Updated at the end of each phase.

## Phase 2: Development Environment Setup
- Always audit existing environment state before installing anything — assumptions about "clean" environments are usually wrong
- WSL2's virtualized clock is a real operational hazard for any time-sensitive service (databases, Elasticsearch, connection pools) — not just a theoretical edge case
- Verifying service health requires more than checking "container is up" — logs AND live connectivity checks (curl) are both necessary
