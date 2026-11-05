# Trabajo 4 - Pipeline de datos en AWS con Terraform

Big Data, Universidad. Autores: Pedro Sierra y Tomas Lopera.

Arquitectura de un pipeline de datos en AWS descrita como Infraestructura como Código:

- Ingesta: SNS topic + cola SQS (con DLQ)
- Almacenamiento: bucket S3 (data lake)
- Procesamiento: rol IAM del procesador (Lambda) con mínimo privilegio
- Consumo: Glue Data Catalog + Athena

## Contenido

- `main.tf`: toda la arquitectura, comentada.
- `informe/Informe_Trabajo4_Sierra_Lopera.docx`: informe de arquitectura.
- `informe/diagrama.png`: diagrama del informe.
- `instrucciones.md`: enunciado.

## Validar

```
terraform init
terraform validate
```

No hace falta cuenta de AWS: el proveedor está configurado para validar sin credenciales. No se desplegó infraestructura.
