package com.mercadoganadero.security.jwt;

import com.mercadoganadero.enums.UserRole;
import io.jsonwebtoken.*;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.SignatureException;
import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.InputStream;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Date;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Proveedor JWT con RS256 (asimétrico) para máxima seguridad
 * - Solo el servidor de autenticación tiene la clave privada
 * - Los microservicios solo necesitan la clave pública
 * - Rechaza explícitamente el algoritmo "none"
 */
@Component
@Slf4j
public class JwtTokenProvider {

    @Value("classpath:keys/private_key_pkcs8.pem")
    private Resource privateKeyResource;

    @Value("classpath:keys/public_key.pem")
    private Resource publicKeyResource;

    @Value("${app.jwt.expiration-ms}")
    private long jwtExpirationInMs;

    @Value("${app.jwt.issuer:mercado-ganadero}")
    private String issuer;

    private PrivateKey privateKey;
    private PublicKey publicKey;

    /**
     * Carga las claves RSA al iniciar el componente
     */
    @PostConstruct
    public void init() throws Exception {
        log.info("Iniciando carga de claves RSA...");
        this.privateKey = loadPrivateKey();
        log.info("Clave privada RSA cargada correctamente");
        this.publicKey = loadPublicKey();
        log.info("Clave pública RSA cargada correctamente");
        log.info("JwtTokenProvider configurado con RS256");
    }

    /**
     * Genera un Access Token JWT con RS256
     * @param username Email del usuario
     * @param userId ID del usuario
     * @param roles Lista de roles del usuario
     * @return JWT firmado con la clave privada
     */
    public String generateAccessToken(String username, Integer userId, List<UserRole> roles) {
        Date now = new Date();
        Date expiryDate = new Date(now.getTime() + jwtExpirationInMs);

        List<String> roleStrings = roles.stream()
                .map(UserRole::getAuthority)
                .collect(Collectors.toList());

        return Jwts.builder()
                .subject(username)
                .claim("userId", userId)
                .claim("roles", roleStrings)
                .claim("type", "access")
                .issuer(issuer)
                .issuedAt(now)
                .expiration(expiryDate)
                .id(UUID.randomUUID().toString()) // JTI para rastreo
                .signWith(privateKey, Jwts.SIG.RS256) // RS256 asimétrico
                .compact();
    }

    /**
     * Genera un Refresh Token (más largo, sin roles sensibles)
     * @param username Email del usuario
     * @param userId ID del usuario
     * @return JWT firmado para refresh
     */
    public String generateRefreshToken(String username, Integer userId) {
        Date now = new Date();
        Date expiryDate = new Date(now.getTime() + (jwtExpirationInMs * 7)); // 7 días

        return Jwts.builder()
                .subject(username)
                .claim("userId", userId)
                .claim("type", "refresh")
                .issuer(issuer)
                .issuedAt(now)
                .expiration(expiryDate)
                .id(UUID.randomUUID().toString())
                .signWith(privateKey, Jwts.SIG.RS256)
                .compact();
    }

    /**
     * Extrae el username del token
     */
    public String getUsernameFromJWT(String token) {
        Claims claims = parseToken(token);
        return claims.getSubject();
    }

    /**
     * Extrae el userId del token
     */
    public Integer getUserIdFromJWT(String token) {
        Claims claims = parseToken(token);
        return claims.get("userId", Integer.class);
    }

    /**
     * Extrae los roles del token
     */
    @SuppressWarnings("unchecked")
    public List<String> getRolesFromJWT(String token) {
        Claims claims = parseToken(token);
        return claims.get("roles", List.class);
    }

    /**
     * Valida el token (firma, expiración, emisor)
     */
    public boolean validateToken(String token) {
        try {
            Jws<Claims> claims = Jwts.parser()
                    .verifyWith(publicKey) //Verifica con clave pública
                    .requireIssuer(issuer)  //Valida el emisor
                    .build()
                    .parseSignedClaims(token);

            // Rechazar explícitamente si el algoritmo es "none"
            String algorithm = claims.getHeader().getAlgorithm();
            if ("none".equalsIgnoreCase(algorithm)) {
                log.error("Intento de usar algoritmo 'none' rechazado");
                return false;
            }

            return true;
        } catch (SignatureException ex) {
            log.error("Firma JWT inválida: {}", ex.getMessage());
        } catch (MalformedJwtException ex) {
            log.error("Token JWT malformado: {}", ex.getMessage());
        } catch (ExpiredJwtException ex) {
            log.warn("Token JWT expirado: {}", ex.getMessage());
        } catch (UnsupportedJwtException ex) {
            log.error("Token JWT no soportado: {}", ex.getMessage());
        } catch (IllegalArgumentException ex) {
            log.error("JWT claims string vacío: {}", ex.getMessage());
        }
        return false;
    }

    /**
     * Parsea el token y extrae los claims
     */
    private Claims parseToken(String token) {
        return Jwts.parser()
                .verifyWith(publicKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }

    /**
     * Carga la clave privada desde el archivo PEM
     */
    private PrivateKey loadPrivateKey() throws Exception {
        try (InputStream inputStream = privateKeyResource.getInputStream()) {
            String key = new String(inputStream.readAllBytes())
                    .replace("-----BEGIN PRIVATE KEY-----", "")
                    .replace("-----END PRIVATE KEY-----", "")
                    .replaceAll("\\s", "");

            byte[] keyBytes = Decoders.BASE64.decode(key);
            PKCS8EncodedKeySpec spec = new PKCS8EncodedKeySpec(keyBytes);
            KeyFactory kf = KeyFactory.getInstance("RSA");
            return kf.generatePrivate(spec);
        } catch (IOException e) {
            log.error("Error al cargar clave privada: {}", e.getMessage());
            throw new RuntimeException("No se pudo cargar la clave privada RSA", e);
        }
    }

    /**
     * Carga la clave pública desde el archivo PEM
     */
    private PublicKey loadPublicKey() throws Exception {
        try (InputStream inputStream = publicKeyResource.getInputStream()) {
            String key = new String(inputStream.readAllBytes())
                    .replace("-----BEGIN PUBLIC KEY-----", "")
                    .replace("-----END PUBLIC KEY-----", "")
                    .replaceAll("\\s", "");

            byte[] keyBytes = Decoders.BASE64.decode(key);
            X509EncodedKeySpec spec = new X509EncodedKeySpec(keyBytes);
            KeyFactory kf = KeyFactory.getInstance("RSA");
            return kf.generatePublic(spec);
        } catch (IOException e) {
            log.error("❌ Error al cargar clave pública: {}", e.getMessage());
            throw new RuntimeException("No se pudo cargar la clave pública RSA", e);
        }
    }
}