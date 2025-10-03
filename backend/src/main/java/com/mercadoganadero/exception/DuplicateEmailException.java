package com.mercadoganadero.exception;

/**
 * Excepción cuando se intenta registrar un email duplicado
 */
public class DuplicateEmailException extends RuntimeException {
    private String email;

    public DuplicateEmailException(String email) {
        super(String.format("El email %s ya está registrado", email));
        this.email = email;
    }

    public String getEmail() {
        return email;
    }
}