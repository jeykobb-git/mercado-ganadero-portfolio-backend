package com.mercadoganadero.service;

import com.mercadoganadero.dto.UserCreateDTO;
import com.mercadoganadero.dto.UserUpdateDTO;
import com.mercadoganadero.entity.User;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.util.List;

/**
 * Service interface para operaciones de Usuario
 * Define el contrato de la lógica de negocio
 */
public interface UserService {

    // ============= OPERACIONES CRUD BÁSICAS =============

    /**
     * Obtiene usuario por ID
     * @param userId El ID del usuario
     * @return User el usuario encontrado
     */
    User getUserById(Integer userId);

    /**
     * Obtiene usuario por email
     * @param email El email del usuario
     * @return User el usuario encontrado
     */
    User getUserByEmail(String email);

    /**
     * Crea nuevo usuario
     * @param dto El DTO con los datos de creación del usuario.
     * @return El nuevo objeto User creado.
     * Genera DuplicateEmailException si el email ya existe.
     */
    User createUser(UserCreateDTO dto);

    /**
     * Actualiza usuario existente
     * @param userId El ID del usuario a actualizar.
     * @param dto El DTO con los datos para la actualización.
     * @return El objeto User actualizado.
     * Genera ResourceNotFoundException si el usuario no existe.
     */
    User updateUser(Integer userId, UserUpdateDTO dto);

    /**
     * Soft delete de usuario
     * @param userId El ID del usuario a eliminar.
     * Genera ResourceNotFoundException si el usuario no existe.
     */
    void deleteUser(Integer userId);

    // ============= BÚSQUEDA Y LISTADOS =============

    /**
     * Búsqueda de usuarios por término
     * Busca en nombre, apellido y email.
     * @param searchTerm El término de búsqueda.
     * @param pageable La información de paginación.
     * @return Una página de objetos User.
     */
    Page<User> searchUsers(String searchTerm, Pageable pageable);

    /**
     * Lista todos los usuarios con paginación
     * @param pageable La información de paginación.
     * @return Una página de objetos User.
     */
    Page<User> getAllUsers(Pageable pageable);

    /**
     * Obtiene usuarios por tipo
     * @param userTypeId El ID del tipo de usuario.
     * @return Una lista de objetos User.
     */
    List<User> getUsersByType(Integer userTypeId);

    // ============= OPERACIONES DE SEGURIDAD =============

    /**
     * Cambia contraseña validando la actual
     * @param userId El ID del usuario.
     * @param oldPassword La contraseña actual.
     * @param newPassword La nueva contraseña.
     * Genera InvalidPasswordException si la contraseña actual no coincide.
     */
    void changePassword(Integer userId, String oldPassword, String newPassword);

    /**
     * Inicia proceso de reseteo de contraseña
     * Envía email con token.
     * @param email El correo electrónico del usuario.
     */
    void initiatePasswordReset(String email);

    /**
     * Completa reseteo de contraseña con token
     * @param token El token de reseteo.
     * @param newPassword La nueva contraseña.
     * Genera InvalidTokenException si el token no es válido.
     */
    void resetPassword(String token, String newPassword);

    /**
     * Verifica email con token
     * @param token El token de verificación.
     * Genera InvalidTokenException si el token no es válido.
     */
    void verifyEmail(String token);

    // ============= ESTADÍSTICAS =============

    /**
     * Cuenta usuarios activos
     * @return El número de usuarios activos.
     */
    long countActiveUsers();

    /**
     * Actualiza último login
     * @param userId El ID del usuario.
     */
    void updateLastLogin(Integer userId);

    // ============= VALIDACIONES =============

    /**
     * Verifica si un email está disponible
     * @param email El correo electrónico a verificar.
     * @return true si está disponible, false en caso contrario.
     */
    boolean isEmailAvailable(String email);

    /**
     * Verifica si un email está disponible (excluyendo un usuario)
     * @param email El correo electrónico a verificar.
     * @param excludeUserId El ID del usuario a excluir de la verificación.
     * @return true si está disponible, false en caso contrario.
     */
    boolean isEmailAvailable(String email, Integer excludeUserId);
}