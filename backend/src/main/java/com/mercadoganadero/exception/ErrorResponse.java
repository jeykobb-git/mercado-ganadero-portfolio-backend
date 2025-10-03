package com.mercadoganadero.exception;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import java.time.OffsetDateTime;
import java.util.Map;

/**
 * Estructura estándar para la respuesta de errores de la API.
 */
@Data // Genera getters, setters, toString, equals, hashCode
@Builder // Genera el constructor builder (necesario para el GlobalExceptionHandler)
@NoArgsConstructor
@AllArgsConstructor
public class ErrorResponse {

    private OffsetDateTime timestamp;
    private Integer status;
    private String error;
    private String message;
    private String path;

    // Campo opcional para errores que necesitan más detalle (como los de validación)
    private Map<String, ?> details;
}