package com.mercadoganadero.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * DTO para la respuesta de autenticación (Login y Refresh Token).
 * Contiene los tokens, el tiempo de expiración y los datos del usuario.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AuthResponseDTO {

    private String accessToken;
    private String refreshToken;
    private long expiresIn;

    @Builder.Default
    private String tokenType = "Bearer";
    private UserResponseDTO user;
}