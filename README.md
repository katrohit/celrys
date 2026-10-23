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

Email links are tracked by MillionSend itself through `lm.gotixi.in`. Caddy proxies that host to the web app (`millionsend:3000`, which serves `/t/c/<token>`), not the API on port 3001, which returns 404 for tracked links. Only `/t/*` is proxied; every other path on that host returns an empty 404 so it doesn't reveal MillionSend.

SES must not wrap links a second time. Virtual Deliverability Manager (VDM) engagement metrics rewrite every link to `*.r.<region>.awstrack.me` and add an open pixel, whatever the config set's event destinations say. This is turned off for the SES account in `us-east-1` (`VdmAttributes.DashboardAttributes.EngagementMetrics = DISABLED`), so new domains and config sets are covered. VDM itself and Guardian's optimized shared delivery stay on.

- Check: `aws sesv2 get-account --region us-east-1 --query VdmAttributes`
- Undo: `aws sesv2 put-account-vdm-attributes --region us-east-1 --vdm-attributes 'VdmEnabled=ENABLED,DashboardAttributes={EngagementMetrics=ENABLED},GuardianAttributes={OptimizedSharedDelivery=ENABLED}'`
- SES is not managed in this repo. If it is managed in Terraform elsewhere, set `engagement_metrics = "DISABLED"` in `aws_sesv2_account_vdm_attributes`, or the next apply may turn it back on.
- The setting is per region. Repeat it for any other region used for sending.
- It only affects emails sent after the change. Links in earlier emails still go through `awstrack.me`, then on to `lm.gotixi.in`.

## Adding a new sending/tracking domain in MillionSend

Link tracking only works if the tracking host is served by Caddy from this repo. When you add a domain in MillionSend:

1. Point the tracking host's A record (e.g. `lm.example.com`) at `terraform output -raw public_ip_address`. Ports 80 and 443 must be open so Caddy can get its Let's Encrypt certificate.
2. Add a site block that proxies to the web app (port 3000, not the API on 3001), in **both** `infra/Caddyfile` and the Caddyfile in `infra/cloud-init.yaml.tftpl`, so a rebuilt VM matches:

   ```
   lm.example.com {
     reverse_proxy millionsend:3000
   }
   ```

3. Open a PR and merge it (CI validates the Caddyfile), then run the "Deploy MillionSend" workflow. Leave `image_update` off unless you want a new MillionSend image.
4. The deploy reloads Caddy automatically after writing the Caddyfile, and fails if Caddy rejects the config. If you ever need to do it by hand: `sudo docker exec millionsend-caddy-1 caddy reload --config /etc/caddy/Caddyfile`.
5. Verify: `curl -sSI https://<host>/t/c/x` must show a valid certificate and an app response, and a real tracked link must return `302` to its destination, not `404`. Check the Caddy logs for `certificate obtained successfully` for the host.

Do not edit `/opt/millionsend/Caddyfile` on the VM with `sed -i` or an editor that replaces the file. The single-file Docker bind mount keeps reading the old file, so the change appears on disk but Caddy ignores it until the container is restarted (`sudo docker restart millionsend-caddy-1`). A hand edit on the VM is also overwritten by the next deploy unless it is in the repo.
