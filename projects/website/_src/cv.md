---
title: Curriculum Vitae
permalink: /cv/
---

Last updated: 2026-07-02

## Overview

Software engineer and researcher focused on reproducible infrastructure,
developer tooling, cloud deployment workflows, and free/open-source software.
My work is mostly around development processes, build systems, infrastructure,
DevOps, CI/CD, and backend.

I currently work full-time at Magalu Cloud, where I work on underlying cloud
resources, virtualization, packaging, and deployment orchestration. I am also
pursuing a Computer Science M.Sc. at the University of São Paulo, researching
software sustainability in open-source ecosystems.

I frequently work with Rust, Python, Lua, PostgreSQL, Nix/NixOS, Docker,
Terraform, Linux, Juju, and GitHub Actions. I also have experience with UI/UX
and web/graphic design.

Outside of work, I [contribute to free/open-source
software](https://github.com/misterio77), help coordinate
[GELOS](https://gelos.club), and enjoy teaching what I know to others.

### Selected public technical artifacts

* [GELOS monorepo](https://github.com/gelos-icmc/monorepo): NixOS-based community infrastructure, website, CI/CD workflows, merge queues, CODEOWNERS-based review, contribution practices, and declarative host configuration.
* [nix-starter-configs](https://github.com/misterio77/nix-starter-configs): widely used Nix/NixOS flake templates designed to make reproducible system configuration easier for newcomers.
* [nix-config](https://github.com/misterio77/nix-config): my personal NixOS infrastructure and system configuration, including declarative hosts, services, secrets, deployment workflows, and reproducible development environments.

## Industry experience

### Magalu Cloud (2024-present)

[Magazine
Luiza](https://ri.magazineluiza.com.br/ShowCanal/Quem-Somos?=urUqu4hANldyCLgMRgO
sTw==&linguagem=en) is a leading retail company group in Brazil. [Magalu
Cloud](https://magalu.cloud), an innovative project under the company's wing, is
Brazil's first 100% domestic public cloud platform.

#### Software Engineer (2025-present)

I am currently part of the team managing underlying resources.
That includes working with open-source solutions for
virtualization (including [OpenStack](https://openstack.org/)
and [Incus](https://linuxcontainers.org/incus)), packaging, and
deployment automation (mainly [Canonical Juju](https://juju.is) and
[Ansible](https://ansible.com)).

#### Site Reliability Engineer (2024-2025)

I was part of the team working on the platform's Object Storage solution. My
responsibilities as an SRE included deployment automation, automated testing,
monitoring, and coordinating routine processes (deployments, disk replacements,
etc.).

### Zoocha (2023-2024)

[Zoocha](https://zoocha.com) is a digital agency, especially focused on
[Drupal](https://drupal.org) development. Zoocha's clients include government,
universities, and private companies.

#### DevOps Engineer (2023-2024)

As part of the DevOps team, I mainly tackled technical debt and supported
developers with better tooling and practices, while simultaneously taking care
of cloud operations and making sure everything was running smoothly.

Some of the work included improving developer tooling, migrating (Chef-based)
client infrastructure from AWS OpsWorks into Terraform-managed AWS SSM, and
dealing with day-to-day operations.

### U-Get (2020-2023)

[U-Get](https://uget.express) was a startup that pioneered a computer
vision-based vending machine system. The system is able to recognize and bill
customers based on what they pick up from a vending spot (fridge, locker), being
much cheaper than traditional mechanical machines.

Our team built our systems from the ground up - including mobile apps, fleet
management (MDM) and billing systems; leveraging Cloud of Things technologies.

#### DevOps Engineer (2020-2023)

I worked with AWS, Terraform, containers, CI/CD, deployments, databases, and
multi-tenant environments.

I led the migration from fragile manual deployments and partially configured
Kubernetes infrastructure into reproducible AWS-based infrastructure using
Terraform, ECS, ECR, IAM, and S3. This included reorganizing and decoupling
application components, introducing CI/CD pipelines, and supporting safer
blue-green deployments with short feedback loops.

I also helped shift the engineering culture toward code review, shared
ownership, and safer production changes. I mentored peers and senior
stakeholders on Git, Linux, infrastructure practices, and code review, helping
replace direct production changes with review-gated workflows.

#### Freelance Developer (2020-2020)

I started off at U-Get by creating a management solution for a fleet of Android
tablets. The MVP was a Python CLI (later rewritten into a Rust backend) that
handled the entire lifecycle of our tablets.

### EVAG

[EVAG](https://evag.me) is a digital agency, focusing on WordPress and custom
solutions for different clients, mostly politicians and activists.

#### Communication Intern (2020)

A temporary job during Brazilian 2020 municipal elections, I built campaign
websites for multiple candidates, many of them now elected. The job involved
working closely together with the candidates, and making their requirements into
actual websites in a very short timespan.

## Education and Research

For my publications, see: [Publications](https://gsfontes.com/publications).

### University of Groningen (2025)

[University of Groningen](https://rug.nl) (RUG) is one of the leading universities
in the Netherlands.

#### Research Internship (2025)

I was at RUG for a 3 month internship, focusing on the intersection between
Cloud Computing Sustainability and open-source software tooling. Some of this
research was [published at SESoS '26](/publications#fontes-sesos-2026).

### University of São Paulo (2020-present)

[University of São Paulo](https://usp.br) (USP) is considered to be Brazil's
most prestigious university, and frequently the top university in Latin America.

During my time here, I helped create and currently lead our [Open-Source & Free
Software extracurricular group](https://gelos.club).

#### Master's: Computer Science and Computational Mathematics (2023-present)

I'm currently researching Software Sustainability in open-source software
projects, hoping to contribute to our understanding of best practices
for successful, long-lived, self-sustaining OSS. Some of this research was
[published at Designing '26](/publications#fontes-design-2026).

#### Bachelor's: Computer Information Systems (2020-2022)

I studied different areas in computing, especially software engineering,
software testing, databases, and operating systems.

I was a teaching assistant for a semester, on a Database Practice subject.

## Open-source and Community

### GELOS - Leadership

I co-founded and help lead [GELOS](https://gelos.club), a free/open-source
software group at ICMC-USP. I coordinate, mentor, review work, and help resolve
conflicts for a group of roughly 10-20 members, and have mentored many more
contributors over the years.

I implemented and maintain much of our [infrastructure and development
process](https://github.com/gelos-icmc/monorepo), including our website,
NixOS-based hosts, GitHub monorepo, CI/CD workflows, merge queues,
CODEOWNERS-based review, and contribution practices.

Together with [UFSCar's](https://www.ufscar.br/) [Patos](https://patos.dev/),
we maintain a large Brazilian [free software package
mirrors](https://github.com/ufscar/mirror).

### Nix ecosystem - Contributor

[Nix](https://nixos.org) is a build and deployment tool based on functional
programming concepts, such as immutability. It allows for highly reproducible
packaging, as well as fully declarative Linux systems through
[NixOS](https://nixos.org).

I'm a very active member in the community. Besides contributing with
packages and modules in [nixpkgs](https://github.com/nixos/nixpkgs) and
[home-manager](https://github.com/nix-community/home-manager), I've also created
a couple relatively popular projects for the ecosystem:
- [nix-colors](https://github.com/misterio77/nix-colors), a repository of
    nix-accessible base16 color schemes and a module that makes their use more
    convenient. It currently has 580+ stars on GitHub. Now archived, due to me
    moving onto other theming standards.
- [nix-starter-configs](https://github.com/misterio77/nix-starter-configs)
    is a collection of nix repository templates. It aims to provide simple,
    opinionated templates so that people starting out with Nix can hit the
    ground running. It has become the most popular NixOS flake template, and
    one of the most starred nix projects overall, with 3,700+ stars on GitHub.

### Other contributions

As I prefer to use open source tools, I frequently hack on them to add a
feature I want or fix a bug; usually upstream the results as PRs. Thanks to
this, I know my way around codebases written in different languages.
