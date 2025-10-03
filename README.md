# Mercado Ganadero - Backend API

Sistema backend para marketplace de ganado bovino con control sanitario y trazabilidad.

## Tecnologías

- **Java 17**
- **Spring Boot 3.2.1**
- **PostgreSQL 16**
- **Docker & Docker Compose**
- **Maven 3.9+**

## Requisitos Previos

- Docker Desktop instalado
- Java 17 JDK (opcional, para desarrollo local)
- Maven 3.9+ (opcional, para desarrollo local)
- IntelliJ IDEA Community (recomendado)

## Estructura del Proyecto

```
mercado-ganadero/
├── backend/                    # Código fuente backend
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/
│   │   │   └── resources/
│   │   └── test/
│   ├── Dockerfile
│   └── pom.xml
├── dev-data/                   # Datos PostgreSQL (gitignored)
├── uploads/                    # Archivos subidos (gitignored)
├── logs/                       # Logs de aplicación (gitignored)
├── docker-compose.yml
├── .env.dev
└── README.md
```

## Configuración Inicial

### 1. Clonar el repositorio

```bash
git clone [tu-repo]
cd mercado-ganadero
```

### 2. Configurar variables de entorno

El archivo `.env.dev` ya está configurado con:
- Credenciales de PostgreSQL
- Configuración de JWT
- Puertos y nombres de contenedores

**IMPORTANTE**: No subas `.env.dev` a Git (ya está en .gitignore)

### 3. Iniciar servicios con Docker

```bash
# Levantar base de datos y backend
docker-compose up -d

# Ver logs
docker-compose logs -f

# Ver logs solo del backend
docker-compose logs -f backend
```

### 4. Verificar que funciona

- Backend: http://localhost:8080
- PostgreSQL: localhost:5432
- Health check: http://localhost:8080/actuator/health

## Desarrollo Local (sin Docker)

Si prefieres correr el backend fuera de Docker:

```bash
cd backend

# Asegúrate de que PostgreSQL está corriendo
docker-compose up -d postgres

# Ejecutar con Maven
mvn spring-boot:run

# O si usas IntelliJ, simplemente corre MercadoGanaderoApplication
```

## Comandos Útiles

```bash
# Reconstruir imagen de backend
docker-compose build backend

# Reiniciar solo el backend
docker-compose restart backend

# Ver base de datos
docker exec -it postgres_db_dev psql -U devuser -d mercado_ganadero_db

# Detener todo
docker-compose down

# Detener y eliminar volúmenes (¡cuidado con los datos!)
docker-compose down -v
```

## Próximos Pasos

1. [ ] Implementar entidades JPA
2. [ ] Crear repositorios
3. [ ] Implementar servicios de negocio
4. [ ] Crear controllers REST
5. [ ] Agregar seguridad JWT
6. [ ] Implementar tests

## API Documentation

Una vez levantado, la documentación Swagger estará disponible en:
- http://localhost:8080/swagger-ui.html

## Troubleshooting

### El backend no puede conectarse a PostgreSQL

```bash
# Verifica que PostgreSQL está corriendo
docker-compose ps

# Verifica logs de PostgreSQL
docker-compose logs postgres
```

### Puerto 8080 ya está en uso

Edita `.env.dev` y cambia `SERVER_PORT` a otro puerto.

### Hot reload no funciona

Asegúrate de que los volúmenes están montados correctamente en `docker-compose.yml`

## Contribuir

Este es un proyecto de portafolio personal. Si encuentras bugs o tienes sugerencias, abre un issue.

## Licencia

MIT License - Libre para uso educativo y portafolio