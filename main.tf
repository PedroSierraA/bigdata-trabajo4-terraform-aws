###############################################################################
# BIG DATA - TRABAJO 4: Pipeline de datos en AWS con Terraform
# Autores: Pedro Sierra, Tomas Lopera
#
# Flujo:  Productor -> SNS topic -> SQS queue (subscription) -> Lambda (rol IAM)
#         -> lee/escribe en S3 (data lake) -> tabla Glue consultable con Athena
#
# Dominio del dato: eventos de ventas de una tienda en línea.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Permiten que "terraform validate/plan" funcionen SIN credenciales reales.
  # (Para un despliegue real se pueden quitar estas tres líneas.)
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

###############################################################################
# VARIABLES
###############################################################################

variable "region" {
  description = "Región de AWS donde se despliega el pipeline"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefijo para nombrar todos los recursos"
  type        = string
  default     = "ventas-pipeline"
}

variable "account_id" {
  description = "ID de la cuenta AWS (se usa para que el nombre del bucket sea único globalmente)"
  type        = string
  default     = "123456789012"
}

###############################################################################
# 1. INGESTA: SNS topic + SQS queue suscrita (+ DLQ)
#    SNS = canal de mensajería (equivalente a Pub/Sub topic).
#    SQS = la "subscription": cola durable de la que el procesador lee.
###############################################################################

resource "aws_sns_topic" "eventos" {
  name = "${var.project}-eventos"
}

# Cola de mensajes fallidos: si un evento falla 3 veces, no se pierde ni
# bloquea el flujo; queda aquí para inspección.
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project}-eventos-dlq"
  message_retention_seconds = 1209600 # 14 días
}

resource "aws_sqs_queue" "eventos" {
  name                       = "${var.project}-eventos"
  visibility_timeout_seconds = 60     # debe ser >= timeout del procesador
  message_retention_seconds  = 345600 # 4 días de colchón si el procesador cae

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# Suscripción: todo lo publicado en el topic llega a la cola.
resource "aws_sns_topic_subscription" "eventos_a_cola" {
  topic_arn            = aws_sns_topic.eventos.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.eventos.arn
  raw_message_delivery = true
}

# Permiso de RECURSO: solo ESTE topic puede escribir en ESTA cola.
resource "aws_sqs_queue_policy" "permite_sns" {
  queue_url = aws_sqs_queue.eventos.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "SoloDesdeElTopic"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.eventos.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.eventos.arn } }
    }]
  })
}

###############################################################################
# 2. ALMACENAMIENTO: bucket S3 (data lake)
#    Prefijos:  raw/      -> datos crudos tal como llegan
#               curated/  -> datos limpios que consulta el warehouse
#               athena-results/ -> resultados de consultas
###############################################################################

resource "aws_s3_bucket" "lake" {
  bucket        = "${var.project}-lake-${var.account_id}"
  force_destroy = true # facilita 'terraform destroy' en un entorno académico
}

# El lake nunca debe ser público.
resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Control de costos: los datos crudos viejos pasan a almacenamiento más barato.
resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    id     = "raw-a-infrequent-access"
    status = "Enabled"
    filter { prefix = "raw/" }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

###############################################################################
# 3. PROCESAMIENTO: identidad (rol IAM) del job que procesa
#    La función Lambda asumiría este rol. Aquí modelamos la identidad y sus
#    permisos; el código de la Lambda queda fuera del alcance del trabajo.
###############################################################################

resource "aws_iam_role" "procesador" {
  name = "${var.project}-procesador"

  # Trust policy: solo el servicio Lambda puede asumir este rol.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

###############################################################################
# 4. CONSUMO: warehouse consultable = Glue Data Catalog + Athena
#    La tabla tiene esquema y apunta a s3://.../curated/. Athena ejecuta SQL
#    directamente sobre esos archivos (serverless).
###############################################################################

resource "aws_glue_catalog_database" "warehouse" {
  name = replace("${var.project}_db", "-", "_")
}

resource "aws_glue_catalog_table" "ventas" {
  name          = "ventas"
  database_name = aws_glue_catalog_database.warehouse.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "parquet"
  }

  partition_keys {
    name = "fecha"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lake.bucket}/curated/ventas/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "event_id"
      type = "string"
    }
    columns {
      name = "timestamp"
      type = "timestamp"
    }
    columns {
      name = "cliente_id"
      type = "string"
    }
    columns {
      name = "producto"
      type = "string"
    }
    columns {
      name = "cantidad"
      type = "int"
    }
    columns {
      name = "valor"
      type = "double"
    }
  }
}

resource "aws_athena_workgroup" "analistas" {
  name          = "${var.project}-analistas"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.bucket}/athena-results/"
    }
  }
}

###############################################################################
# 5. PERMISOS (IAM) - MÍNIMO PRIVILEGIO
#    El procesador necesita: leer de la ingesta, leer el lake, escribir en el
#    warehouse y escribir sus logs. Nada más. Cada permiso apunta a un ARN
#    concreto (nunca "Resource": "*") y a las acciones estrictamente necesarias.
###############################################################################

data "aws_iam_policy_document" "procesador" {

  # (a) INGESTA: consumir mensajes SOLO de la cola de eventos.
  statement {
    sid       = "LeerDeLaCola"
    effect    = "Allow"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.eventos.arn]
  }

  # (b) LAKE (lectura): solo leer objetos del prefijo raw/.
  statement {
    sid       = "LeerRawDelLake"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.lake.arn}/raw/*"]
  }

  statement {
    sid       = "ListarElLake"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.lake.arn]
  }

  # (c) WAREHOUSE (escritura): escribir SOLO en curated/ventas/ (donde apunta
  #     la tabla) y registrar particiones SOLO en esa base y tabla del catálogo.
  statement {
    sid       = "EscribirCuratedEnElLake"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.lake.arn}/curated/ventas/*"]
  }

  statement {
    sid     = "RegistrarParticionesEnLaTabla"
    effect  = "Allow"
    actions = ["glue:GetTable", "glue:GetPartition", "glue:BatchCreatePartition", "glue:CreatePartition"]
    resources = [
      "arn:aws:glue:${var.region}:${var.account_id}:catalog",
      aws_glue_catalog_database.warehouse.arn,
      aws_glue_catalog_table.ventas.arn,
    ]
  }

  # (d) LOGS: solo su propio grupo de logs.
  statement {
    sid       = "EscribirSusLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.procesador.arn}:*"]
  }
}

resource "aws_cloudwatch_log_group" "procesador" {
  name              = "/aws/lambda/${var.project}-procesador"
  retention_in_days = 14
}

resource "aws_iam_policy" "procesador" {
  name   = "${var.project}-procesador-minimo-privilegio"
  policy = data.aws_iam_policy_document.procesador.json
}

resource "aws_iam_role_policy_attachment" "procesador" {
  role       = aws_iam_role.procesador.name
  policy_arn = aws_iam_policy.procesador.arn
}

###############################################################################
# OUTPUTS
###############################################################################

output "sns_topic_arn" {
  value = aws_sns_topic.eventos.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.eventos.id
}

output "s3_lake_bucket" {
  value = aws_s3_bucket.lake.bucket
}

output "procesador_role_arn" {
  value = aws_iam_role.procesador.arn
}

output "glue_database" {
  value = aws_glue_catalog_database.warehouse.name
}
