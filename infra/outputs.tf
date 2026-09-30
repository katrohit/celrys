output "key_vault_name" { value = azurerm_key_vault.platform.name }
output "public_ip_address" { value = azurerm_public_ip.vm.ip_address }
output "web_hostname" { value = var.web_hostname }
output "api_hostname" { value = var.api_hostname }
output "ssh_command" { value = "ssh ${var.admin_username}@${azurerm_public_ip.vm.ip_address}" }
