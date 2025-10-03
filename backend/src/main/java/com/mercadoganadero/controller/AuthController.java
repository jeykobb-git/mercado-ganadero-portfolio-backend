package com.mercadoganadero.controller;

import com.mercadoganadero.dto.AuthResponseDTO;
import com.mercadoganadero.dto.LoginDTO;
import com.mercadoganadero.dto.UserCreateDTO;
import com.mercadoganadero.dto.UserResponseDTO;
import com.mercadoganadero.entity.User;
import com.mercadoganadero.security.jwt.JwtTokenProvider;
import com.mercadoganadero.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthenticationManager authenticationManager; // Mecanismo de autenticación de Spring
    private final JwtTokenProvider tokenProvider;               // Proveedor de JWT
    private final UserService userService;                      // Servicio de negocio para el registro

    /**
     * POST /api/auth/login
     * Maneja el inicio de sesión y genera el JWT
     * * NOTA: Requiere que se configure el bean AuthenticationManager en SecurityConfig.
     */
    @PostMapping("/login")
    public ResponseEntity<AuthResponseDTO> authenticateUser(@Valid @RequestBody LoginDTO loginDTO) {

        // 1. Autenticar las credenciales (llama a CustomUserDetailsService)
        Authentication authentication = authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(
                        loginDTO.getEmail(),
                        loginDTO.getPassword()
                )
        );

        // 2. Establecer la autenticación en el contexto de seguridad (opcional, pero buena práctica)
        SecurityContextHolder.getContext().setAuthentication(authentication);

        // 3. Generar el JWT
        String jwt = tokenProvider.generateToken(loginDTO.getEmail());

        // 4. Devolver el token y los datos del usuario
        User user = userService.getUserByEmail(loginDTO.getEmail());

        AuthResponseDTO response = AuthResponseDTO.builder()
                .token(jwt)
                .user(UserResponseDTO.fromEntity(user)) // Usamos el DTO de respuesta para el usuario
                .build();

        return ResponseEntity.ok(response);
    }

    /**
     * POST /api/auth/register
     * Maneja el registro de nuevos usuarios
     */
    @PostMapping("/register")
    public ResponseEntity<UserResponseDTO> registerUser(@Valid @RequestBody UserCreateDTO userCreateDTO) {
        // El UserService lanza DuplicateEmailException si el email ya existe
        User user = userService.createUser(userCreateDTO);

        // Devolvemos el usuario creado (sin el password hash)
        return new ResponseEntity<>(UserResponseDTO.fromEntity(user), HttpStatus.CREATED);
    }

    // Aquí se podrían añadir endpoints como /refresh-token
}