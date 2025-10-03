package com.mercadoganadero.dto;

import jakarta.validation.constraints.*;
import lombok.Data;

/**
 * DTO para cambio de contraseña
 * Requiere contraseña actual por seguridad
 */
@Data
public class ChangePasswordDTO {

    @NotBlank(message = "La contraseña actual es requerida")
    private String oldPassword;

    @NotBlank(message = "La nueva contraseña es requerida")
    @Size(min = 8, message = "La contraseña debe tener al menos 8 caracteres")
    @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).*$",
            message = "La contraseña debe contener mayúsculas, minúsculas y números")
    private String newPassword;

    @NotBlank(message = "Debe confirmar la nueva contraseña")
    private String confirmPassword;

    // Validación personalizada en el service
    public boolean passwordsMatch() {
        return newPassword != null && newPassword.equals(confirmPassword);
    }
}