package com.mercadoganadero.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import lombok.Data;

/**
 * DTO para la solicitud de inicio de sesión (Login)
 */
@Data
public class LoginDTO {

    @NotBlank(message = "El email es requerido")
    @Email(message = "El email debe ser válido") // Reafirmamos la validación del formato de email
    private String email;

    @NotBlank(message = "La contraseña es requerida")
    // No validamos la complejidad aquí, solo que no esté vacía,
    // ya que el login solo verifica el hash almacenado.
    private String password;
}