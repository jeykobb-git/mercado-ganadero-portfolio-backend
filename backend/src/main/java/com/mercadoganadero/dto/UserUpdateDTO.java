package com.mercadoganadero.dto;

import jakarta.validation.constraints.*;
import lombok.Data;
import java.util.Map;

/**
 * DTO para actualizar usuario
 * Solo incluye campos que pueden ser actualizados
 * No incluye password ni email (tienen endpoints separados)
 */
@Data
public class UserUpdateDTO {

    @Size(min = 2, max = 100, message = "El nombre debe tener entre 2 y 100 caracteres")
    private String name;

    @Size(min = 2, max = 200, message = "El apellido debe tener entre 2 y 200 caracteres")
    private String lastName;

    @Pattern(regexp = "^[+]?[0-9]{10,15}$", message = "El teléfono debe ser válido")
    private String phoneNumber;

    private Integer addressId;

    private Integer subscriptionPlanId;

    private Map<String, Object> settings;

    private Map<String, Object> notificationPreferences;

    private Boolean tfaEnabled;
}