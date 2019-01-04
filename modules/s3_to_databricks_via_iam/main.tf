# dillon.bostwick@databricks.com

provider "aws" { # Default
  region     = "${var.aws_region}"
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  version    = "~>1.52.0"
}

# This is only initialized if the connection is cross account.
# In this case the "foreign"
# account refers to the account that is not the account hosting the
# Databricks data plane account. If both VPCs are in the same account,
# then the above "default" (aka non-aliased) provider is used for all resources
# in this module 
provider "aws" {
  alias      = "foreign_acct"
  region     = "${var.aws_foreign_acct_region != "" ? var.aws_foreign_acct_region : var.aws_region}"
  access_key = "${var.aws_foreign_acct_access_key != "" ? var.aws_foreign_acct_access_key : var.aws_access_key}"
  secret_key = "${var.aws_foreign_acct_secret_key != "" ? var.aws_foreign_acct_secret_key : var.aws_secret_key}"
  version    = "~>1.52.0"
}

locals {
  multi_account = "${var.aws_foreign_acct_access_key == "" ? 0 : 0}"
}

# provider "http" {}

# Get account metadata of the primary account (databricks account)
data "aws_caller_identity" "current" {}

# Set up bucket policy:

data "aws_s3_bucket" "target_s3_bucket" {
  provider = "aws.foreign_acct"
  bucket = "${var.s3_bucket_name}"
}

data "template_file" "bucket_policy" {
  template = "${file("${path.module}/policies/bucket_policy.template.json")}"

  vars = {
    db_aws_account_id     = "${data.aws_caller_identity.current.account_id}"
    s3_cross_account_role = "${aws_iam_role.databricks_to_s3_role.id}"
    target_bucket_name    = "${data.aws_s3_bucket.target_s3_bucket.id}"
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  provider = "aws.foreign_acct"
  bucket = "${data.aws_s3_bucket.target_s3_bucket.id}"
  policy = "${data.template_file.bucket_policy.rendered}"
}

# # Configure IAM role for Databricks to access bucket:

# Role for S3 access
resource "aws_iam_role" "databricks_to_s3_role" {
  # provider           = "aws.db_acct"
  name               = "${var.custom_iam_role_name}"
  assume_role_policy = "${file("${path.module}/policies/assume_role_policy.json")}"
}

# Need to explicitally specify the instance profile for the role as well
resource "aws_iam_instance_profile" "role_instance_profile" {
  # provider = "aws.db_acct"
  name     = "${aws_iam_role.databricks_to_s3_role.name}"
  role     = "${aws_iam_role.databricks_to_s3_role.name}"
}

# Attach an inline policy to the role
resource "aws_iam_policy" "databricks_to_s3_policy" {
  # provider = "aws.db_acct"
  name     = "${var.custom_iam_role_name}-policy"
  policy   = "${data.template_file.databricks_to_s3_policy_config.rendered}"
}

resource "aws_iam_role_policy_attachment" "attach_policy_to_role" {
  # provider   = "aws.db_acct"
  role       = "${aws_iam_role.databricks_to_s3_role.id}"
  policy_arn = "${aws_iam_policy.databricks_to_s3_policy.arn}"
}

# Interpolate the role inline policy config template
data "template_file" "databricks_to_s3_policy_config" {
  template = "${file("${path.module}/policies/role_policy.template.json")}"

  vars = {
    target_bucket_name = "${data.aws_s3_bucket.target_s3_bucket.id}"
  }
}

# Set up pass through from the workspace role:

# New policy gets added to the existing Databricks EC2 role:
resource "aws_iam_policy" "pass_through_policy" {
  # provider = "aws.db_acct"
  name     = "${var.databricks_deployment_role}-policy" # TODO do not do not use the role name
  policy   = "${data.template_file.pass_through_policy_config.rendered}"
}

resource "aws_iam_role_policy_attachment" "attach_pass_through_policy_to_databricks_bucket_role" {
  # provider   = "aws.db_acct"
  role       = "${var.databricks_deployment_role}"
  policy_arn = "${aws_iam_policy.pass_through_policy.arn}"
}

data "template_file" "pass_through_policy_config" {
  template = "${file("${path.module}/policies/pass_through_policy.template.json")}"

  vars = {
    aws_account_id_databricks = "${data.aws_caller_identity.current.account_id}"
    iam_role_for_s3_access    = "${aws_iam_role.databricks_to_s3_role.name}"
    foo                       = "hello"
  }
}

# User must now enter the IAM Role to Databricks, etc:

data "aws_iam_instance_profile" "databricks_to_s3_role_instance_profile" {
  # provider = "aws.db_acct"
  name     = "${aws_iam_role.databricks_to_s3_role.id}"
}

# # Use Instance Profiles API to add the new role
# data "http" "add_instance_profile_to_databricks" {
#   url = "${var.databricks_workspace_url}Cust/api/2.0/instance-profiles/add"


#   request_headers {
#     "Content-Type" = "application/json"
#     "Authorization" = "Bearer ${var.databricks_access_token}"
#   }


#   body = "{ \"instance_profile_arn\": \"${data.aws_iam_instance_profile.databricks_to_s3_role_instance_profile.arn}\" }"
# }

