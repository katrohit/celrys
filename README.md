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

## Link tracking and SES engagement tracking

Email links are tracked by MillionSend itself through `lm.gotixi.in`. Caddy proxies that host to the web app (`millionsend:3000`, which serves `/t/c/<token>`), not the API on port 3001, which returns 404 for tracked links.

SES must not wrap links a second time. Virtual Deliverability Manager (VDM) engagement metrics rewrite every link to `*.r.<region>.awstrack.me` and add an open pixel, whatever the config set's event destinations say. This is turned off for the SES account in `us-east-1` (`VdmAttributes.DashboardAttributes.EngagementMetrics = DISABLED`), so new domains and config sets are covered. VDM itself and Guardian's optimized shared delivery stay on.

- Check: `aws sesv2 get-account --region us-east-1 --query VdmAttributes`
- Undo: `aws sesv2 put-account-vdm-attributes --region us-east-1 --vdm-attributes 'VdmEnabled=ENABLED,DashboardAttributes={EngagementMetrics=ENABLED},GuardianAttributes={OptimizedSharedDelivery=ENABLED}'`
- SES is not managed in this repo. If it is managed in Terraform elsewhere, set `engagement_metrics = "DISABLED"` in `aws_sesv2_account_vdm_attributes`, or the next apply may turn it back on.
- The setting is per region. Repeat it for any other region used for sending.
- It only affects emails sent after the change. Links in earlier emails still go through `awstrack.me`, then on to `lm.gotixi.in`.
