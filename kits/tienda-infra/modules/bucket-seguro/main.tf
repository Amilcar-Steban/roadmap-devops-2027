# Bucket S3 privado, cifrado y con versionado. Valores por defecto seguros: hay que pedir
# explícitamente lo contrario.

# Los logs de acceso de S3 irían a otro bucket que a su vez necesitaría logs: se activan con
# CloudTrail (eventos de datos) cuando hace falta auditar, no en cada bucket.
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "this" {
  bucket        = var.nombre
  force_destroy = var.forzar_borrado
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced" # sin ACL: los permisos solo vienen de políticas
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versionado ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null # menos llamadas (y coste) a KMS
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = var.versionado ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "versiones-antiguas"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.dias_versiones_antiguas
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

data "aws_iam_policy_document" "this" {
  source_policy_documents = var.politicas_adicionales

  statement {
    sid     = "SoloTLS"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json

  # El bloqueo de acceso público debe existir antes de aplicar cualquier política
  depends_on = [aws_s3_bucket_public_access_block.this]
}
