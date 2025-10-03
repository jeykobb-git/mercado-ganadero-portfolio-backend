package com.mercadoganadero.security;

import com.mercadoganadero.entity.User;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;

import java.util.Collection;
import java.util.Collections;
import lombok.Getter;

@Getter // Para poder acceder al userId desde el filtro
public class CustomUserDetails implements UserDetails {

    private Integer userId;
    private String email;
    private String password;
    private Collection<? extends GrantedAuthority> authorities;

    public CustomUserDetails(User user) {
        this.userId = user.getUserId();
        this.email = user.getEmail();
        this.password = user.getPasswordHash(); // Contraseña hasheada
        // TODO: cargar roles/autoridades
        this.authorities = Collections.emptyList();
    }

    // Métodos de la interfaz UserDetails (implementación mínima)
    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return authorities;
    }

    @Override
    public String getPassword() {
        return password;
    }

    @Override
    public String getUsername() {
        return email;
    }

    @Override
    public boolean isAccountNonExpired() { return true; }

    @Override
    public boolean isAccountNonLocked() { return true; }

    @Override
    public boolean isCredentialsNonExpired() { return true; }

    // Usamos el campo isActive de tu entidad
    @Override
    public boolean isEnabled() { return true; }
}