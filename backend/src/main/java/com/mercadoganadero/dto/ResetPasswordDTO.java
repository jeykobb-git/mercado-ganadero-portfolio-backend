package com.mercadoganadero.dto;

import jakarta.validation.constraints.*;
import lombok.Data;

/**
 * DTO para reseteo de contraseña con token
 */
@Data
public class ResetPasswordDTO {

    @NotBlank(message = "El token es requerido")
    private String token;

    @NotBlank(message = "La nueva contraseña es requerida")
    @Size(min = 8, message = "La contraseña debe tener al menos 8 caracteres")
    @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).*$",
            message = "La contraseña debe contener mayúsculas, minúsculas y números")
    private String newPassword;

    @NotBlank(message = "Debe confirmar la nueva contraseña")
    private String confirmPassword;
}