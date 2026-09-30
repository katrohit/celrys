data "azurerm_client_config" "current" {}
data "azurerm_dns_zone" "celrys" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_resource_group_name
}

locals {
  name = "${var.name_prefix}-${var.environment}"
  tags = { application = "celrys", environment = var.environment, managed-by = "terraform" }
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "platform" {
  name                = "vnet-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.platform.name
  address_space       = ["10.80.0.0/24"]
  tags                = local.tags
}

resource "azurerm_subnet" "vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.platform.name
  virtual_network_name = azurerm_virtual_network.platform.name
  address_prefixes     = ["10.80.0.0/25"]
  service_endpoints    = ["Microsoft.KeyVault"]
}

resource "azurerm_network_security_group" "vm" {
  name                = "nsg-${local.name}-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.platform.name
  security_rule {
    name                       = "web"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = local.tags
}

resource "azurerm_public_ip" "vm" {
  name                = "pip-${local.name}-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.platform.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_dns_a_record" "mesend" {
  name                = "mesend"
  zone_name           = data.azurerm_dns_zone.celrys.name
  resource_group_name = data.azurerm_dns_zone.celrys.resource_group
  ttl                 = 300
  records             = [azurerm_public_ip.vm.ip_address]
}

resource "azurerm_dns_a_record" "api_mesend" {
  name                = "api.mesend"
  zone_name           = data.azurerm_dns_zone.celrys.name
  resource_group_name = data.azurerm_dns_zone.celrys.resource_group
  ttl                 = 300
  records             = [azurerm_public_ip.vm.ip_address]
}

resource "azurerm_network_interface" "vm" {
  name                = "nic-${local.name}-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.platform.name
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
  tags = local.tags
}

resource "azurerm_network_interface_security_group_association" "vm" {
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

resource "azurerm_user_assigned_identity" "vm" {
  name                = "id-${local.name}-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags
}

resource "azurerm_key_vault" "platform" {
  name                          = "kv${replace(local.name, "-", "")}${random_string.suffix.result}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.platform.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = true
  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.vm.id]
    ip_rules                   = var.allowed_key_vault_ip_ranges
  }
  tags = local.tags
}

resource "azurerm_role_assignment" "vm_secrets" {
  scope                = azurerm_key_vault.platform.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.vm.principal_id
}

resource "azurerm_role_assignment" "operator_secrets" {
  scope                = azurerm_key_vault.platform.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "random_password" "postgres" {
  length  = 40
  special = true
}
resource "random_password" "master_key" {
  length  = 43
  special = false
}
resource "random_password" "auth_secret" {
  length  = 43
  special = false
}

resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-password"
  value        = random_password.postgres.result
  key_vault_id = azurerm_key_vault.platform.id
  depends_on   = [azurerm_role_assignment.operator_secrets]
}
resource "azurerm_key_vault_secret" "master_key" {
  name         = "master-encryption-key"
  value        = random_password.master_key.result
  key_vault_id = azurerm_key_vault.platform.id
  depends_on   = [azurerm_role_assignment.operator_secrets]
}
resource "azurerm_key_vault_secret" "auth_secret" {
  name         = "better-auth-secret"
  value        = random_password.auth_secret.result
  key_vault_id = azurerm_key_vault.platform.id
  depends_on   = [azurerm_role_assignment.operator_secrets]
}

resource "azurerm_linux_virtual_machine" "millionsend" {
  name                            = "vm-${local.name}-millionsend"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.platform.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.vm.id]
  disable_password_authentication = true
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vm.id]
  }
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    key_vault_name = azurerm_key_vault.platform.name
    web_hostname   = var.web_hostname
    api_hostname   = var.api_hostname
  }))
  tags       = local.tags
  depends_on = [azurerm_role_assignment.vm_secrets]
}
