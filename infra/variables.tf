variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
}

variable "location" {
  description = "Primary region. South Africa North (Johannesburg) has availability zones."
  type        = string
  default     = "southafricanorth"
}

variable "environment" {
  description = "Environment name, used in resource names."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "nonprod", "prod"], var.environment)
    error_message = "environment must be dev, nonprod or prod."
  }
}

variable "owner" {
  description = "Who is responsible for these resources. Becomes the owner tag."
  type        = string
}

variable "cost_center" {
  description = "Who pays. Becomes the cost-center tag, used for chargeback."
  type        = string
  default     = "portfolio"
}

variable "hub_cidr" {
  description = "Address space for the hub VNet. See the IP plan in docs/ip-plan.md."
  type        = string
  default     = "10.10.0.0/22"
}

variable "spokes" {
  description = "Workload spokes. Add an entry to vend a new spoke."
  type = map(object({
    cidr = string
  }))
  default = {
    app  = { cidr = "10.20.0.0/22" }
    data = { cidr = "10.30.0.0/22" }
  }
}
