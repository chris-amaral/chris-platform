###############################################################################
# Backend Configuration (partial)
# Use: terraform init -backend-config=inventories/<env>/backend.hcl
# Author: Christopher Amaral
###############################################################################

terraform {
  backend "s3" {}
}
