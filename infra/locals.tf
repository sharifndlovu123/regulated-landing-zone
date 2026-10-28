locals {
  # Short region code keeps names readable: southafricanorth -> san
  region_short = { southafricanorth = "san", southafricawest = "saw" }[var.location]

  # Pattern used for every resource: <type>-<workload>-<env>-<region>
  suffix = "lz-${var.environment}-${local.region_short}"

  # The policy work in a later piece will REQUIRE these tags, so every resource carries them from day one.
  tags = {
    owner       = var.owner
    environment = var.environment
    cost-center = var.cost_center
    managed-by  = "terraform"
  }
}
