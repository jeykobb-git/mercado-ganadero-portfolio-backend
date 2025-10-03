package com.mercadoganadero.controller;

import com.mercadoganadero.dto.*;
import com.mercadoganadero.entity.User;
import com.mercadoganadero.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import jakarta.validation.Valid;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * REST Controller para endpoints de users
 * Base URL: /api/users
 *
 * EXPLICACIÓN DE ARQUITECTURA:
 * - Controller: Maneja HTTP requests/responses
 * - Service: Contiene lógica de negocio
 * - Repository: Acceso a datos
 * - DTOs: Transferencia de datos (evita exponer entidades directamente)
 */
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor // Lombok genera constructor con campos final
@CrossOrigin(origins = "${app.cors.allowed-origins}") // Lee de application.yml
public class UserController {

    private final UserService userService;

    /**
     * GET /api/users/{id}
     * Obtener usuario por ID
     *
     * @PathVariable vincula el {id} de la URL con el parámetro
     * ResponseEntity permite controlar status HTTP y body
     */
    @GetMapping("/{id}")
    public ResponseEntity<UserResponseDTO> getUserById(@PathVariable Integer id) {
        User user = userService.getUserById(id);
        return ResponseEntity.ok(UserResponseDTO.fromEntity(user));
    }

    /**
     * GET /api/users/email/{email}
     * Buscar por email exacto
     */
    @GetMapping("/email/{email}")
    public ResponseEntity<UserResponseDTO> getUserByEmail(@PathVariable String email) {
        User user = userService.getUserByEmail(email);
        return ResponseEntity.ok(UserResponseDTO.fromEntity(user));
    }

    /**
     * GET /api/users/search?q=termino&page=0&size=10
     * Búsqueda con paginación
     *
     * @RequestParam captura parámetros de query string
     * defaultValue provee valores por defecto si no se envían
     */
    @GetMapping("/search")
    public ResponseEntity<Map<String, Object>> searchUsers(
            @RequestParam String q,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(defaultValue = "createdAt") String sort,
            @RequestParam(defaultValue = "DESC") String direction) {

        Sort.Direction sortDirection = direction.equalsIgnoreCase("ASC")
                ? Sort.Direction.ASC
                : Sort.Direction.DESC;

        Pageable pageable = PageRequest.of(page, size, Sort.by(sortDirection, sort));
        Page<User> usersPage = userService.searchUsers(q, pageable);

        // Convertir entidades a DTOs
        List<UserResponseDTO> userDTOs = usersPage.getContent().stream()
                .map(UserResponseDTO::fromEntity)
                .collect(Collectors.toList());

        Map<String, Object> response = new HashMap<>();
        response.put("users", userDTOs);
        response.put("currentPage", usersPage.getNumber());
        response.put("totalItems", usersPage.getTotalElements());
        response.put("totalPages", usersPage.getTotalPages());
        response.put("searchTerm", q);

        return ResponseEntity.ok(response);
    }

    /**
     * POST /api/users
     * Crear nuevo usuario
     *
     * @Valid activa validación de Bean Validation
     * @RequestBody deserializa JSON a objeto Java
     */
    @PostMapping
    public ResponseEntity<Map<String, Object>> createUser(@Valid @RequestBody UserCreateDTO dto) {
        User user = userService.createUser(dto);

        Map<String, Object> response = new HashMap<>();
        response.put("message", "Usuario creado exitosamente");
        response.put("user", UserResponseDTO.fromEntity(user));
        response.put("verificationRequired", true);

        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    /**
     * PUT /api/users/{id}
     * Actualización parcial de usuario
     * Solo actualiza campos que no son críticos (no password, no email)
     */
    @PutMapping("/{id}")
    public ResponseEntity<Map<String, Object>> updateUser(
            @PathVariable Integer id,
            @Valid @RequestBody UserUpdateDTO dto) {

        User user = userService.updateUser(id, dto);

        Map<String, Object> response = new HashMap<>();
        response.put("message", "Usuario actualizado exitosamente");
        response.put("user", UserResponseDTO.fromEntity(user));

        return ResponseEntity.ok(response);
    }

    /**
     * DELETE /api/users/{id}
     * Soft delete - no borra físicamente, solo marca como eliminado
     */
    @DeleteMapping("/{id}")
    public ResponseEntity<Map<String, String>> deleteUser(@PathVariable Integer id) {
        userService.deleteUser(id);

        Map<String, String> response = new HashMap<>();
        response.put("message", "Usuario eliminado exitosamente");
        response.put("userId", id.toString());

        return ResponseEntity.ok(response);
    }

    /**
     * PUT /api/users/{id}/password
     * Cambio de contraseña con validación de contraseña actual
     */
    @PutMapping("/{id}/password")
    public ResponseEntity<Map<String, String>> changePassword(
            @PathVariable Integer id,
            @Valid @RequestBody ChangePasswordDTO dto) {

        userService.changePassword(id, dto.getOldPassword(), dto.getNewPassword());

        Map<String, String> response = new HashMap<>();
        response.put("message", "Contraseña actualizada exitosamente");

        return ResponseEntity.ok(response);
    }

    /**
     * POST /api/users/verify-email?token=xyz123
     * Verificación de email mediante token
     */
    @PostMapping("/verify-email")
    public ResponseEntity<Map<String, String>> verifyEmail(@RequestParam String token) {
        userService.verifyEmail(token);

        Map<String, String> response = new HashMap<>();
        response.put("message", "Email verificado exitosamente");

        return ResponseEntity.ok(response);
    }

    /**
     * GET /api/users/stats/active-count
     * Estadística: usuarios activos
     */
    @GetMapping("/stats/active-count")
    public ResponseEntity<Map<String, Long>> getActiveUserCount() {
        long count = userService.countActiveUsers();

        Map<String, Long> response = new HashMap<>();
        response.put("activeUsers", count);

        return ResponseEntity.ok(response);
    }

    /**
     * GET /api/users/by-type/{typeId}
     * Filtrar usuarios por tipo
     */
    @GetMapping("/by-type/{typeId}")
    public ResponseEntity<Map<String, Object>> getUsersByType(@PathVariable Integer typeId) {
        List<User> users = userService.getUsersByType(typeId);

        List<UserResponseDTO> userDTOs = users.stream()
                .map(UserResponseDTO::fromEntity)
                .collect(Collectors.toList());

        Map<String, Object> response = new HashMap<>();
        response.put("userTypeId", typeId);
        response.put("count", userDTOs.size());
        response.put("users", userDTOs);

        return ResponseEntity.ok(response);
    }

    /**
     * GET /api/users?page=0&size=10
     * Listar todos con paginación
     *
     * Pageable permite navegación por páginas grandes de datos
     */
    @GetMapping
    public ResponseEntity<Map<String, Object>> getAllUsers(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(defaultValue = "createdAt") String sort,
            @RequestParam(defaultValue = "DESC") String direction) {

        Sort.Direction sortDirection = direction.equalsIgnoreCase("ASC")
                ? Sort.Direction.ASC
                : Sort.Direction.DESC;

        Pageable pageable = PageRequest.of(page, size, Sort.by(sortDirection, sort));
        Page<User> usersPage = userService.getAllUsers(pageable);

        List<UserResponseDTO> userDTOs = usersPage.getContent().stream()
                .map(UserResponseDTO::fromEntity)
                .collect(Collectors.toList());

        Map<String, Object> response = new HashMap<>();
        response.put("users", userDTOs);
        response.put("currentPage", usersPage.getNumber());
        response.put("totalItems", usersPage.getTotalElements());
        response.put("totalPages", usersPage.getTotalPages());

        return ResponseEntity.ok(response);
    }

    /**
     * POST /api/users/forgot-password
     * Iniciar proceso de recuperación de contraseña
     */
    @PostMapping("/forgot-password")
    public ResponseEntity<Map<String, String>> forgotPassword(@RequestBody Map<String, String> request) {
        String email = request.get("email");
        userService.initiatePasswordReset(email);

        Map<String, String> response = new HashMap<>();
        response.put("message", "Si el email existe, recibirás instrucciones para restablecer tu contraseña");

        return ResponseEntity.ok(response);
    }

    /**
     * POST /api/users/reset-password
     * Completar reseteo de contraseña con token
     */
    @PostMapping("/reset-password")
    public ResponseEntity<Map<String, String>> resetPassword(@Valid @RequestBody ResetPasswordDTO dto) {
        userService.resetPassword(dto.getToken(), dto.getNewPassword());

        Map<String, String> response = new HashMap<>();
        response.put("message", "Contraseña restablecida exitosamente");

        return ResponseEntity.ok(response);
    }
}