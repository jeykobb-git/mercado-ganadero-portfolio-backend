package com.mercadoganadero.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
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
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration;

@Configuration
@EnableWebSecurity // Habilita el filtro de seguridad de Spring Security
@RequiredArgsConstructor // Para inyectar el filtro
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;

    // ====================================================================
    // 1. BEAN PARA HASHEAR CONTRASEÑAS
    // ====================================================================
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }

    // ====================================================================
    // 2. AuthenticationManager BEAN
    // ====================================================================
    @Bean
    public AuthenticationManager authenticationManager(AuthenticationConfiguration authenticationConfiguration) throws Exception {
        return authenticationConfiguration.getAuthenticationManager();
    }

    // ====================================================================
    // 2. REGLAS DE SEGURIDAD HTTP
    // ====================================================================
    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                // 1. API REST sin estado (Stateless)
                .csrf(AbstractHttpConfigurer::disable) // Deshabilitar CSRF (No se usa en API REST)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))

                // 2. Reglas de Autorización (Quién puede acceder a qué)
                .authorizeHttpRequests(auth -> auth
                        // Endpoints públicos (registro, login, reseteo de contraseña)
                        .requestMatchers(
                                "/api/auth/**",
                                "/api/users/register",
                                "/api/users/forgot-password",
                                "/api/users/reset-password",
                                "/api/users/verify-email",
                                "/api/users/available-email"
                        ).permitAll() // Permitir acceso sin autenticación

                        // Endpoints para usuarios autenticados
                        .anyRequest().authenticated() // Cualquier otra petición requiere autenticación
                )
                // 1. filtro JWT (para autenticar y poner el ID en el contexto)
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }
}