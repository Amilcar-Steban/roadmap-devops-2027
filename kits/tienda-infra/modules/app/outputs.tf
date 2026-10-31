output "url" {
  description = "URL del balanceador."
  value       = "${local.https ? "https" : "http"}://${aws_lb.this.dns_name}"
}

output "alb_dns" {
  description = "DNS del balanceador (origen /api/* de CloudFront)."
  value       = aws_lb.this.dns_name
}

output "ecr_url" {
  description = "Repositorio de imágenes (variable ECR_REPOSITORY del workflow Deploy AWS: la parte tras la /)."
  value       = aws_ecr_repository.api.repository_url
}

output "cluster" {
  description = "Nombre del clúster (variable ECS_CLUSTER)."
  value       = aws_ecs_cluster.this.name
}

output "servicio" {
  description = "Nombre del servicio (variable ECS_SERVICE)."
  value       = aws_ecs_service.api.name
}

output "rol_ejecucion_arn" {
  description = "executionRoleArn para aws/ecs/task-definition.json."
  value       = aws_iam_role.ejecucion.arn
}

output "rol_tarea_arn" {
  description = "taskRoleArn para aws/ecs/task-definition.json."
  value       = aws_iam_role.tarea.arn
}
