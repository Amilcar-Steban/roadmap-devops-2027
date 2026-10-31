# Pruebas sin AWS: el proveedor simulado inventa los atributos calculados (ids, ARNs).
# Ejecuta desde modules/bucket-seguro:  terraform init && terraform test
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  nombre = "tienda-pruebas-bucket-seguro"
}

run "privado_cifrado_y_versionado_por_defecto" {
  command = apply # con el proveedor simulado no se crea nada real

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "Las cuatro opciones de bloqueo de acceso público deben estar activas."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Sin clave KMS, el cifrado debe ser AES256."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "El versionado debe estar activo por defecto."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Las ACL deben estar desactivadas."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "Por defecto no se puede borrar un bucket con objetos."
  }
}

run "kms_si_se_pasa_una_clave" {
  command = apply

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Con clave KMS, el cifrado debe ser aws:kms."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled
    error_message = "Con KMS, el bucket key reduce las llamadas a KMS."
  }
}

run "sin_versionado_no_hay_regla_de_ciclo_de_vida" {
  command = plan

  variables {
    versionado = false
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this) == 0
    error_message = "Sin versionado no hace falta expirar versiones antiguas."
  }
}

run "rechaza_nombres_invalidos" {
  command = plan

  variables {
    nombre = "Nombre_Con_Mayusculas"
  }

  expect_failures = [var.nombre]
}
