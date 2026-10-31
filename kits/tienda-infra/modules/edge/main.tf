# Entrada de la tienda: CloudFront sirve el frontend desde un bucket privado (OAC) y
# reenvía /api/* al balanceador, sin caché.
#
#   usuario ──HTTPS──► CloudFront ─┬─ /*      ──► S3 (privado, solo CloudFront puede leer)
#                                  └─ /api/*  ──► ALB ──► tareas ECS

locals {
  origen_s3  = "web"
  origen_alb = "api"
  # Políticas gestionadas por AWS (sus IDs son fijos y públicos)
  cache_optimizada         = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  cache_desactivada        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
  peticion_todo_menos_host = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader
}

# Cabeceras de seguridad: las mismas que pone el Nginx del proxy en Compose (Fase 8, escaneo de ZAP).
# La política gestionada Managed-SecurityHeadersPolicy no trae CSP ni Permissions-Policy.
resource "aws_cloudfront_response_headers_policy" "seguridad" {
  name    = "${var.nombre}-seguridad"
  comment = "CSP, anti-clickjacking, HSTS y permisos del navegador de la tienda"

  security_headers_config {
    content_security_policy {
      content_security_policy = "default-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
      override                = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), payment=()"
      override = true
    }
  }
}

module "web" {
  source = "../bucket-seguro"

  nombre                = var.bucket_web
  forzar_borrado        = var.forzar_borrado
  politicas_adicionales = [data.aws_iam_policy_document.solo_cloudfront.json]
}

# Solo esta distribución puede leer el bucket
data "aws_iam_policy_document" "solo_cloudfront" {
  statement {
    sid       = "LecturaDesdeCloudFront"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.bucket_web}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "${var.nombre}-web"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Los logs de acceso de CloudFront se añaden en la Fase 7 (observabilidad)
#trivy:ignore:AWS-0010
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.nombre
  default_root_object = "index.html"
  price_class         = var.clase_precio
  aliases             = var.alias
  web_acl_id          = var.waf_arn
  http_version        = "http2and3"

  origin {
    origin_id                = local.origen_s3
    domain_name              = module.web.dominio_regional
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  origin {
    origin_id   = local.origen_alb
    domain_name = var.alb_dns
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = var.alb_https ? "https-only" : "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id           = local.origen_s3
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = local.cache_optimizada
    response_headers_policy_id = aws_cloudfront_response_headers_policy.seguridad.id
    compress                   = true
  }

  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = local.origen_alb
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = local.cache_desactivada
    origin_request_policy_id   = local.peticion_todo_menos_host
    response_headers_policy_id = aws_cloudfront_response_headers_policy.seguridad.id
    compress                   = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.certificado_arn == null
    acm_certificate_arn            = var.certificado_arn
    ssl_support_method             = var.certificado_arn == null ? null : "sni-only"
    minimum_protocol_version       = var.certificado_arn == null ? "TLSv1" : "TLSv1.2_2021"
  }
}
