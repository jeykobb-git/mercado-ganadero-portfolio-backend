package com.mercadoganadero.security;

import com.mercadoganadero.entity.User;
import com.mercadoganadero.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

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
     * @param username El 'username' proporcionado (que es el email en nuestro caso).
     * @return UserDetails objeto que representa al usuario.
     * @throws UsernameNotFoundException si el usuario no existe o no está activo.
     */
    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        // Usamos el método findActiveByEmail definido en UserRepository
        User user = userRepository.findActiveByEmail(username)
                .orElseThrow(() -> new UsernameNotFoundException("Usuario no encontrado o inactivo con email: " + username));

        // Convertimos tu entidad User a un objeto UserDetails de Spring Security.
        // Spring Security necesita su propio objeto User para el contexto.
        return new CustomUserDetails(user);
        // TODO: Llenar la lista de Roles y permisos**
    }
}