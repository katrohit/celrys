# celrys

Production infrastructure for free, self-hosted tools on `xyz.celrys.com`.

The first service is [MillionSend](https://github.com/MillionSend/millionsend): a self-hosted email platform backed by AWS SES. It runs as Docker Compose on one small Azure VM, with Azure Key Vault and remote Terraform state.

## Design principles

- Terraform state lives only in an Azure Storage account with versioning, soft-delete, RBAC, TLS-only access, and no public blob access.
- Application secrets live in Azure Key Vault and are read by the VM using managed identity.
- PostgreSQL, the app, and Caddy run privately in Docker Compose; only ports 80, 443, and SSH reach the VM.
- Caddy issues TLS certificates and routes `/ses/events` to the API, which MillionSend requires for SES event delivery.

## Start here

Read [the deployment guide](docs/millionsend.md). It walks through state bootstrap, Azure deployment, Key Vault secret loading, DNS, AWS SES, and first-user setup.
