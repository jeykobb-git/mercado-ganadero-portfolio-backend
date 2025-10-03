package com.mercadoganadero.security.jwt;

import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;

/**
 * Utilidad para generar, validar y leer JSON Web Tokens (JWT).
 */
@Component
public class JwtTokenProvider {

    // Clave secreta para firmar los tokens
    @Value("${app.jwt.secret}")
    private String jwtSecret;

    // Tiempo de expiración del token (24 horas en milisegundos)
    @Value("${app.jwt.expiration-ms}")
    private long jwtExpirationInMs;

    private SecretKey getSigningKey() {
        return Keys.hmacShaKeyFor(jwtSecret.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * Genera un token JWT para un usuario.
     */
    public String generateToken(String username) {
        Date now = new Date();
        Date expiryDate = new Date(now.getTime() + jwtExpirationInMs);

        return Jwts.builder()
                .subject(username) // El "subject" (asunto) es la identidad (email)
                .issuedAt(new Date())
                .expiration(expiryDate)
                .signWith(getSigningKey(), Jwts.SIG.HS256) // Firma el token con la clave
                .compact();
    }

    /**
     * Extrae el username (email) del token.
     */
    public String getUsernameFromJWT(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(getSigningKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();

        return claims.getSubject();
    }

    /**
     * Valida la integridad y expiración del token.
     */
    public boolean validateToken(String authToken) {
        try {
            // Si la validación falla (firma inválida o expiración), lanza una excepción
            Jwts.parser().verifyWith(getSigningKey()).build().parseSignedClaims(authToken);
            return true;
        } catch (MalformedJwtException ex) {
            // Token JWT inválido
        } catch (ExpiredJwtException ex) {
            // Token JWT expirado
        } catch (UnsupportedJwtException ex) {
            // Token JWT no soportado
        } catch (IllegalArgumentException ex) {
            // Cadena JWT vacía
        }
        return false;
    }
}