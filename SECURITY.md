# Security Policy

## Reporting a vulnerability

Do not open a public issue containing a real server IP, subscription URL, UUID, admin path, API key, private key, or exploit details.

After the repository is published on GitHub, use its private vulnerability reporting / Security Advisory feature. Until a private channel is configured, prepare a redacted reproduction and wait for the maintainer to publish a reporting address.

Include affected commit, Hiddify version, impact, reproduction steps, and a redacted log. Never attach `.local/`, `current.json`, a PEM file, or a full subscription response.

## Supported scope

Only the HiddifyPanel version explicitly accepted by `scripts/deployment_config.py` is supported. Reports against unverified latest releases may require a separate compatibility review.
