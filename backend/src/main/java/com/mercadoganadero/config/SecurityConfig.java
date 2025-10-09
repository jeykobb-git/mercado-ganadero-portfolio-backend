package com.mercadoganadero.config;

import com.mercadoganadero.security.CustomUserDetailsService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import com.mercadoganadero.security.jwt.JwtAuthenticationFilter;
import lombok.RequiredArgsConstructor;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

/**
 * Configuración de seguridad mejorada con:
 * - Soporte para @PreAuthorize en controllers
 * - RS256 para JWT
 * - Refresh tokens
 * - Autorización granular por roles
 */
@Configuration
@EnableWebSecurity // Habilita el filtro de seguridad de Spring Security
@EnableMethodSecurity(prePostEnabled = true)
@RequiredArgsConstructor // Para inyectar el filtro
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final CustomUserDetailsService userDetailsService;

    // ====================================================================
    // 1. BEAN PARA HASHEAR CONTRASEÑAS
    // ====================================================================
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }

    /**
     * Proveedor de autenticación DAO personalizado
     */
    @Bean
    public DaoAuthenticationProvider authenticationProvider() {
        DaoAuthenticationProvider authProvider = new DaoAuthenticationProvider();
        authProvider.setUserDetailsService(userDetailsService);
        authProvider.setPasswordEncoder(passwordEncoder());
        return authProvider;
    }

    // ====================================================================
    // 2. AuthenticationManager BEAN
    // ====================================================================
    @Bean
    public AuthenticationManager authenticationManager(AuthenticationConfiguration authConfig) throws Exception {
        return authConfig.getAuthenticationManager();
    }

    // ====================================================================
    // 2. REGLAS DE SEGURIDAD HTTP
    // ====================================================================
    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                // 1. API REST sin estado (Stateless)
                .csrf(AbstractHttpConfigurer::disable) // Deshabilitar CSRF (No se usa en API REST)
                .sessionManagement(session ->
                        session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))

                // Configurar proveedor de autenticación
                .authenticationProvider(authenticationProvider())

                // 2. Reglas de Autorización (Quién puede acceder a qué)
                .authorizeHttpRequests(auth -> auth
                        // Endpoints públicos (registro, login, reseteo de contraseña)
                        .requestMatchers(
                                "/api/auth/login",
                                "/api/auth/register",
                                "/api/auth/logout",
                                "/api/auth/refresh-token",
                                "/api/users/forgot-password",
                                "/api/users/reset-password",
                                "/api/users/verify-email",
                                "/api/users/available-email"
                        ).permitAll() // Permitir acceso sin autenticación

                        // ========== ENDPOINTS DE ADMINISTRACIÓN ==========
                        .requestMatchers("/api/admin/**").hasRole("ADMIN")

                        // ========== ENDPOINTS DE VENDEDORES ==========
                        .requestMatchers("/api/sellers/**").hasAnyRole("SELLER", "ADMIN")

                        // ========== ENDPOINTS DE COMPRADORES ==========
                        .requestMatchers("/api/buyers/**").hasAnyRole("BUYER", "ADMIN")

                        // Endpoints para usuarios autenticados
                        .anyRequest().authenticated() // Cualquier otra petición requiere autenticación
                )
                // 1. filtro JWT (para autenticar y poner el ID en el contexto)
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }
}