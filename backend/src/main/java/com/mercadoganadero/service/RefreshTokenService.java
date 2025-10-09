package com.mercadoganadero.service;

import com.mercadoganadero.entity.RefreshToken;
import com.mercadoganadero.exception.InvalidTokenException;
import com.mercadoganadero.repository.RefreshTokenRepository;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * Servicio para gestionar Refresh Tokens
 * Permite renovar access tokens sin pedir credenciales nuevamente
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class RefreshTokenService {

    private final RefreshTokenRepository refreshTokenRepository;

    @Value("${app.jwt.refresh-expiration-days:7}")
    private int refreshExpirationDays;

    @Value("${app.jwt.max-active-sessions:5}")
    private int maxActiveSessions;

    /**
     * Crea un nuevo refresh token
     */
    @Transactional
    public RefreshToken createRefreshToken(Integer userId, HttpServletRequest request) {
        // Verificar límite de sesiones activas
        long activeSessions = refreshTokenRepository.countActiveTokensByUserId(userId, OffsetDateTime.now());
        if (activeSessions >= maxActiveSessions) {
            log.warn("Usuario {} alcanzó el límite de sesiones activas ({}). Revocando la más antigua.", userId, maxActiveSessions);
            revokeOldestToken(userId);
        }

        String token = UUID.randomUUID().toString();
        OffsetDateTime expiresAt = OffsetDateTime.now().plusDays(refreshExpirationDays);

        RefreshToken refreshToken = RefreshToken.builder()
                .token(token)
                .userId(userId)
                .expiresAt(expiresAt)
                .ipAddress(getClientIP(request))
                .userAgent(request.getHeader("User-Agent"))
                .build();

        return refreshTokenRepository.save(refreshToken);
    }

    /**
     * Valida y retorna un refresh token
     */
    @Transactional(readOnly = true)
    public RefreshToken validateRefreshToken(String token) {
        RefreshToken refreshToken = refreshTokenRepository.findByToken(token)
                .orElseThrow(() -> new InvalidTokenException("Refresh token inválido"));

        if (refreshToken.isRevoked()) {
            log.warn("Intento de usar refresh token revocado: {}", token);
            throw new InvalidTokenException("Este token ha sido revocado");
        }

        if (refreshToken.isExpired()) {
            log.warn("Refresh token expirado: {}", token);
            throw new InvalidTokenException("El refresh token ha expirado");
        }

        // Detectar reuso de token (posible robo)
        if (refreshToken.getReplacedByToken() != null) {
            log.error("ALERTA: Token reemplazado siendo reutilizado. Posible robo. User ID: {}", refreshToken.getUserId());
            revokeAllUserTokens(refreshToken.getUserId());
            throw new InvalidTokenException("Token de seguridad comprometido. Se han revocado todas las sesiones.");
        }

        return refreshToken;
    }

    /**
     * Revoca un token específico y lo marca como reemplazado
     */
    @Transactional
    public void revokeToken(String oldToken, String newToken) {
        refreshTokenRepository.findByToken(oldToken).ifPresent(token -> {
            token.setRevokedAt(OffsetDateTime.now());
            token.setReplacedByToken(newToken);
            refreshTokenRepository.save(token);
        });
    }

    /**
     * Revoca todos los tokens de un usuario (logout global)
     */
    @Transactional
    public void revokeAllUserTokens(Integer userId) {
        refreshTokenRepository.revokeAllUserTokens(userId, OffsetDateTime.now());
        log.info("Todas las sesiones del usuario {} han sido revocadas", userId);
    }

    /**
     * Revoca el token más antiguo de un usuario
     */
    @Transactional
    public void revokeOldestToken(Integer userId) {
        List<RefreshToken> activeTokens = refreshTokenRepository.findActiveTokensByUserId(userId);
        if (!activeTokens.isEmpty()) {
            RefreshToken oldest = activeTokens.stream()
                    .min((t1, t2) -> t1.getCreatedAt().compareTo(t2.getCreatedAt()))
                    .orElse(activeTokens.get(0));

            oldest.setRevokedAt(OffsetDateTime.now());
            refreshTokenRepository.save(oldest);
            log.info("Token más antiguo revocado para usuario {}", userId);
        }
    }

    /**
     * Tarea programada: Limpia tokens expirados cada día a las 3 AM
     */
    @Scheduled(cron = "0 0 3 * * ?")
    @Transactional
    public void cleanupExpiredTokens() {
        refreshTokenRepository.deleteExpiredTokens(OffsetDateTime.now());
        log.info("Limpieza de refresh tokens expirados completada");
    }

    /**
     * Obtiene la IP real del cliente (considerando proxies)
     */
    private String getClientIP(HttpServletRequest request) {
        String xfHeader = request.getHeader("X-Forwarded-For");
        if (xfHeader == null) {
            return request.getRemoteAddr();
        }
        return xfHeader.split(",")[0].trim();
    }
}