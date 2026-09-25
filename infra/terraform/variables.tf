variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Short name used to prefix all resources"
  type        = string
  default     = "visionx"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "backend_container_port" {
  type    = number
  default = 8000
}

variable "frontend_container_port" {
  type    = number
  default = 3000
}

variable "backend_cpu" {
  description = "Fargate task CPU units for backend (heavy ML deps: torch, mediapipe, insightface, paddleocr)"
  type        = number
  default     = 2048
}

variable "backend_memory" {
  description = "Fargate task memory (MB) for backend"
  type        = number
  default     = 8192
}

variable "frontend_cpu" {
  type    = number
  default = 512
}

variable "frontend_memory" {
  type    = number
  default = 1024
}

variable "backend_desired_count" {
  type    = number
  default = 1
}

variable "frontend_desired_count" {
  type    = number
  default = 1
}

variable "backend_image_tag" {
  description = "Docker image tag to deploy for backend (set by CI)"
  type        = string
  default     = "latest"
}

variable "frontend_image_tag" {
  description = "Docker image tag to deploy for frontend (set by CI)"
  type        = string
  default     = "latest"
}

# ---- Secrets (sensitive - pass via TF_VAR_* env vars or a tfvars file that's gitignored, never commit) ----

variable "secret_key" {
  description = "Backend SECRET_KEY (min 32 chars)"
  type        = string
  sensitive   = true
}

variable "jwt_secret_key" {
  description = "Backend JWT_SECRET_KEY (min 32 chars)"
  type        = string
  sensitive   = true
}

variable "supabase_url" {
  description = "Supabase project URL (leave empty to keep local dev-auth fallback in production - not recommended)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "supabase_service_role_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "supabase_anon_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "gemini_api_key" {
  type      = string
  default   = ""
  sensitive = true
}
