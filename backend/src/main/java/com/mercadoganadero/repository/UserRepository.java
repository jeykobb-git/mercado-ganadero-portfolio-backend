package com.mercadoganadero.repository;

import com.mercadoganadero.entity.User;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UserRepository extends JpaRepository<User, Integer> {

    // ==============================================================================
    // BÚSQUEDA BÁSICA Y VALIDACIÓN (existentes y necesarios)
    // ==============================================================================

    /** Buscar usuario por email (incluye inactivos o con soft delete) */
    Optional<User> findByEmail(String email);

    /** Buscar usuario por email (solo activos y no eliminados), usado en CustomUserDetailsService */
    @Query("SELECT u FROM User u WHERE u.email = :email AND u.isActive = true AND u.deletedAt IS NULL")
    Optional<User> findActiveByEmail(String email);

    /** Verificar si existe un email */
    boolean existsByEmail(String email);

    /** Verificar si existe un email (excluyendo un usuario específico - útil para updates) */
    @Query("SELECT CASE WHEN COUNT(u) > 0 THEN true ELSE false END FROM User u WHERE u.email = :email AND u.userId != :excludeUserId")
    boolean existsByEmailAndUserIdNot(String email, Integer excludeUserId);

    // ==============================================================================
    // MÉTODOS REQUERIDOS POR UserServiceImpl (Paginación y Filtros)
    // ==============================================================================

    /** 1. Paginación de usuarios activos (para getAllUsers) */
    Page<User> findByDeletedAtIsNull(Pageable pageable);

    /** 2. Búsqueda de usuarios (para searchUsers) */
    // Realiza una búsqueda case-insensitive en nombre, apellido y email, excluyendo eliminados.
    @Query("SELECT u FROM User u WHERE u.deletedAt IS NULL AND (LOWER(u.name) LIKE LOWER(CONCAT('%', :searchTerm, '%')) OR LOWER(u.lastName) LIKE LOWER(CONCAT('%', :searchTerm, '%')) OR LOWER(u.email) LIKE LOWER(CONCAT('%', :searchTerm, '%')))")
    Page<User> searchUsers(String searchTerm, Pageable pageable);

    /** 3. Listado por tipo (para getUsersByType), excluyendo eliminados */
    List<User> findByUserTypeIdAndDeletedAtIsNull(Integer userTypeId);

    /** 4. Conteo de usuarios activos (para countActiveUsers) */
    long countByDeletedAtIsNull();

    /** 5. Búsqueda de usuario que actualizó su último login (para updateLastLogin) */
    // Ya cubierto por JpaRepository.findById(Integer) y el Optional.ifPresent

    // ==============================================================================
    // MÉTODOS REQUERIDOS PARA SEGURIDAD (Tokens)
    // ==============================================================================

    /** 6. Búsqueda por token de reseteo (para resetPassword) */
    Optional<User> findByPasswordResetToken(String token);

    /** 7. Búsqueda por token de verificación de email (para verifyEmail) */
    Optional<User> findByEmailVerificationToken(String token);

    // NOTA: Para que los métodos 6 y 7 funcionen, tu entidad User.java
    // debe tener los campos 'passwordResetToken' y 'emailVerificationToken'.
}