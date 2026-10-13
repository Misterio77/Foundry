---
title: Curriculum Vitae
description: Curriculum vitae of Gabriel Fontes, a software engineer and researcher specializing in reproducible infrastructure, cloud platforms, and developer tooling.
permalink: /cv/
---

Gabriel Silva Fontes - gabriel@gsfontes.com - [GitHub](https://github.com/misterio77)

## Overview

Software engineer focused on reproducible infrastructure, cloud platforms,
developer tooling, and free/open-source software. Experience in production cloud
operations, infrastructure as code, CI/CD, and deployment automation. Currently
working at Magalu Cloud and pursuing a PhD at the University of São Paulo,
researching software sustainability in open-source ecosystems.

**Technologies:** Linux, Nix/NixOS, Terraform, AWS, OpenStack, Incus, Juju,
Ansible, Docker, GitHub Actions, PostgreSQL, Rust, Python, and Lua.

## Industry experience

### [Magalu Cloud](https://magalu.cloud) (2024-present)

Brazilian public cloud platform.

#### Software Engineer (2025-present)

- Work on underlying cloud resources, virtualization, packaging, and deployment
  orchestration using OpenStack, Incus, Canonical Juju, and Ansible.

#### Site Reliability Engineer (2024-2025)

- Worked on the Object Storage platform, including deployment automation,
  automated testing, and monitoring.
- Coordinated operational processes, including deployments and disk replacements.

### [Zoocha](https://zoocha.com) (2023-2024)

Web development agency focused in Drupal.

#### DevOps Engineer (2023-2024)

- Migrated Chef-based client infrastructure from AWS OpsWorks to
  Terraform-managed AWS SSM.
- Improved developer tooling and practices, addressed technical debt, and
  supported day-to-day cloud operations.

### [U-Get](https://uget.express) (2020-2023)

Startup developing computer vision-based vending systems.

#### DevOps Engineer (2020-2023)

- Led the migration from manual deployments and partially configured Kubernetes
  infrastructure to reproducible AWS infrastructure using Terraform, ECS, ECR,
  IAM, and S3.
- Decoupled application components, introduced CI/CD pipelines, and supported
  blue-green deployments with short feedback loops.
- Helped replace direct production changes with review-gated workflows. Mentored
  peers and senior stakeholders on Git, Linux, infrastructure practices, and code
  review.
- Worked with databases and multi-tenant environments.

#### Freelance Developer (2020)

- Built an Android tablet fleet-management solution, initially as a Python CLI
  and later rewritten as a Rust backend, covering the tablets' lifecycle.

### [EVAG](https://evag.me) (2020)

#### Communication Intern

- Built campaign websites during Brazil's municipal elections, working directly
  with candidates to deliver their requirements under tight deadlines.

## Education and Research

### University of São Paulo (2020-present)

- PhD: Computer Science and Computational Mathematics (2026-present)
- MSc: Computer Science and Computational Mathematics (2023-2026)

My research focuses on software sustainability in open-source ecosystems and
practices that support long-lived, self-sustaining projects. Some of this work
was [published at Designing '26]({% link _publications/fontes-design-2026.md
%}).

- Bachelor's: Computer Information Systems (2020-2022)

Teaching assistant for a semester in Database Practice.

### University of Groningen (2025)

**Research Internship:** Three months researching cloud computing sustainability
ecosystems. Some of this work was [published at SESoS '26]({% link
_publications/fontes-sesos-2026.md %}).

See all [publications]({% link publications.html %}).

## Open-source and Community

### Nix ecosystem

- Created [nix-starter-configs](https://github.com/misterio77/nix-starter-configs),
  Nix/NixOS configuration templates with 3,700+ GitHub stars, helping newcomers
  adopt reproducible system configuration.
- Created [nix-colors](https://github.com/misterio77/nix-colors), a collection of
  base16 color schemes and an integration module, with 580+ GitHub stars
  (now archived).
- Contribute packages and modules to [nixpkgs](https://github.com/nixos/nixpkgs)
  and [home-manager](https://github.com/nix-community/home-manager).
- Maintain [Foundry](https://github.com/misterio77/Foundry), my personal NixOS
  infrastructure: declarative hosts, services, secrets, deployment workflows, and
  reproducible development environments.

### GELOS - Leadership

- Co-founded and help lead [GELOS](https://gelos.club), a free/open-source
  software group at ICMC-USP with roughly 10-20 members. Coordinate work, mentor
  contributors, review contributions, and help resolve conflicts.
- Implemented and maintain the group's
  [infrastructure and development workflows](https://github.com/gelos-icmc/monorepo):
  NixOS hosts, website, GitHub monorepo, CI/CD, merge queues, and CODEOWNERS-based
  review.
- Maintain Brazilian [free software package mirrors](https://github.com/ufscar/mirror)
  together with UFSCar's [Patos](https://patos.dev/).
