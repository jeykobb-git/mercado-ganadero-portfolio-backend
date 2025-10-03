package com.mercadoganadero.exception;

/**
 * Excepción para contraseña incorrecta
 */
public class InvalidPasswordException extends RuntimeException {
    public InvalidPasswordException() {
        super("La contraseña actual es incorrecta");
    }

    public InvalidPasswordException(String message) {
        super(message);
    }
}