package com.mercadoganadero.dto;

import com.mercadoganadero.entity.User;
import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;
import java.util.Map;

/**
 * DTO de respuesta para Usuario
 *
 *
 * @JsonInclude controla serialización de valores null
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
public class UserResponseDTO {

    private Integer userId;
    private String name;
    private String lastName;
    private String email;
    private String phoneNumber;
    private OffsetDateTime createdAt;
    private OffsetDateTime updatedAt;

    // Solo mostrar si el usuario está viendo su propio perfil
    private OffsetDateTime lastLogin;

    private Boolean isActive;
    private Boolean emailVerified;
    private Boolean tfaEnabled;
    private Map<String, Object> settings;
    private Map<String, Object> notificationPreferences;

    // Referencias a otras entidades
    private Integer userTypeId;
    private String userTypeName;

    private Integer addressId;
    private Integer subscriptionPlanId;
    private String subscriptionPlanName;

    // Información adicional útil
    private Boolean isDeleted; // Si deletedAt != null

    /**
     * Convierte entidad User a DTO
     * Filtra información sensible
     */
    public static UserResponseDTO fromEntity(User user) {
        return UserResponseDTO.builder()
                .userId(user.getUserId())
                .name(user.getName())
                .lastName(user.getLastName())
                .email(user.getEmail())
                .phoneNumber(user.getPhoneNumber())
                .createdAt(user.getCreatedAt())
                .updatedAt(user.getUpdatedAt())
                .lastLogin(user.getLastLogin())
                .isActive(user.getIsActive())
                .emailVerified(user.getEmailVerified())
                .tfaEnabled(user.getTfaEnabled())
                .settings(filterSensitiveSettings(user.getSettings()))
                .notificationPreferences(user.getNotificationPreferences())
                .userTypeId(user.getUserTypeId())
                .addressId(user.getAddressId())
                .subscriptionPlanId(user.getSubscriptionPlanId())
                .isDeleted(user.getDeletedAt() != null)
                .build();
    }

    /**
     * Filtra configuraciones sensibles
     * Por ejemplo, tokens de API, claves, etc.
     */
    private static Map<String, Object> filterSensitiveSettings(Map<String, Object> settings) {
        if (settings == null) return null;

        // Aquí se filtran las keys sensibles
        settings.remove("apiKey");
        settings.remove("secretToken");
        // etc...

        return settings;
    }

    /**
     * Versión mínima para listados públicos
     * Solo información básica
     */
    public static UserResponseDTO minimal(User user) {
        return UserResponseDTO.builder()
                .userId(user.getUserId())
                .name(user.getName())
                .lastName(user.getLastName())
                .build();
    }
}