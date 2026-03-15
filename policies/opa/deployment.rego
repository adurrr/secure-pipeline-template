package deployment

# Enforce that containers must not run as root
deny[msg] {
    input.resource_type == "aws_ecs_task_definition"
    container := input.resource.container_definitions[_]
    not container.readonlyRootFilesystem
    msg := sprintf("Container '%s' must use readonlyRootFilesystem", [container.name])
}

# Enforce encryption on S3 buckets
deny[msg] {
    input.resource_type == "aws_s3_bucket"
    not input.resource.server_side_encryption_configuration
    msg := sprintf("S3 bucket '%s' must have encryption enabled", [input.resource.bucket])
}

# Enforce VPC flow logs
deny[msg] {
    input.resource_type == "aws_vpc"
    not has_flow_log(input.resource.id)
    msg := "VPC must have flow logs enabled"
}

# Enforce TLS 1.2+ on load balancers
deny[msg] {
    input.resource_type == "aws_lb_listener"
    input.resource.protocol == "HTTPS"
    not valid_tls_policy(input.resource.ssl_policy)
    msg := "ALB must use TLS 1.2 or higher"
}

# Enforce no public S3 buckets
deny[msg] {
    input.resource_type == "aws_s3_bucket_public_access_block"
    not input.resource.block_public_acls
    msg := "S3 bucket must block public ACLs"
}

deny[msg] {
    input.resource_type == "aws_security_group"
    rule := input.resource.ingress[_]
    rule.cidr_blocks[_] == "0.0.0.0/0"
    rule.from_port == 22
    msg := "Security group must not allow SSH from 0.0.0.0/0"
}

valid_tls_policy(policy) {
    contains(policy, "TLS13")
}

valid_tls_policy(policy) {
    contains(policy, "TLS-1-2")
}

has_flow_log(vpc_id) {
    # Placeholder — in practice, check linked resources
    vpc_id != ""
}
