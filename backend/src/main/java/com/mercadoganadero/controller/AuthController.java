package com.mercadoganadero.controller;

import com.mercadoganadero.dto.*;
import com.mercadoganadero.entity.RefreshToken;
import com.mercadoganadero.entity.User;
import com.mercadoganadero.security.jwt.JwtTokenProvider;
import com.mercadoganadero.service.RefreshTokenService;
import com.mercadoganadero.service.UserService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

/**
 * Controlador de autenticación
 * - Login con access + refresh token
 * - Endpoint para renovar tokens
 * - Logout que revoca tokens
 */
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
@Slf4j
public class AuthController {

    private final AuthenticationManager authenticationManager; // Mecanismo de autenticación de Spring
    private final JwtTokenProvider tokenProvider; // Proveedor de JWT
    private final UserService userService; // Servicio de negocio para el registro
    private final RefreshTokenService refreshTokenService;

    @Value("${app.jwt.expiration-ms}")
    private long jwtExpirationInMs;

    /**
     * POST /api/auth/login
     * Maneja el inicio de sesión y genera el JWT
     * * NOTA: Requiere que se configure el bean AuthenticationManager en SecurityConfig.
     */
    @PostMapping("/login")
    public ResponseEntity<AuthResponseDTO> authenticateUser(
            @Valid @RequestBody LoginDTO loginDTO,
            HttpServletRequest request) {

        // 1. Autenticar las credenciales (llama a CustomUserDetailsService)
        Authentication authentication = authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(
                        loginDTO.getEmail(),
                        loginDTO.getPassword()
                )
        );

        SecurityContextHolder.getContext().setAuthentication(authentication);

        // 2. Obtener usuario completo con roles
        User user = userService.getUserByEmail(loginDTO.getEmail());

        // 3. Generar Access Token (corto, con roles)
        String accessToken = tokenProvider.generateAccessToken(
                user.getEmail(),
                user.getUserId(),
                user.getRolesList()
        );

        // 4. Generar Refresh Token (largo, sin roles sensibles)
        String refreshTokenStr = tokenProvider.generateRefreshToken(
                user.getEmail(),
                user.getUserId()
        );

        // 5. Guardar refresh token en BD
        RefreshToken refreshToken = refreshTokenService.createRefreshToken(
                user.getUserId(),
                request
        );

        // 6. Actualizar último login
        userService.updateLastLogin(user.getUserId());

        // 7. Respuesta
        AuthResponseDTO response = AuthResponseDTO.builder()
                .accessToken(accessToken)
                .refreshToken(refreshToken.getToken())
                .expiresIn(jwtExpirationInMs / 1000) // Convertir a segundos
                .user(UserResponseDTO.fromEntity(user))
                .build();

        log.info("Login exitoso: {} desde IP: {}", user.getEmail(),
                refreshToken.getIpAddress());

        return ResponseEntity.ok(response);
    }

    /**
     * POST /api/auth/refresh-token
     * Renueva el access token usando el refresh token
     */
    @PostMapping("/refresh-token")
    public ResponseEntity<AuthResponseDTO> refreshToken(
            @Valid @RequestBody RefreshTokenDTO refreshTokenDTO,
            HttpServletRequest request) {

        // 1. Validar refresh token
        RefreshToken refreshToken = refreshTokenService.validateRefreshToken(
                refreshTokenDTO.getRefreshToken()
        );

        // 2. Obtener usuario
        User user = userService.getUserById(refreshToken.getUserId());

        // 3. Generar nuevo access token
        String newAccessToken = tokenProvider.generateAccessToken(
                user.getEmail(),
                user.getUserId(),
                user.getRolesList()
        );

        // 4. Generar nuevo refresh token (rotación)
        String newRefreshTokenStr = tokenProvider.generateRefreshToken(
                user.getEmail(),
                user.getUserId()
        );

        RefreshToken newRefreshToken = refreshTokenService.createRefreshToken(
                user.getUserId(),
                request
        );

        // 5. Revocar el refresh token viejo
        refreshTokenService.revokeToken(
                refreshTokenDTO.getRefreshToken(),
                newRefreshToken.getToken()
        );

        // 6. Respuesta
        AuthResponseDTO response = AuthResponseDTO.builder()
                .accessToken(newAccessToken)
                .refreshToken(newRefreshToken.getToken())
                .expiresIn(jwtExpirationInMs / 1000)
                .user(UserResponseDTO.fromEntity(user))
                .build();

        log.info("🔄 Token renovado para: {}", user.getEmail());

        return ResponseEntity.ok(response);
    }

    /**
     * POST /api/auth/register
     * Maneja el registro de nuevos usuarios
     */
    @PostMapping("/register")
    public ResponseEntity<UserResponseDTO> registerUser(
            @Valid @RequestBody UserCreateDTO userCreateDTO) {
        // El UserService lanza DuplicateEmailException si el email ya existe
        User user = userService.createUser(userCreateDTO);

        log.info("Nuevo usuario registrado: {}", user.getEmail());

        // Devolvemos el usuario creado (sin el password hash)
        return new ResponseEntity<>(UserResponseDTO.fromEntity(user), HttpStatus.CREATED);
    }

    /**
     * POST /api/auth/logout
     * Cierra sesión y revoca el refresh token actual
     */
    @PostMapping("/logout")
    public ResponseEntity<Void> logout(@Valid @RequestBody RefreshTokenDTO refreshTokenDTO) {
        try {
            RefreshToken refreshToken = refreshTokenService.validateRefreshToken(
                    refreshTokenDTO.getRefreshToken()
            );

            refreshTokenService.revokeToken(refreshTokenDTO.getRefreshToken(), null);

            log.info("Logout exitoso para usuario ID: {}", refreshToken.getUserId());

            return ResponseEntity.ok().build();
        } catch (Exception e) {
            // Si el token no es válido, igual respondemos OK (idempotencia)
            return ResponseEntity.ok().build();
        }
    }

    /**
     * POST /api/auth/logout-all
     * Cierra todas las sesiones del usuario actual
     */
    @PostMapping("/logout-all")
    public ResponseEntity<Void> logoutAll(@AuthenticationPrincipal UserDetails userDetails) {
        User user = userService.getUserByEmail(userDetails.getUsername());
        refreshTokenService.revokeAllUserTokens(user.getUserId());

        log.info("Logout global para usuario: {}", user.getEmail());

        return ResponseEntity.ok().build();
    }
}