output "alb_dns_name" {
  description = "Public URL of the app (ALB). Frontend and /api/*, /health both live here."
  value       = aws_lb.main.dns_name
}

output "ecr_backend_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_backend_service_name" {
  value = aws_ecs_service.backend.name
}

output "ecs_frontend_service_name" {
  value = aws_ecs_service.frontend.name
}

output "backend_secret_arn" {
  value = aws_secretsmanager_secret.backend.arn
}
