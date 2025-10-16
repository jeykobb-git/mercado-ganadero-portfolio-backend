# Mercado Ganadero - API Backend

> API backend robusta y segura para un marketplace de ganado, construida con las mejores prácticas de desarrollo de software y un enfoque en la seguridad y escalabilidad.

[![Java](https://img.shields.io/badge/Java-17-orange?logo=openjdk)](https://openjdk.org/)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3.2.1-brightgreen?logo=spring)](https://spring.io/projects/spring-boot)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue?logo=postgresql)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?logo=docker)](https://www.docker.com/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Características Principales

Este proyecto **no es solo un CRUD básico**, implementa funcionalidades complejas y seguras para una aplicación del mundo real:

### Seguridad Avanzada con Spring Security

- **Autenticación JWT Asimétrica (RS256)**: Uso de pares de claves pública/privada para firmar y verificar tokens, el estándar más seguro para microservicios.
- **Refresh Tokens con Rotación**: Sistema de refresco de tokens que mejora la seguridad y la experiencia de usuario, revocando tokens usados para prevenir ataques de repetición.
- **Control de Acceso Basado en Roles (RBAC)**: Endpoints protegidos con anotaciones `@PreAuthorize` para un control granular (ej. ADMIN, SELLER, BUYER).
- **Validación Robusta de Contraseñas**: Validador de contraseñas que sigue las recomendaciones de OWASP (longitud, complejidad, no comunes, sin secuencias).

### Arquitectura Limpia y Organizada

- **Separación de Responsabilidades**: Lógica de negocio encapsulada en la capa de servicios, separada de los controladores y el acceso a datos.
- **DTOs (Data Transfer Objects)**: Uso de patrones DTO para la comunicación con el cliente, evitando exponer las entidades de la base de datos y personalizando la información enviada.
- **Manejo Global de Excepciones**: Un `RestControllerAdvice` centralizado para manejar errores de forma consistente y enviar respuestas claras al cliente.

### Base de Datos y Persistencia

- **PostgreSQL y JPA/Hibernate**: Uso de una base de datos relacional robusta con mapeo objeto-relacional estándar de la industria.
- **Soporte para JSONB**: Campos de tipo `jsonb` para almacenar datos semi-estructurados como configuraciones de usuario, con un conversor de atributos personalizado.

### Entorno Contenerizado con Docker

- **Dockerfile Multi-etapa**: Optimiza el tamaño de la imagen final separando la fase de construcción de la de ejecución.
- **Docker Compose**: Orquestación sencilla de los servicios de backend y base de datos para un entorno de desarrollo consistente y fácil de levantar.
- **Hot Reload en Desarrollo**: Configuración de volúmenes para reflejar los cambios en el código al instante sin necesidad de reconstruir la imagen.

---

## Stack Tecnológico

| Área | Tecnología |
|------|-----------|
| **Backend** | Java 17, Spring Boot 3.2.1 |
| **Base de Datos** | PostgreSQL 16, Spring Data JPA, Hibernate |
| **Seguridad** | Spring Security, JWT (jjwt-api), BCrypt |
| **API** | Spring Web (REST Controllers), Spring Validation |
| **Contenerización** | Docker, Docker Compose |
| **Build Tool** | Maven 3.9+ |
| **Utilidades** | Lombok, Jackson (JSON), Slf4j (Logging) |
| **Documentación API** | SpringDoc (OpenAPI / Swagger) |

---

## Cómo Empezar

### Requisitos Previos

- Docker Desktop instalado y corriendo
- Opcional (para desarrollo local sin Docker): JDK 17, Maven 3.9+

### 1️ Clonar el Repositorio

```bash
git clone [URL-DE-TU-REPOSITORIO]
cd mercado-ganadero-portfolio-backend
```

### 2️ Configurar Variables de Entorno

El proyecto incluye un archivo `.env.dev` con valores predeterminados para un inicio rápido. No es necesario modificarlo para levantar el entorno.

### 3️ Iniciar con Docker Compose

Este es el método **recomendado**. Levanta tanto la API como la base de datos PostgreSQL en contenedores aislados.

```bash
# Construir y levantar los contenedores en segundo plano
docker-compose up -d --build

# Para ver los logs de la aplicación en tiempo real
docker-compose logs -f backend
```

La aplicación estará disponible en **http://localhost:8080**

### 4️ Verificar el Estado

- **API Health Check**: Visita [http://localhost:8080/actuator/health](http://localhost:8080/actuator/health) para verificar que la API está UP.
- **Base de Datos**: Se puede acceder en `localhost:5432` con las credenciales de `.env.dev`

---

## Documentación de la API

Una vez que la aplicación está corriendo, la documentación interactiva de la API (Swagger UI) está disponible en:

** [http://localhost:8080/swagger-ui.html](http://localhost:8080/swagger-ui.html)**

Desde allí puedes explorar todos los endpoints, ver los modelos de datos y probar la API directamente.

---

## Comandos Útiles de Docker

```bash
# Detener y eliminar los contenedores
docker-compose down

# Detener contenedores y eliminar volúmenes (¡borra los datos de la BD!)
docker-compose down -v

# Reconstruir la imagen del backend si haces cambios en el Dockerfile o pom.xml
docker-compose build backend

# Reiniciar solo el servicio del backend
docker-compose restart backend

# Conectarse a la base de datos PostgreSQL dentro del contenedor
docker exec -it postgres_db_dev psql -U devuser -d mercado_ganadero_db
```

---

## Licencia

Este proyecto es de código abierto bajo la [Licencia MIT](LICENSE). Eres libre de usarlo para fines educativos y para tu propio portafolio.

---

## Autor

**Jacob Baños Tapia**

<div align="center">
⭐ Si este proyecto te resulta útil, considera darle una estrella en GitHub
