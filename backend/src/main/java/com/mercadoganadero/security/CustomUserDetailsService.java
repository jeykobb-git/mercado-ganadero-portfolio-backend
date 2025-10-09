package com.mercadoganadero.security;

import com.mercadoganadero.entity.User;
import com.mercadoganadero.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
import java.util.stream.Collectors;

import java.util.ArrayList; // Para simular roles/autoridades

/**
 * Carga los datos del usuario para el contexto de Spring Security.
 * Spring Security requiere esta clase para manejar la autenticación.
 */
@Service
@RequiredArgsConstructor
public class CustomUserDetailsService implements UserDetailsService {

    private final UserRepository userRepository;

    /**
     * Este método es llamado por Spring Security para cargar al usuario
     * durante la autenticación (login o validación de JWT).
     * @param email El 'username' proporcionado (que es el email en nuestro caso).
     * @return UserDetails objeto que representa al usuario.
     * @throws UsernameNotFoundException si el usuario no existe o no está activo.
     */
    @Override
    @Transactional(readOnly = true)
    public UserDetails loadUserByUsername(String email) throws UsernameNotFoundException {
        // Usamos el método findActiveByEmail definido en UserRepository
        User user = userRepository.findActiveByEmail(email)
                .orElseThrow(() -> new UsernameNotFoundException("Usuario no encontrado o inactivo con email: " + email));

        // Verificar que el usuario esté activo
        if (!user.getIsActive()) {
            throw new UsernameNotFoundException("La cuenta ha sido desactivada");
        }
        // Convertir roles a authorities de Spring Security
        Collection<GrantedAuthority> authorities = user.getRoles().stream()
                .map(role -> new SimpleGrantedAuthority(role.getAuthority()))
                .collect(Collectors.toList());
        // Convertimos tu entidad User a un objeto UserDetails de Spring Security.
        // Spring Security necesita su propio objeto User para el contexto.
        return org.springframework.security.core.userdetails.User.builder()
                .username(user.getEmail())
                .password(user.getPasswordHash())
                .authorities(authorities)
                .accountExpired(false)
                .accountLocked(false)
                .credentialsExpired(false)
                .disabled(!user.getIsActive())
                .build();
    }
}