package com.mercadoganadero.dto;

import jakarta.validation.constraints.*;
import lombok.Data;
import java.util.Map;

/**
 * DTO para crear usuario nuevo
 * Incluye validaciones de Bean Validation
 */
@Data
public class UserCreateDTO {

    @NotBlank(message = "El nombre es requerido")
    @Size(min = 2, max = 100, message = "El nombre debe tener entre 2 y 100 caracteres")
    private String name;

    @NotBlank(message = "El apellido es requerido")
    @Size(min = 2, max = 200, message = "El apellido debe tener entre 2 y 200 caracteres")
    private String lastName;

    @NotBlank(message = "El email es requerido")
    @Email(message = "El email debe ser válido")
    @Size(max = 250)
    private String email;

    @NotBlank(message = "El teléfono es requerido")
    @Pattern(regexp = "^[+]?[0-9]{10,15}$", message = "El teléfono debe ser válido")
    private String phoneNumber;

    @NotBlank(message = "La contraseña es requerida")
    @Size(min = 8, message = "La contraseña debe tener al menos 8 caracteres")
    @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).*$",
            message = "La contraseña debe contener mayúsculas, minúsculas y números")
    private String password;

    @NotNull(message = "El tipo de usuario es requerido")
    private Integer userTypeId;

    @NotNull(message = "La dirección es requerida")
    private Integer addressId;

    @NotNull(message = "El plan de suscripción es requerido")
    private Integer subscriptionPlanId;

    private Map<String, Object> settings;

    private Map<String, Object> notificationPreferences;
}