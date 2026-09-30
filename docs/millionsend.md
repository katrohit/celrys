# MillionSend on one VM

This is intentionally a small deployment for two users: one Standard_B2ms Ubuntu VM, Docker Compose, and its 64-GB Premium OS disk. It is not an HA design.

## Deploy

1. Bootstrap remote Terraform state:

```bash
cd infra
RESOURCE_GROUP=rg-celrys-state LOCATION=centralindia STATE_STORAGE_ACCOUNT=<unique-name> ./bootstrap-state.sh
terraform init -backend-config=backend.hcl
```

2. Create ignored `terraform.tfvars`:

```hcl
admin_ssh_public_key = "ssh-ed25519 AAAA..."
allowed_key_vault_ip_ranges = ["YOUR.PUBLIC.IP/32"]
```

3. Apply: `terraform apply`.

4. Provision AWS SES using MillionSend's upstream guide, then add its runtime values to Key Vault:

```bash
VAULT=$(terraform output -raw key_vault_name)
az keyvault secret set --vault-name "$VAULT" --name aws-access-key-id --value "<value>"
az keyvault secret set --vault-name "$VAULT" --name aws-secret-access-key --value "<value>"
az keyvault secret set --vault-name "$VAULT" --name sns-topic-arns --value "<topic-arn>"
az keyvault secret set --vault-name "$VAULT" --name sqs-queue-url --value "<queue-url>"
```

5. Point `millionsend.xyz.celrys.com` and `api.millionsend.xyz.celrys.com` A records at `terraform output -raw public_ip_address`. SSH in, then run:

```bash
sudo /usr/local/bin/celrys-sync-secrets
```

Caddy gets TLS certificates after DNS resolves. Register the first MillionSend user, then leave `ALLOW_SIGNUP=false`.

## Operations

- Update: `cd /opt/millionsend && sudo docker compose pull && sudo docker compose up -d`
- Rotate a Key Vault secret, then run `sudo /usr/local/bin/celrys-sync-secrets`.
- Back up first: `sudo docker compose exec -T postgres pg_dump -U millionsend millionsend > millionsend-$(date +%F).sql`.
- Restrict SSH in the NSG to your own IP before treating this as internet-facing.
