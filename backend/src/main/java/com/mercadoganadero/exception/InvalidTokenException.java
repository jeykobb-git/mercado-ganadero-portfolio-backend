package com.mercadoganadero.exception;

/**
 * Excepción para tokens inválidos o expirados
 */
public class InvalidTokenException extends RuntimeException {
    public InvalidTokenException() {
        super("Token inválido o expirado");
    }

    public InvalidTokenException(String message) {
        super(message);
    }
}