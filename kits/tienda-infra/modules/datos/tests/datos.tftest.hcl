mock_provider "aws" {
  mock_resource "aws_db_instance" {
    defaults = {
      address = "tienda-test.abc123.us-east-1.rds.amazonaws.com"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-test-AbCdEf"
        secret_status = "active"
        kms_key_id    = "arn:aws:kms:us-east-1:123456789012:key/test"
      }]
    }
  }
}

variables {
  nombre         = "tienda-test"
  vpc_id         = "vpc-0123456789abcdef0"
  subredes_datos = ["subnet-aaaa", "subnet-bbbb"]
  prefijo_ssm    = "/tienda/test/datos"
}

run "dev_barato" {
  command = apply

  variables {
    multi_az           = false
    replicas_cache     = 0
    proteccion_borrado = false
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password && aws_db_instance.this.password == null
    error_message = "La contraseña debe gestionarla RDS, nunca Terraform."
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted && !aws_db_instance.this.publicly_accessible
    error_message = "La base debe estar cifrada y sin acceso público."
  }

  assert {
    condition     = !aws_elasticache_replication_group.this.automatic_failover_enabled && aws_elasticache_replication_group.this.num_cache_clusters == 1
    error_message = "Sin réplicas no puede haber failover."
  }

  assert {
    condition     = aws_db_instance.this.skip_final_snapshot && !aws_db_instance.this.deletion_protection
    error_message = "En dev se debe poder destruir sin snapshot final."
  }

  assert {
    condition     = aws_ssm_parameter.publicado["secreto_bd_arn"].value == "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-test-AbCdEf"
    error_message = "El ARN del secreto debe publicarse en Parameter Store."
  }
}

run "prod_resistente" {
  command = apply

  variables {
    multi_az       = true
    replicas_cache = 1
  }

  assert {
    condition     = aws_db_instance.this.multi_az && aws_db_instance.this.deletion_protection
    error_message = "En prod la base debe ser Multi-AZ y estar protegida contra borrado."
  }

  assert {
    condition     = aws_db_instance.this.final_snapshot_identifier == "tienda-test-final"
    error_message = "En prod se debe guardar un snapshot final."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.automatic_failover_enabled && aws_elasticache_replication_group.this.multi_az_enabled
    error_message = "Con una réplica, la caché debe tener failover Multi-AZ."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.bd.referenced_security_group_id == aws_security_group.clientes.id
    error_message = "Solo el security group de clientes debe llegar a PostgreSQL."
  }
}

run "rechaza_una_sola_subred" {
  command = plan

  variables {
    subredes_datos = ["subnet-aaaa"]
  }

  expect_failures = [var.subredes_datos]
}
