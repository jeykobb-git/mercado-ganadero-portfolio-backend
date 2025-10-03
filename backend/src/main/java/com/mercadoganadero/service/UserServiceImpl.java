package com.mercadoganadero.service;

import com.mercadoganadero.dto.UserCreateDTO;
import com.mercadoganadero.dto.UserUpdateDTO;
import com.mercadoganadero.entity.User;
import com.mercadoganadero.repository.UserRepository;
import com.mercadoganadero.exception.ResourceNotFoundException;
import com.mercadoganadero.exception.DuplicateEmailException;
import com.mercadoganadero.exception.InvalidPasswordException;
import com.mercadoganadero.exception.InvalidTokenException;

import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class UserServiceImpl implements UserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    // ============================= OPERACIONES CRUD BÁSICAS =============================

    /**
     * Obtiene usuario por ID.
     * @throws ResourceNotFoundException si no existe.
     */
    @Override
    public User getUserById(Integer userId) {
        return userRepository.findById(userId)
                .orElseThrow(() -> new ResourceNotFoundException("Usuario", "ID", userId));
    }

    /**
     * Obtiene usuario por email.
     * @throws ResourceNotFoundException si no existe.
     */
    @Override
    public User getUserByEmail(String email) {
        // Usamos findActiveByEmail si solo queremos usuarios activos,
        // o findByEmail si necesitamos el objeto para manejo interno. Usaremos findByEmail.
        return userRepository.findByEmail(email)
                .orElseThrow(() -> new ResourceNotFoundException("Usuario", "email", email));
    }

    /**
     * Crea nuevo usuario.
     * @throws DuplicateEmailException si el email ya existe.
     */
    @Override
    @Transactional
    public User createUser(UserCreateDTO dto) {
        // 1. Validar que el email no exista
        if (userRepository.existsByEmail(dto.getEmail())) {
            throw new DuplicateEmailException(dto.getEmail());
        }

        // 2. Mapeo de DTO a Entidad y Hashing de Contraseña
        // Se usa el Builder de Lombok
        User newUser = User.builder()
                .name(dto.getName())
                .lastName(dto.getLastName())
                .email(dto.getEmail())
                .phoneNumber(dto.getPhoneNumber())
                .userTypeId(dto.getUserTypeId())
                .addressId(dto.getAddressId())
                .subscriptionPlanId(dto.getSubscriptionPlanId())
                .settings(dto.getSettings())
                .notificationPreferences(dto.getNotificationPreferences())
                .passwordHash(passwordEncoder.encode(dto.getPassword())) // <--- HASHEO
                .passwordSalt("")
                .passwordAlgorithm("bcrypt")
                .isActive(true)
                .emailVerified(false)
                .tfaEnabled(false)
                // createdAt y updatedAt se gestionan con @PrePersist en la entidad
                .build();

        return userRepository.save(newUser);
    }

    /**
     * Actualiza usuario existente.
     * @throws ResourceNotFoundException si no existe.
     */
    @Override
    @Transactional
    public User updateUser(Integer userId, UserUpdateDTO dto) {
        // 1. Buscar usuario, si no existe lanza ResourceNotFoundException
        User existingUser = this.getUserById(userId);

        // 2. Aplicar actualizaciones solo si el campo existe en el DTO (usando Optional.ofNullable)
        Optional.ofNullable(dto.getName()).ifPresent(existingUser::setName);
        Optional.ofNullable(dto.getLastName()).ifPresent(existingUser::setLastName);
        Optional.ofNullable(dto.getPhoneNumber()).ifPresent(existingUser::setPhoneNumber);
        Optional.ofNullable(dto.getAddressId()).ifPresent(existingUser::setAddressId);
        Optional.ofNullable(dto.getSubscriptionPlanId()).ifPresent(existingUser::setSubscriptionPlanId);
        Optional.ofNullable(dto.getSettings()).ifPresent(existingUser::setSettings);
        Optional.ofNullable(dto.getNotificationPreferences()).ifPresent(existingUser::setNotificationPreferences);
        Optional.ofNullable(dto.getTfaEnabled()).ifPresent(existingUser::setTfaEnabled);

        // El updatedAt se maneja en la Entidad (con @PreUpdate)
        return userRepository.save(existingUser);
    }

    /**
     * Soft delete de usuario.
     * @throws ResourceNotFoundException si no existe.
     */
    @Override
    @Transactional
    public void deleteUser(Integer userId) {
        User user = this.getUserById(userId); // Lanza 404 si no existe

        // Soft Delete: marca como eliminado e inactivo
        user.setDeletedAt(OffsetDateTime.now());
        user.setIsActive(false);
        userRepository.save(user);
    }

    // ============================= BÚSQUEDA Y LISTADOS =============================

    @Override
    public Page<User> searchUsers(String searchTerm, Pageable pageable) {
        // Asumiendo que UserRepository tiene un método con la Query de búsqueda
        return userRepository.searchUsers(searchTerm, pageable);
    }

    @Override
    public Page<User> getAllUsers(Pageable pageable) {
        // Lista solo usuarios que no tienen marca de borrado
        return userRepository.findByDeletedAtIsNull(pageable);
    }

    @Override
    public List<User> getUsersByType(Integer userTypeId) {
        return userRepository.findByUserTypeIdAndDeletedAtIsNull(userTypeId);
    }

    // ============================= OPERACIONES DE SEGURIDAD =============================

    /**
     * Cambia contraseña validando la actual.
     * @throws InvalidPasswordException si la contraseña actual no coincide.
     * @throws ResourceNotFoundException si no existe.
     */
    @Override
    @Transactional
    public void changePassword(Integer userId, String oldPassword, String newPassword) {
        User user = this.getUserById(userId); // 404 si no existe

        String trimmedOldPassword = oldPassword.trim();

        // 1. Verificar contraseña actual (usando PasswordEncoder.matches)
        if (!passwordEncoder.matches(trimmedOldPassword, user.getPasswordHash())) {
            throw new InvalidPasswordException("La contraseña actual proporcionada es incorrecta.");
        }

        // 2. Hashear y guardar la nueva contraseña
        user.setPasswordHash(passwordEncoder.encode(newPassword));
        userRepository.save(user);
    }

    /**
     * Inicia proceso de reseteo de contraseña.
     * En un caso real, no lanza 404 para evitar la enumeración de usuarios.
     */
    @Override
    @Transactional
    public void initiatePasswordReset(String email) {
        Optional<User> userOptional = userRepository.findByEmail(email);

        if (userOptional.isPresent()) {
            User user = userOptional.get();

            // 1. Generar token y fecha de expiración (Ejemplo de 1 hora)
            String token = UUID.randomUUID().toString();
            OffsetDateTime expiryDate = OffsetDateTime.now().plusHours(1);

            // 2. Guardar token
            // NOTA: Se asume que User.java tiene los setters para estos campos
            user.setPasswordResetToken(token);
            user.setPasswordResetTokenExpiryDate(expiryDate);
            userRepository.save(user);

            // TODO: Implementar envío de email
            // emailService.sendPasswordResetEmail(user.getEmail(), token);)
        }
    }

    /**
     * Completa reseteo de contraseña con token.
     * @throws InvalidTokenException si el token no es válido o ha expirado.
     */
    @Override
    @Transactional
    public void resetPassword(String token, String newPassword) {
        // 1. Buscar usuario por token (Asumimos findByPasswordResetToken en el repo)
        User user = userRepository.findByPasswordResetToken(token)
                .orElseThrow(() -> new InvalidTokenException("El token de reseteo es inválido."));

        // 2. Validar expiración (Si el campo existe en la entidad User)

        if (user.getPasswordResetTokenExpiryDate() != null && user.getPasswordResetTokenExpiryDate().isBefore(OffsetDateTime.now())) {
            user.setPasswordResetToken(null);
            user.setPasswordResetTokenExpiryDate(null);
            userRepository.save(user);
            throw new InvalidTokenException("El token de reseteo ha expirado.");
        }

        // 3. Resetear y Hashear la nueva contraseña
        user.setPasswordHash(passwordEncoder.encode(newPassword));

        // 4. Limpiar token después de uso
        user.setPasswordResetToken(null);
        user.setPasswordResetTokenExpiryDate(null);
        userRepository.save(user);
    }

    /**
     * Verifica email con token.
     * @throws InvalidTokenException si el token no es válido.
     */
    @Override
    @Transactional
    public void verifyEmail(String token) {
        // 1. Buscar usuario por token (Asumimos findByEmailVerificationToken en el repo)
        User user = userRepository.findByEmailVerificationToken(token)
                .orElseThrow(() -> new InvalidTokenException("El token de verificación es inválido."));

        // 2. Marcar email como verificado y limpiar token
        user.setEmailVerified(true);
        user.setEmailVerificationToken(null);
        userRepository.save(user);
    }

    // ============================= ESTADÍSTICAS Y VALIDACIONES =============================

    @Override
    public long countActiveUsers() {
        return userRepository.countByDeletedAtIsNull();
    }

    @Override
    @Transactional
    public void updateLastLogin(Integer userId) {
        userRepository.findById(userId).ifPresent(user -> {
            user.setLastLogin(OffsetDateTime.now());
            userRepository.save(user);
        });
    }

    @Override
    public boolean isEmailAvailable(String email) {
        return !userRepository.existsByEmail(email);
    }

    @Override
    public boolean isEmailAvailable(String email, Integer excludeUserId) {
        // Si el email no existe, está disponible.
        // Si existe, verifica que el usuario encontrado NO sea el excluido.
        return !userRepository.existsByEmailAndUserIdNot(email, excludeUserId);
    }
}