output "url" {
  description = "URL pública de la tienda."
  value       = "https://${length(var.alias) > 0 ? var.alias[0] : aws_cloudfront_distribution.this.domain_name}"
}

output "distribucion_id" {
  description = "ID de la distribución (variable CF_DISTRIBUTION del workflow Deploy AWS)."
  value       = aws_cloudfront_distribution.this.id
}

output "bucket_web" {
  description = "Bucket del frontend (variable WEB_BUCKET del workflow Deploy AWS)."
  value       = module.web.nombre
}
