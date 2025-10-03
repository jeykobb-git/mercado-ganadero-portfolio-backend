package com.mercadoganadero.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * DTO para la respuesta de autenticación (Login)
 * Contiene el token JWT y el objeto de usuario.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AuthResponseDTO {

    private String token;
    private final String tokenType = "Bearer"; // Tipo de token estándar
    private UserResponseDTO user; // Objeto de usuario (sin password, con datos relevantes)
}