---
title: Dotfiles não bastam
subtitle: Seu ambiente não é uma pasta de configs
description: Como usar Nix e Home Manager para trazer ferramentas junto com as configs, compartilhar preferências entre programas e organizar módulos por funcionalidade.
date: 2026-10-24
event: Inauguração Sanca Hackerspace
language: pt-BR
slides_url: /assets/talks/dotfiles-nao-bastam/slides.pdf
---

Clonar seus dotfiles nem sempre basta para ter seu ambiente funcionando. Quando uma preferência muda ou uma nova máquina é adicionada, organizar tudo por arquivo de programa pode não ser suficiente.

Nesta palestra, mostro como usar Nix e Home Manager pra trazer as ferramentas junto com as configs, compartilhar uma paleta entre programas e organizar módulos por funcionalidade. Dá pra usar sem NixOS. Também comparamos com scripts e templates, que já resolvem parte desses problemas.

## Os três pontos

- **Completude:** configs, ferramentas e versões juntas.
- **Transformação:** mudar a paleta num lugar só, inclusive pro tema GTK.
- **Composição:** escolher as funcionalidades de cada máquina pelos imports.

## Mais recursos

- [Learn Nix](https://nixos.org/learn/): hub de documentações do nix, nixos, e nixpkgs.
- [Home Manager](https://nix-community.github.io/home-manager/): documentação para gerenciar o ambiente do usuário, com ou sem NixOS.
- [NixOS & Flakes Book](https://nixos-and-flakes.thiscute.world/): guia para começar com Nix, flakes e Home Manager.
- [Nix Starter Configs](https://github.com/misterio77/nix-starter-configs): templates para flakes de nixos e home-manager.
- [Minhas configurações](https://github.com/misterio77/Foundry): exemplos reais de módulos e configurações usados no meu ambiente.
