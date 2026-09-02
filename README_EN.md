# Self-Hosted VPN Agent

[简体中文](README.md) | English

> Bring an AWS account. Let AI handle the rest and deploy a VPN that belongs to you.

`self-hosted-vpn-agent` is a self-hosted VPN deployment toolkit built on HiddifyPanel and designed for AI coding agents.

Give this repository to an agent such as Claude Code, Codex, or Cursor Agent that can access local files, run terminal commands, and use SSH. You provide the AWS environment and required information, complete the few AWS Console actions that require your confirmation, and the agent handles installation, configuration, checks, troubleshooting, and final delivery.

When deployment is complete, you receive:

- A browser-based VPN management panel
- A separate Clash, Mihomo, or Shadowrocket subscription URL for each user
- A usage guide generated from the actual deployment

The server runs in your own AWS account. You control the users and subscriptions, and your traffic does not pass through infrastructure operated by this project's maintainer.

## What You Need

You only need:

1. An AWS account that can create an AWS Lightsail instance
2. A computer with an AI coding agent installed

You can complete the initial AWS setup yourself or ask the agent to guide you through it:

- Create a Lightsail instance
- Download the SSH private key (`.pem`)
- Create and attach a Static IP
- Configure the firewall rules

The agent guides you by complete operation: it gives all steps required to create the instance in one group, waits for that operation to finish, and then moves on to the Static IP and firewall groups. It does not stop for confirmation after every click.

After initialization, give the agent the local path to the `.pem` file and the server's Static IP. The agent then handles installation, configuration, checks, repairs, user creation, subscription generation, final validation, and delivery.

After deployment, the agent provides the management panel URL. You only need to open it once and set the administrator password.

Keep your AWS password, MFA codes, payment information, and permanent Access Keys to yourself.

Do not paste the contents of the SSH key into the chat. The agent only needs the local `.pem` file path and the server's Static IP.

## Start a Deployment

The easiest method is to send the repository URL directly to the agent:

```text
Download this project, read AGENTS.md, and help me deploy my own VPN:
https://github.com/hymn07/self-hosted-vpn-agent
```

If the agent cannot download the repository directly, clone it manually:

```bash
git clone https://github.com/hymn07/self-hosted-vpn-agent.git
cd self-hosted-vpn-agent
```

Then tell the agent:

```text
Read AGENTS.md and help me deploy my own VPN.
```

On the first run, the agent presents the recommended configuration in one message. If you do not want to choose a region, plan, user quota, or domain, reply:

```text
Use the recommended defaults.
```

To customize the deployment, list all changes in one reply. The defaults reduce unnecessary questions; they do not restrict the region, plan, number of users, or traffic quotas you can choose.

## What the Agent Does

```text
Confirm the default or customized configuration
    ↓
Complete Lightsail, Static IP, and firewall initialization
    ↓
Check local configuration, SSH, system resources, and network ports
    ↓
Install the pinned compatible HiddifyPanel version
    ↓
Configure Reality, Hysteria2, users, and routing rules
    ↓
Check services, TLS, and protocol status
    ↓
Validate every user subscription
    ↓
Generate the panel URL, subscription URLs, and usage guide
```

After AWS initialization, the agent and repository scripts handle the server-side work. The agent asks for confirmation before actions that affect cost, delete resources, upgrade software, or introduce other significant risk.

Deployment is complete only after the management panel, protocols, and user subscriptions have been tested successfully.

## What You Receive

### 1. Web Management Panel

The finished deployment includes an address similar to:

```text
https://your-domain.example/<admin-path>/
```

From the panel, you can:

- Create, disable, and delete users
- Set traffic quotas, reset periods, and expiration dates
- View usage
- Get new subscription URLs

Routine administration does not require Linux commands.

### 2. A Separate Subscription for Each User

Mihomo / Clash:

```text
https://your-domain.example/<client-path>/<user-id>/clashmeta/
```

Shadowrocket / generic subscription:

```text
https://your-domain.example/<client-path>/<user-id>/auto/
```

Each user has a separate identity, quota, reset period, expiration date, and subscription credential. Disabling or deleting one user does not affect the others.

### 3. Deployment-Specific Usage Guide

Deployment data is stored locally under `.local/`:

```text
.local/
├── USER_GUIDE.md
├── SECRETS.md
├── DEPLOYMENT_REPORT.md
└── deployment.yaml
```

- `USER_GUIDE.md`: Client import, panel administration, and common troubleshooting instructions
- `SECRETS.md`: Management panel and user subscription URLs that must be protected
- `DEPLOYMENT_REPORT.md`: Region, version, user configuration, and final check results
- `deployment.yaml`: The final configuration used for this deployment

The `.local/` directory is generated during deployment and ignored by Git by default. Real IP addresses, SSH key paths, UUIDs, admin paths, API keys, and subscription URLs are never written to the public repository.

## Recommended Configuration

If you choose the defaults, the current template uses:

| Item | Recommended value |
|---|---|
| Cloud | AWS Lightsail |
| Region | Oregon (`us-west-2`) |
| OS | Ubuntu 22.04 LTS |
| Plan | At least 1 GB RAM; the template assumes a tier with about 2 TB monthly transfer |
| Resource buffer | Creates 2 GB swap by default |
| Panel | HiddifyPanel v12.3.3 |
| Protocols | Reality + Hysteria2 |
| Domain | Free `sslip.io` domain |
| Users | 3 (`user1`, `user2`, and `user3`) |
| Traffic per user | 500 GB/month |
| Traffic reset | Monthly |
| Validity | 3,650 days |
| Clients | Clash / Mihomo / Shadowrocket |

These values are recommendations only. You can change the number of users, names, quotas, reset behavior, validity, region, plan, domain, and node names.

AWS pricing, included regional transfer, and overage rates can change. Before creating a resource, the agent asks you to confirm the specifications, price, and transfer allowance currently shown in the AWS Console. Numbers in this README are not billing commitments.

## Why Not One Giant “One-Click” Script?

Installing HiddifyPanel is not the hardest part. Real environments may also encounter:

- An installer that hangs without an interactive terminal
- HTTP 500 errors from the management panel
- Reality or Hysteria2 not being enabled correctly
- Missing UDP firewall rules
- A user that exists but has an unusable subscription
- Incorrect Clash or Mihomo routing rules
- Domain and subscription failures after a Static IP change
- HiddifyPanel upgrades that overwrite compatibility patches
- SSH, certificate, or network failures

A fixed shell script cannot reliably handle every one of these conditions. This project therefore uses:

> **Agent + Runbook + Scripts + Diagnostics**

Scripts handle environment checks, configuration validation, service checks, and deliverable generation. When something fails, the agent uses the actual version, logs, service state, and troubleshooting guide to choose the next action. For an undocumented problem, the agent should stop changing the server, collect evidence, and explain the situation instead of blindly repeating the installation.

## Technical Scope and Validation Status

The current compatibility baseline is:

- AWS Lightsail
- Ubuntu 22.04 LTS
- HiddifyPanel v12.3.3
- Reality + Hysteria2
- Clash / Mihomo / Shadowrocket subscriptions

The repository has passed configuration tests, static checks, and patch compatibility validation against the upstream HiddifyPanel v12.3.3 source. A fresh end-to-end regression on a new Lightsail environment has not yet been completed, so this project does not claim complete validation across every cloud environment.

Some patches are tied to the source layout of this exact version, so the agent does not silently upgrade to `latest`. Before an upgrade, upstream changes, patch applicability, and the complete deployment flow must be reviewed again. See [docs/UPGRADING.md](docs/UPGRADING.md).

Current boundaries include:

- Only AWS Lightsail is supported; other cloud providers are not yet adapted
- `sslip.io` is a free third-party service and can be replaced with your own domain
- AWS resources must be initialized by the user in the Console; the agent handles subsequent server deployment to avoid exposing broad AWS account permissions

## Security and Cost

The default workflow follows these principles:

- The user always retains control of the AWS password and MFA
- SSH uses the local `.pem` file; its contents are not copied into chat or uploaded to the server
- Sensitive deployment information is stored only in the Git-ignored `.local/` directory
- Every user receives separate subscription credentials
- HiddifyPanel files are backed up before modification, and patches stop on version mismatch
- A 2 GB swap file is created by default to buffer transient memory pressure on 1 GB instances
- Resource deletion, non-default user deletion, upgrades, and rollbacks require confirmation
- All critical services must pass real checks before delivery

Costs come from your own AWS Lightsail instance, network traffic beyond the plan allowance, and an optional custom domain. The project does not create paid resources outside the confirmed configuration. The AWS Console and your final bill are the source of truth for pricing.

## Documentation

To deploy, start with [AGENTS.md](AGENTS.md).

- [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md): Complete deployment workflow
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): Architecture, configuration flow, and system boundaries
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md): Diagnostics and known issues
- [docs/SECURITY.md](docs/SECURITY.md): Deployment security design
- [docs/UPGRADING.md](docs/UPGRADING.md): Version upgrade process
- [SECURITY.md](SECURITY.md): Security reporting process
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md): Third-party code and license notices

## Disclaimer

This project is intended only for lawful, compliant, and authorized use. Users are responsible for complying with local laws, AWS terms, and the licenses and terms of HiddifyPanel, client software, and other third-party projects.

Users are also responsible for cloud costs, network availability, IP availability, and compliance with local law.

## License

Original scripts, configuration templates, and documentation in this repository are licensed under the MIT License.

Files under `patches/` contain upstream source context from HiddifyPanel v12.3.3 and are distributed under CC BY-NC-SA 4.0. They are outside the root MIT License grant. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
