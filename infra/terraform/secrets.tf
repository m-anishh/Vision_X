resource "aws_secretsmanager_secret" "backend" {
  name = "${var.project_name}/${var.environment}/backend"
}

resource "aws_secretsmanager_secret_version" "backend" {
  secret_id = aws_secretsmanager_secret.backend.id
  secret_string = jsonencode({
    SECRET_KEY                = var.secret_key
    JWT_SECRET_KEY            = var.jwt_secret_key
    SUPABASE_URL              = var.supabase_url
    SUPABASE_SERVICE_ROLE_KEY = var.supabase_service_role_key
    SUPABASE_ANON_KEY         = var.supabase_anon_key
    GEMINI_API_KEY            = var.gemini_api_key
  })
}
