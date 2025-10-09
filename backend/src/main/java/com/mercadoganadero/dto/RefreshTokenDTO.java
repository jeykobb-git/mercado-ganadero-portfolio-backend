package com.mercadoganadero.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

/**
 * DTO para solicitudes de refresh token
 */
@Data
public class RefreshTokenDTO {

    @NotBlank(message = "El refresh token es requerido")
    private String refreshToken;
}