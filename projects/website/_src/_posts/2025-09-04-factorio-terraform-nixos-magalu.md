---
title: Servidor de Factorio declarativo com NixOS+Terraform no Magalu Cloud
description: Aprenda como usar Terraform e NixOS para facilmente subir VMs com suas aplicações no Magalu Cloud.
language: pt
---

> **This blog post was originally published on [dev.to](https://dev.to/magalucloud/servidor-de-factorio-100-declarativo-com-nixos-e-terraform-no-magalu-cloud-3f37) as a guide for Magalu Cloud (my employer) hackathon's participants.**

Uma dúvida comum que pessoas novas ao Terraform têm é: “depois de criar a VM, como eu rodo minha aplicação?”. Algumas soluções incluem cloud-init, Ansible, etc.

Nesse guia, eu quero mostrar uma das melhores (na minha opinião) soluções para isso: o NixOS. Mostrarei como usar Terraform + NixOS para provisionar um servidor já rodando uma aplicação de sua escolha, sem nenhum passo manual.

Factorio é um jogo de automação com uma qualidade absurda e uma gameplay extremamente polida. Se você valoriza seu sono, recomendo não jogar! Pro resto de nós, já viciados, a fábrica deve crescer!

Com isso em mente, esse guia irá, como exemplo divertido, focar em subir um servidor de Factorio! ⚙️

> *Mas, Gabriel, eu não gosto de Factorio!*
>
> Ótimo! Melhor ficar longe desse vício.
>
> O factorio é só um exemplo, e é a parte menos importante do guia. Explicarei como fazer isso para outros jogos (e.g. minecraft), continue lendo!

O versão final está disponível aqui: [GitHub - Misterio77/hackathon-mgc-factorio-terraform](https://github.com/misterio77/hackathon-mgc-factorio-terraform). Esse tutorial irá mostrar como construir esse código iterativamente.

## Intro 🏁

O NixOS é uma distribuição Linux baseada no gerenciador de pacotes Nix. O Nix permite empacotar programas de forma reproduzível e isolada, numa linguagem declarativa e pura. O NixOS leva isso a um outro nível, e permite configurar sistemas inteiros usando essa mesma linguagem. Por exemplo, para subir um servidor de Factorio:

```nix
{
  services.factorio = {
    enable = true;
  };
}
```

Lembra bastante o Terraform, né?

Vou mostrar pra vocês como implantar e configurar um servidor no Magalu Cloud, via Terraform e NixOS, por meio do [nixos-anywhere](https://github.com/nix-community/nixos-anywhere).

A idéia é que, com apenas um `tofu apply`, o servidor seja criado já rodando exatamente o que você quer que rode, sem nenhum passo manual. :construction_worker:

Mãos à obra!

## Setup 🔨

Caso queira acompanhar o tutorial e ir rodando coisas na sua máquina (que recomendo!), você vai precisar:

* Qualquer distro Linux (pode ser WSL) ou MacOS;
* Instalar o gerenciador de pacotes [Nix](https://nixos.org/download) (sua máquina **não** precisa ser NixOS);
* Instalar a [MGC CLI](https://docs.magalu.cloud/docs/devops-tools/cli-mgc/overview/);
* Instalar o [OpenTofu](https://opentofu.org/docs/intro/install/);
* Uma chave SSH;
* Um editor de texto que você goste.

## Configuração de NixOS ❄️

Para usarmos algumas funcionalidades novas do Nix, vamos habilitar `flakes` e `nix-command`:

```shell
$ mkdir -p ~/.config/nix
$ echo "extra-experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

Vamos começar configurando nosso NixOS. Crie uma `configuration.nix`:

```nix
{
  networking = {
    hostName = "factorio-server";
    # Usar DHCP para conectar
    useDHCP = true;
  };

  system.stateVersion = "25.05";
  nixpkgs = {
    # Arquitetura e sistema
    hostPlatform = "x86_64-linux";
    # Habilitar pacotes proprietários
    config.allowUnfree = true;
  };

  services.factorio = {
    enable = true;
    # Abrir porta no firewall
    openFirewall = true;
  };

  # TODO: Iremos remover isso depois
  users.users.root = {
    initialPassword = "123456";
  };
}
```

> *Gabriel, o que mais podemos rodar além de factorio?*
>
> O que seu coração mandar! O NixOS tem [abstrações prontas](https://search.nixos.org/options) para vários jogos, e você pode rodar qualquer software que imaginar.
> Experimente `services.minecraft`!

Vamos usar flakes nesse tutorial. Crie uma `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.factorio-server = nixpkgs.lib.nixosSystem {
      modules = [./configuration.nix];
    };
  };
}
```

> *Gabriellll, o que é diachos é um flake?*
>
> Ótima pergunta! Ter um `flake.nix` torna seu repositório um flake (duh). Em resumo, um flake é um "projeto nix", com dependências em outros "projetos nix", e que provê "coisas nix". Nesse caso, nosso projeto depende do [`nixpkgs`](https://github.com/nixos/nixpkgs) (o conjunto principal de software empacotado para Nix) na versão `nixos-unstable`, e provê uma configuraçao de NixOS chamada `factorio-server`.
>
> É possível usar Nix sem flakes, mas criar um flake te permite gerir melhor as dependências do seu projeto e usar uma CLI mais intuitiva.


Vamos testar? O Nix permite criar uma VM para uma dada configuração de NixOS. Rode:

```shell
$ nix run .#nixosConfigurations.factorio-server.config.system.build.vm
```

Pode levar alguns minutos, pois o Nix irá baixar absolutamente tudo nescessário para esse sistema. Fique tranquilo, pois seu sistema irá re-usar isso sempre que possível.

Irá abrir uma janela com o console da sua VM. Faça login com `root` e `123456`.

![Uma captura de tela mostrando um console QEMU, com login no tty feito no usuário root](https://canada1.discourse-cdn.com/flex008/uploads/jaxy/original/1X/aa442cc9cf735b530098e1b800e9e6d514f1c61f.png?v=1)

Vamos ver se o servidor está okay:

```shell
systemctl status factorio
```

![Uma captura de tela mostrando um console QEMU, após executar 'systemctl status factorio', mostrando que ele está executando corretamente](https://canada1.discourse-cdn.com/flex008/uploads/jaxy/original/1X/7698218f20b9ca2bd9062715a1968779a0132fc0.png?v=1)

Sucesso! Nossa VM está rodando Factorio ⚙️

Agora, vamos colocar isso na Cloud! Bora para o Terraform. Depois voltaremos para fazer alguns ajustes nessa configuração.

## Subindo VM com Terraform ☁️

Crie um arquivo `main.tf`, com o conteúdo:

```tf
terraform {
  backend "local" {
    path = ".terraform.tfstate"
  }
  required_providers {
    mgc = {
      source = "registry.terraform.io/magalucloud/mgc"
      version = "0.36.1"
    }
  }
}

provider "mgc" {
  region = "br-se1"
}
```

Nice. Esse é o nosso boilerplate básico pra usar o provider e manter o estado do terraform no nosso diretório local.

O terraform lê todas as `.tf` no diretório, então vamos deixar as coisas organizadinhas.

### Criando a VM

Vamos preparar nossa VM. Crie um `vm.tf`:

```tf
resource "mgc_virtual_machine_instances" "factorio_server" {
  name = "factorio"
  # 2 vCPUs, 8GB de RAM, 40GB de disco
  machine_type = "BV2-8-40"
  image = "cloud-debian-12 LTS"
}
```

> *Ué, Debian? Não íamos usar NixOS? Que sacrilégio é esse?*
>
> Calma calma foguetinho 🚀! O Magalu Cloud ainda não tem imagem de NixOS, mas temos uma carta na manga para instalar e configurar o NixOS, aguenta ai!

### Tornando ela acessível ao mundo

Precisamos acessar essa VM. Pra isso, vamos:
1. Adicionar nossa chave SSH
2. Alocar um IP público e atribuir ele à máquina
3. Abrir a porta do SSH (22 TCP) e do Factorio (34197 UDP) no firewall da cloud

Começando pela chave pública. Na sua `vm.tf`:

```tf
resource "mgc_ssh_keys" "key" {
  name = "chave-do-gabriel"
  # Altere para a sua chave publica
  key = "<SUA CHAVE SSH PUBLICA>"
}

resource "mgc_virtual_machine_instances" "factorio_server" {
  name = "factorio"
  # 2 vCPUs, 8GB de RAM, 40GB de disco
  machine_type = "BV2-8-40"
  image = "cloud-debian-12 LTS"
  # Passar nossa chave
  ssh_key_name = mgc_ssh_keys.key.name
}
```

E vamos alocar um IPv4 dedicado e atribuir à maquina, crie uma `ip.tf`:
```tf
# Alocar um IPv4
resource "mgc_network_public_ips" "factorio_ip" {
  vpc_id = mgc_virtual_machine_instances.factorio_server.vpc_id
}

# Atribuir à máquina
resource "mgc_network_public_ips_attach" "factorio_ip_attach" {
  public_ip_id = mgc_network_public_ips.factorio_ip.id
  interface_id = mgc_virtual_machine_instances.factorio_server.network_interfaces[0].id
}

# O terraform vai mostrar esse valor para nós
output "ip" {
  value = mgc_network_public_ips.factorio_ip.public_ip
}
```

Por fim, vamos abrir as portas. Crie uma `firewall.tf`:
```tf
# Nosso security group
resource "mgc_network_security_groups" "factorio_server" {
  name = "factorio-hackathon"
}

# Regra para SSH
resource "mgc_network_security_groups_rules" "incoming_ssh" {
  direction = "ingress"
  port_range_min = 22
  port_range_max = 22
  protocol = "tcp"
  ethertype = "IPv4"
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = mgc_network_security_groups.factorio_server.id
}
# Regra para o factorio
resource "mgc_network_security_groups_rules" "incoming_factorio" {
  direction = "ingress"
  port_range_min = 34197
  port_range_max = 34197
  protocol = "udp"
  ethertype = "IPv4"
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = mgc_network_security_groups.factorio_server.id
}

# Atribuir o group à nossa VM
resource "mgc_network_security_groups_attach" "factorio_firewall_attach" {
  security_group_id = mgc_network_security_groups.factorio_server.id
  interface_id      = mgc_virtual_machine_instances.factorio_server.network_interfaces[0].id
}
```

> Lembre-se de trocar (ou adicionar) regras conforme o que você está deployando. Por exemplo, se está subindo minecraft, faça uma regra que abre a porta `25565` no protocolo `tcp`.

### O primeiro deploy

Maravilha! Hora de deployar. Vamos começar autenticando via MGC CLI:

```shell
$ mgc auth login
```

E siga os passos na tela.

Agora precisamos criar uma API key e passar para o terraform.

```shell
$ mgc auth api-key create --name terraform-factorio
```

Aperte a flecha direita para dar todas as permissões, e tab para aceitar. Agora vamos pegar a key e passar para o terraform. Um oneliner que facilita:

```shell
export TF_VAR_mgc_api_key=$(mgc auth api-key get --id $(mgc auth api-key list -o json -r | jq 'map(select(.name == "terraform-factorio"))[0].id' -r) -o json -r | jq .api_key -r)
```

Feito isso, vamos preparar o terraform:

```shell
$ tofu init
```

E aplicar:

```shell
$ tofu apply
```

Digite `yes`, e aguarde um pouquinho.

Feito isso, é hora de validar que o servidor está okay e está acessível pela sua chave. O seu apply deve ter retornado o `ip` como output. Rode:

```shell
$ ssh debian@<IP DA VM>
```

Agora temos uma VM… Rodando Debian (por enquanto):

![Uma captura de tela de um terminal conectado por SSH na VM do Magalu, rodando screenfetch e exibindo o logo do debian](https://canada1.discourse-cdn.com/flex008/uploads/jaxy/original/1X/6f6ec1c34d15f3c917db776ec3433b3ebc359852.png?v=1)

Vamos agora infectar essa querida com NixOS! Iremos utilizar o [nixos-anywhere](https://github.com/nix-community/nixos-anywhere).

## Instalando NixOS na VM 🪄

A idéia do `nixos-anywhere` é iniciar um NixOS via kexec, desmontar o disco da máquina, re-particionar ele, e instalar NixOS de verdade (com a nossa configuração). Eles provêm um módulo de Terraform, que é perfeito para a gente!

> *Gabriel, kexec? Que diacho é isso?*
>
> Não tema! É bem mais simples do que parece. Significa "**k**ernel **exec**ute".
>
> Pense assim: quando você vai instalar Linux numa máquina, você geralmente boota uma ISO por pendrive. Isso é necessário para você poder liberar e formatar o disco do seu computador.
>
> No Magalu não temos como espetar um pendrive, então usamos um truque de executar outro Linux direto na memória RAM da máquina, isso nos permite desmontar e formatar os discos da máquina, igual com um pendrive!

Vamos precisar fazer alguns ajustes na nossa configuração de NixOS para comportar isso. O NixOS anywhere usa uma ferramenta chamada [disko](https://github.com/nix-community/disko) para particionar declarativamente. Vamos adicioná-la no nosso `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, disko, ... }: {
    nixosConfigurations.factorio-server = nixpkgs.lib.nixosSystem {
      modules = [
        ./configuration.nix
        disko.nixosModules.disko
      ];
    };
  };
}
```

Rode:

```shell
$ nix flake lock
```

Para registrar a mudança na flake.lock.

Nice. Agora vamos adicionar as configurações específicas da máquina (partições, módulos de kernel). Vamos fazer isso num arquivo separado da `configuration.nix`, para separar o “what it runs” e o “where it runs”.

Crie um arquivo `hardware-configuration.nix`:

```nix
{modulesPath, ...}: {
  imports = [(modulesPath + "/profiles/qemu-guest.nix")];
  boot = {
    initrd.availableKernelModules = ["ata_piix" "uhci_hcd"];
    kernelModules = ["kvm-intel"];
  };

  # Nossas partições
  disko.devices.disk.main = {
    device = "/dev/vda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        esp = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
```

Não se preocupe muito se isso parece complexo. A maior parte desse arquivo foi gerado automaticamente. A parte do `disko` define quais nossas partições.

Precisamos importar esse arquivo da nossa `configuration.nix`. Também vamos tirar a senha `123456`, e habilitar SSH. Edite ela:

```nix
{
  imports = [
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "factorio-server";
    useDHCP = true;
  };

  system.stateVersion = "25.05";
  nixpkgs = {
    hostPlatform = "x86_64-linux";
    config.allowUnfree = true;
  };

  services.factorio = {
    enable = true;
    openFirewall = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
    };
  };

  users.users.root = {
    openssh.authorizedKeys.keys = [
      # Troque para sua chave.
      "<SUA CHAVE SSH PUBLICA>"
    ];
  };
}
```

Lembre-se de trocar a chave SSH para a sua.

> *Gabriel, por que temos a chave SSH em dois lugares?*
>
> A do terraform define qual vai ser a chave autorizada assim que a máquina é provisionada. Essa chave será usada pela instalação inicial do nixos-anywhere. A do NixOS é qual será a chave autorizada após a instalação (e nescessária para rebuilds).
> No repositório (link no fim do post), fizemos de um jeito mais robusto: o terraform cria a chave.

Certo, agora vamos configurar o nixos-anywhere pelo terraform. Crie um `nixos.tf`:

```tf
module "deploy" {
  source = "github.com/nix-community/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr = ".#nixosConfigurations.factorio-server.config.system.build.toplevel"
  nixos_partitioner_attr = ".#nixosConfigurations.factorio-server.config.system.build.diskoScript"
  debug_logging = true

  instance_id = mgc_virtual_machine_instances.factorio_server.id
  target_host = mgc_virtual_machine_instances.factorio_server.network.public_address
  install_user = "debian"
}
```

Adicionamos um novo módulo externo, então rode novamente o init:

```shell
$ tofu init
```

Certinho! Estamos prontos. Vamos aplicar a configuração do Terraform:

```shell
$ tofu apply
```

Aguarde alguns minutos (geralmente menos de 5). O NixOS anywhere irá instalar NixOS na VM, e aplicar nossa configuração!

Sempre que você modificar a configuração, basta dar apply novamente, ele irá detectar a mudança e fazer alterações na VM conforme nescessário.

Sucesso! Podemos usar o IP agora para jogar factorio:

![Uma captura de tela nos menus da tela inicial do factorio, está sendo feita uma conexão direta ao IP da VM](https://canada1.discourse-cdn.com/flex008/uploads/jaxy/original/1X/135ef87fb35016ea28af6319e543245f91ae7389.jpeg)


## Fechamento

Espero que esse tutorial tenha ajudado você a ver algumas das coisas que são possíveis no modelo declarativo!

A magia da coisa é que qualquer um pode rodar `tofu apply` e ter um servidor exatamente igual. Fazendo as mudanças nos arquivos e rodando apply, você garante que não existe nenhum passo de setup (e.g. instale coisa X, altere arquivo Y) além de simplesmente ter os arquivos `.tf` e `.nix`.

O versão final está disponível no repositório: [GitHub - Misterio77/hackathon-mgc-factorio-terraform](https://github.com/misterio77/hackathon-mgc-factorio-terraform)

Feedback é muito bem vindo, e fico a disposição para qualquer dúvida!

Beijos,
Gab

