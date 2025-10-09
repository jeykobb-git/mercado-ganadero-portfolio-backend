package com.mercadoganadero.validation;

import com.mercadoganadero.exception.WeakPasswordException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Validador robusto de contraseñas
 * Aplica las mejores prácticas de seguridad OWASP
 */
@Component
@Slf4j
public class PasswordValidator {

    private static final int MIN_LENGTH = 8;
    private static final int MAX_LENGTH = 128;

    // Patrones de validación
    private static final Pattern LOWERCASE = Pattern.compile("[a-z]");
    private static final Pattern UPPERCASE = Pattern.compile("[A-Z]");
    private static final Pattern DIGIT = Pattern.compile("[0-9]");
    private static final Pattern SPECIAL_CHAR = Pattern.compile("[!@#$%^&*()_+\\-=\\[\\]{};':\"\\\\|,.<>/?]");

    // Lista de contraseñas comunes prohibidas
    private static final List<String> COMMON_PASSWORDS = List.of(
            "password", "12345678", "qwerty", "abc123", "password1",
            "admin", "letmein", "welcome", "monkey", "1234567890",
            "Password123", "Admin123", "Qwerty123"
    );

    /**
     * Valida una contraseña según criterios de seguridad
     * @param password La contraseña a validar
     * @throws WeakPasswordException si no cumple los requisitos
     */
    public void validatePassword(String password) {
        List<String> errors = new ArrayList<>();

        // 1. Validar longitud
        if (password == null || password.length() < MIN_LENGTH) {
            errors.add("La contraseña debe tener al menos " + MIN_LENGTH + " caracteres");
        }

        if (password != null && password.length() > MAX_LENGTH) {
            errors.add("La contraseña no puede exceder " + MAX_LENGTH + " caracteres");
        }

        if (password == null) {
            throw new WeakPasswordException(errors);
        }

        // 2. Validar complejidad
        if (!LOWERCASE.matcher(password).find()) {
            errors.add("Debe contener al menos una letra minúscula");
        }

        if (!UPPERCASE.matcher(password).find()) {
            errors.add("Debe contener al menos una letra mayúscula");
        }

        if (!DIGIT.matcher(password).find()) {
            errors.add("Debe contener al menos un número");
        }

        if (!SPECIAL_CHAR.matcher(password).find()) {
            errors.add("Debe contener al menos un carácter especial (!@#$%^&*()_+-=[]{}etc)");
        }

        // 3. Verificar contraseñas comunes
        String lowerPassword = password.toLowerCase();
        for (String common : COMMON_PASSWORDS) {
            if (lowerPassword.contains(common.toLowerCase())) {
                errors.add("La contraseña es demasiado común y fácil de adivinar");
                break;
            }
        }

        // 4. Detectar patrones repetitivos
        if (hasRepeatingCharacters(password, 3)) {
            errors.add("La contraseña no debe tener más de 3 caracteres consecutivos repetidos");
        }

        if (hasSequentialCharacters(password)) {
            errors.add("La contraseña no debe contener secuencias obvias (abc, 123, etc.)");
        }

        // 5. Validar espacios en blanco
        if (password.trim().length() != password.length()) {
            errors.add("La contraseña no debe comenzar ni terminar con espacios");
        }

        // Lanzar excepción si hay errores
        if (!errors.isEmpty()) {
            log.warn("Contraseña rechazada. Errores: {}", errors);
            throw new WeakPasswordException(errors);
        }

        log.info("✅ Contraseña validada correctamente");
    }

    /**
     * Verifica si la contraseña tiene caracteres repetidos consecutivamente
     */
    private boolean hasRepeatingCharacters(String password, int maxRepeat) {
        int count = 1;
        for (int i = 1; i < password.length(); i++) {
            if (password.charAt(i) == password.charAt(i - 1)) {
                count++;
                if (count > maxRepeat) {
                    return true;
                }
            } else {
                count = 1;
            }
        }
        return false;
    }

    /**
     * Detecta secuencias comunes (abc, 123, qwerty, etc.)
     */
    private boolean hasSequentialCharacters(String password) {
        String lower = password.toLowerCase();

        // Secuencias alfabéticas
        String[] alphabetSequences = {"abc", "bcd", "cde", "def", "efg", "fgh", "ghi", "hij", "ijk", "jkl", "klm", "lmn", "mno", "nop", "opq", "pqr", "qrs", "rst", "stu", "tuv", "uvw", "vwx", "wxy", "xyz"};
        for (String seq : alphabetSequences) {
            if (lower.contains(seq)) return true;
        }

        // Secuencias numéricas
        String[] numericSequences = {"012", "123", "234", "345", "456", "567", "678", "789"};
        for (String seq : numericSequences) {
            if (password.contains(seq)) return true;
        }

        // Secuencias de teclado
        String[] keyboardSequences = {"qwerty", "asdfgh", "zxcvbn", "qwertyuiop"};
        for (String seq : keyboardSequences) {
            if (lower.contains(seq)) return true;
        }

        return false;
    }

    /**
     * Calcula la fortaleza de una contraseña (0-100)
     */
    public int calculatePasswordStrength(String password) {
        if (password == null || password.isEmpty()) {
            return 0;
        }

        int strength = 0;

        // Longitud (hasta 40 puntos)
        strength += Math.min(password.length() * 2, 40);

        // Complejidad (15 puntos cada uno)
        if (LOWERCASE.matcher(password).find()) strength += 15;
        if (UPPERCASE.matcher(password).find()) strength += 15;
        if (DIGIT.matcher(password).find()) strength += 15;
        if (SPECIAL_CHAR.matcher(password).find()) strength += 15;

        return Math.min(strength, 100);
    }
}