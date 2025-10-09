package com.mercadoganadero.repository;

import com.mercadoganadero.entity.RefreshToken;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface RefreshTokenRepository extends JpaRepository<RefreshToken, Long> {

    /**
     * Busca un refresh token por su valor
     */
    Optional<RefreshToken> findByToken(String token);

    /**
     * Busca todos los tokens activos de un usuario
     */
    @Query("SELECT rt FROM RefreshToken rt WHERE rt.userId = :userId AND rt.revokedAt IS NULL")
    List<RefreshToken> findActiveTokensByUserId(@Param("userId") Integer userId);

    /**
     * Revoca todos los tokens activos de un usuario (para logout global)
     */
    @Modifying
    @Query("UPDATE RefreshToken rt SET rt.revokedAt = :revokedAt WHERE rt.userId = :userId AND rt.revokedAt IS NULL")
    void revokeAllUserTokens(@Param("userId") Integer userId, @Param("revokedAt") OffsetDateTime revokedAt);

    /**
     * Elimina tokens expirados (limpieza automática)
     */
    @Modifying
    @Query("DELETE FROM RefreshToken rt WHERE rt.expiresAt < :now")
    void deleteExpiredTokens(@Param("now") OffsetDateTime now);

    /**
     * Cuenta tokens activos de un usuario
     */
    @Query("SELECT COUNT(rt) FROM RefreshToken rt WHERE rt.userId = :userId AND rt.revokedAt IS NULL AND rt.expiresAt > :now")
    long countActiveTokensByUserId(@Param("userId") Integer userId, @Param("now") OffsetDateTime now);
}