package com.mercadoganadero.exception;

import lombok.Getter;

import java.util.List;

/**
 * Excepción lanzada cuando una contraseña no cumple los requisitos de seguridad
 */
@Getter
public class WeakPasswordException extends RuntimeException {

    private final List<String> validationErrors;

    public WeakPasswordException(List<String> validationErrors) {
        super("La contraseña no cumple con los requisitos de seguridad");
        this.validationErrors = validationErrors;
    }

    public WeakPasswordException(String message) {
        super(message);
        this.validationErrors = List.of(message);
    }
}