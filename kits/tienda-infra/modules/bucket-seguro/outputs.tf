output "nombre" {
  description = "Nombre del bucket."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "ARN del bucket."
  value       = aws_s3_bucket.this.arn
}

output "dominio_regional" {
  description = "Dominio regional, para usarlo como origen de CloudFront."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
