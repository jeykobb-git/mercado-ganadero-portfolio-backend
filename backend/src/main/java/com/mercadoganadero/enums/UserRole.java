package com.mercadoganadero.enums;

/**
 * Enum para roles de usuario
 * Define los niveles de autorización en el sistema
 */
public enum UserRole {
    ADMIN("ROLE_ADMIN", "Administrador del sistema"),
    SELLER("ROLE_SELLER", "Vendedor/Ganadero"),
    BUYER("ROLE_BUYER", "Comprador"),
    MODERATOR("ROLE_MODERATOR", "Moderador de contenido"),
    USER("ROLE_USER", "Usuario base");

    private final String authority;
    private final String description;

    UserRole(String authority, String description) {
        this.authority = authority;
        this.description = description;
    }

    public String getAuthority() {
        return authority;
    }

    public String getDescription() {
        return description;
    }

    /**
     * Obtiene el rol desde el authority string
     */
    public static UserRole fromAuthority(String authority) {
        for (UserRole role : values()) {
            if (role.authority.equals(authority)) {
                return role;
            }
        }
        throw new IllegalArgumentException("Rol desconocido: " + authority);
    }
}