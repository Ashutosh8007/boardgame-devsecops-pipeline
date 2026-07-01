# Boardgame DevSecOps Pipeline

A production-style CI/CD pipeline that builds, tests, scans, and deploys a Java Spring Boot application to a self-managed Kubernetes (K3s) cluster — engineered to run within real hardware constraints (1 vCPU / 1GB RAM on AWS EC2 t2.micro).

> **Status:** 🚧 In progress — Docker & Dockerfile hardening complete; actively building out Phases 5-15.

## What This Project Demonstrates

This isn't a "spin up unlimited cloud resources" demo. It's a deliberately resource-constrained DevSecOps pipeline, which means every architectural decision below was made under real tradeoffs — the same kind of tradeoffs you'd face with a limited infrastructure budget in an actual company.

- **CI/CD Pipeline:** Jenkins orchestrates build → test → static analysis → security scan → containerize → deploy
- **Security-first ("DevSecOps"):** SonarQube (code quality) and Trivy (vulnerability scanning) are integrated as pipeline gates, not afterthoughts
- **Container Orchestration:** K3s (lightweight Kubernetes) running the actual application workload on AWS EC2
- **Infrastructure Separation:** Build tooling (Jenkins, SonarQube) runs on a local WSL workstation; only the Kubernetes runtime lives on EC2 — mirroring how real companies separate build infrastructure from production runtime

## Application

The deployed application is a Spring Boot board game listing & review platform, forked and adapted from [jaiswaladi246/Boardgame](https://github.com/jaiswaladi246/Boardgame). It features:
- Role-based access control (non-members, users, managers) via Spring Security
- CRUD operations for board games and reviews
- Server-rendered UI via Thymeleaf

The application itself is not the focus of this repository — the DevSecOps pipeline built around it is.

## Architecture
Full architecture diagram and explanation: [docs/architecture.md](./docs/architecture.md)

## Tech Stack

| Layer | Tools |
|---|---|
| Source Control | Git, GitHub |
| Build | Maven, Java 21 |
| CI/CD | Jenkins |
| Code Quality | SonarQube |
| Security Scanning | Trivy (filesystem + image scanning) |
| Containerization | Docker, Docker Hub |
| Orchestration | Kubernetes (K3s), kubectl, Helm |
| Ingress | Nginx Ingress Controller |

## Repository Structure
## Documentation

- [Architecture](./docs/architecture.md)
- [Deployment Guide](./docs/deployment-guide.md)
- [Troubleshooting](./docs/troubleshooting.md)
- [Lessons Learned](./docs/lessons-learned.md)
- [Future Improvements](./docs/future-improvements.md)

## Author

Ashutosh Shirke — built as a hands-on DevSecOps learning project, documenting real infrastructure issues and their resolutions along the way.
