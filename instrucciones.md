BIG DATA · TRABAJO 4 (EVALUACIÓN FINAL)
Arquitectura de un pipeline en la nube con Terraform
Infraestructura como Código: diseña, justifica y (opcionalmente) despliega
Prof. Alejandro Mery Agudelo · En parejas · Entrega por Teams
De qué se trata
A lo largo de la unidad de nube recorriste las piezas de un pipeline de datos moderno: ingesta, almacenamiento (data lake), procesamiento y consumo (warehouse). En este trabajo final las vas a unir, pero no operándolas a mano: las vas a DISEÑAR como Infraestructura como Código (IaC) con Terraform. Escribirás un archivo que describe toda la arquitectura, y sustentarás por qué cada pieza está ahí y cómo se conectan.
Lo más importante que debes entender
No se evalúa que despliegues infraestructura (eso puede costar dinero). Se evalúa que DISEÑES una arquitectura correcta y que SUSTENTES tus decisiones. El código y el informe de arquitectura valen más que el despliegue.
Desplegar es OPCIONAL. Validar el código con 'terraform validate' es obligatorio (es gratis y no crea nada).

Qué es Terraform (en breve)
Terraform es la herramienta estándar de la industria para Infraestructura como Código: en vez de crear recursos a clic en la consola de la nube, los describes en un archivo de texto (.tf). Ese archivo es versionable, revisable y reproducible. Un mismo archivo puede desplegar la misma arquitectura mil veces, igual. Es agnóstico de nube: sirve para AWS, Google Cloud, Azure y más.
Instalar y validar (gratis, sin cuenta de pago)

1. Instala Terraform: https://developer.hashicorp.com/terraform/install
2. En la carpeta de tu proyecto: terraform init (descarga el plugin del proveedor)
3. Valida la sintaxis y la lógica: terraform validate
   terraform validate NO crea nada ni cuesta: solo revisa que tu arquitectura 'compile'.

Qué deben construir
Un archivo Terraform (main.tf) que modele un pipeline de datos en la nube con las 4 capas que vimos, más los permisos que las conectan. El ejemplo de referencia usa Google Cloud (los servicios que ya conocen), pero pueden usar la nube que prefieran — justifíquenlo en el informe.
Las piezas (mínimo)
Capa
Qué modelar
Ejemplo GCP
Ingesta
Un canal de mensajería para el flujo de eventos + su subscription
Pub/Sub topic + subscription
Almacenamiento
Un bucket de object storage (data lake)
Cloud Storage bucket
Procesamiento
La identidad (service account) del job que procesa
Service Account
Consumo
Un warehouse con al menos una tabla con esquema
BigQuery dataset + table
Permisos (IAM)
Los permisos que conectan el procesador con las otras 3 capas
IAM members

Pista: la parte de IAM es la que separa un buen diseño de uno mediocre
Modelar los recursos es la parte fácil. Lo valioso es conectarlos con permisos CORRECTOS y MÍNIMOS: el procesador necesita leer del lake y de la ingesta, y escribir en el warehouse — nada más. Ese principio (mínimo privilegio) es clave en arquitectura cloud real.

Una plantilla
Para que no partan de cero con una herramienta nueva, le adjunto un esqueleto (plantilla/main.tf) con la estructura y comentarios TODO que indican qué completar. Pueden partir de ahí, o escribir el suyo desde cero si prefieren.

El informe de arquitectura (el corazón del trabajo)
Esta es la parte que más pesa. Un documento (PDF, máx. 5 páginas) que acompaña al código y donde SUSTENTAN sus decisiones. Debe incluir:
Un DIAGRAMA de la arquitectura: las piezas y las flechas que las conectan (pueden dibujarlo a mano, en draw.io, donde sea).
Por cada pieza, una justificación corta: ¿qué servicio elegiste y por qué? ¿qué papel cumple en el pipeline?
Las CONEXIONES: ¿cómo fluye un dato desde que entra (ingesta) hasta que se consulta (warehouse)? Explica el recorrido.
Los PERMISOS: ¿por qué le diste al procesador esos permisos y no otros? ¿qué es el mínimo privilegio y cómo lo aplicaste?
Una decisión de DISEÑO con su alternativa: menciona algo que consideraste y descartaste, y por qué (p. ej. ¿por qué object storage y no una base de datos? ¿por qué Pub/Sub y no leer archivos?).
Escalabilidad: si mañana el pipeline recibiera 100 veces más datos, ¿qué piezas de tu arquitectura aguantarían y cuáles habría que ajustar?

Todo se evalúa por el informe escrito
No hay sustentación oral: la calificación sale del código y del informe que entregan. Por eso el informe debe dejar MUY claro el porqué de cada decisión — es lo que demuestra que entienden arquitectura de datos en la nube. Ambos integrantes deben participar en el diseño y la escritura.

Qué y cómo entregar
El archivo main.tf con la arquitectura modelada y comentada.
Una captura de la salida de 'terraform validate' mostrando 'Success! The configuration is valid.' (obligatorio).
El informe de arquitectura en PDF (máx. 5 páginas) con el diagrama y las justificaciones.
OPCIONAL (suma, no resta): si despliegan de verdad en una cuenta gratuita y lo documentan con capturas, es un plus. No es obligatorio y NO desplegar no baja la nota.
Los nombres de la pareja y la nube elegida en la primera página del informe.

Consejos
• Empiecen por el diagrama en papel: si saben dibujar el flujo, el código sale solo.
• Validen seguido con 'terraform validate' mientras escriben; corrige errores temprano.
• No se obsesionen con desplegar: el valor está en el diseño y la sustentación.
• El principio de mínimo privilegio en los permisos es donde más se nota un buen diseño.
-