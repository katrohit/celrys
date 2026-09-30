variable "location" {
  type    = string
  default = "centralindia"
}
variable "environment" {
  type    = string
  default = "prod"
}
variable "name_prefix" {
  type    = string
  default = "celrys"
}
variable "web_hostname" {
  type    = string
  default = "mesend.celrys.com"
}
variable "api_hostname" {
  type    = string
  default = "api.mesend.celrys.com"
}
variable "vm_size" {
  type    = string
  default = "Standard_B2ms"
}
variable "admin_username" {
  type    = string
  default = "celrysadmin"
}
variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key only; never commit a private key."
}
variable "allowed_key_vault_ip_ranges" {
  type        = list(string)
  default     = []
  description = "Operator/CI IPv4 CIDRs allowed to write Key Vault secrets."
}
