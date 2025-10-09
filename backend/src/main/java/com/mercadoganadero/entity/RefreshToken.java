package com.mercadoganadero.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;

/**
 * Entidad para gestionar tokens de refresco
 * Permite revocar sesiones y detectar tokens robados
 */
@Entity
@Table(name = "refresh_tokens", indexes = {
        @Index(name = "idx_token", columnList = "token"),
        @Index(name = "idx_user_id", columnList = "user_id")
})
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class RefreshToken {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "token", nullable = false, unique = true, length = 500)
    private String token;

    @Column(name = "user_id", nullable = false)
    private Integer userId;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @Column(name = "revoked_at")
    private OffsetDateTime revokedAt;

    @Column(name = "replaced_by_token")
    private String replacedByToken;

    // IP y User Agent para detección de robo
    @Column(name = "ip_address", length = 45)
    private String ipAddress;

    @Column(name = "user_agent", length = 500)
    private String userAgent;

    @PrePersist
    protected void onCreate() {
        createdAt = OffsetDateTime.now();
    }

    /**
     * Verifica si el token ha expirado
     */
    public boolean isExpired() {
        return OffsetDateTime.now().isAfter(expiresAt);
    }

    /**
     * Verifica si el token fue revocado
     */
    public boolean isRevoked() {
        return revokedAt != null;
    }

    /**
     * Verifica si el token es válido (no expirado ni revocado)
     */
    public boolean isValid() {
        return !isExpired() && !isRevoked();
    }
}