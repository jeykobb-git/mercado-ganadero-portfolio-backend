package com.mercadoganadero.entity;

import com.mercadoganadero.enums.UserRole;
import jakarta.persistence.*;
import java.time.OffsetDateTime;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.util.*;

@Entity
@Table(name = "users")
@Data // Genera getters, setters, toString, etc.
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "user_id")
    private Integer userId;

    @Column(name = "name", nullable = false, length = 100)
    private String name;

    @Column(name = "last_name", nullable = false, length = 200)
    private String lastName;

    @Column(name = "email", nullable = false, unique = true, length = 250)
    private String email;

    @Column(name = "phone_number", nullable = false, length = 50)
    private String phoneNumber;

    @Column(name = "password_hash", nullable = false, length = 255)
    private String passwordHash;

    @Column(name = "password_salt", nullable = false, length = 255)
    private String passwordSalt;

    @Column(name = "password_algorithm", length = 50)
    private String passwordAlgorithm = "bcrypt";

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at")
    private OffsetDateTime updatedAt;

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;

    @Column(name = "last_login")
    private OffsetDateTime lastLogin;

    @Column(name = "is_active")
    private Boolean isActive = true;

    @Column(name = "email_verified")
    private Boolean emailVerified = false;

    @Column(name = "tfa_enabled")
    private Boolean tfaEnabled = false;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "settings", nullable = false, columnDefinition = "jsonb")
    private Map<String, Object> settings;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "notification_preferences", columnDefinition = "jsonb")
    private Map<String, Object> notificationPreferences;

    // TODO: generar relaciones

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "user_roles", joinColumns = @JoinColumn(name = "user_id"))
    @Column(name = "role")
    @Enumerated(EnumType.STRING)
    @Builder.Default
    private Set<UserRole> roles = new HashSet<>();

    @Column(name = "user_type_id", nullable = false)
    private Integer userTypeId;

    @Column(name = "address_id", nullable = false)
    private Integer addressId;

    @Column(name = "subscription_plan_id", nullable = false)
    private Integer subscriptionPlanId;

    @Column(name = "password_reset_token")
    private String passwordResetToken;

    @Column(name = "password_reset_token_expiry_date")
    private OffsetDateTime passwordResetTokenExpiryDate;

    @Column(name = "email_verification_token")
    private String emailVerificationToken;

    @Column(name = "tfa_secret")
    private String tfaSecret;

    @Column(name = "email_verified_at")
    private OffsetDateTime emailVerifiedAt;

    @PrePersist
    protected void onCreate() {
        createdAt = OffsetDateTime.now();
        updatedAt = OffsetDateTime.now();

        // Inicializar Maps si son null
        if (settings == null) {
            settings = new HashMap<>();
        }
        if (notificationPreferences == null) {
            notificationPreferences = new HashMap<>();
        }

        // Si no tiene roles, asignar USER por defecto
        if (roles == null || roles.isEmpty()) {
            roles = new HashSet<>();
            roles.add(UserRole.USER);
        }
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = OffsetDateTime.now();
    }

    // Métodos de ayuda para roles
    public void addRole(UserRole role) {
        if (this.roles == null) {
            this.roles = new HashSet<>();
        }
        this.roles.add(role);
    }

    public void removeRole(UserRole role) {
        if (this.roles != null) {
            this.roles.remove(role);
        }
    }

    public boolean hasRole(UserRole role) {
        return this.roles != null && this.roles.contains(role);
    }

    public List<UserRole> getRolesList() {
        return this.roles != null ? new ArrayList<>(this.roles) : new ArrayList<>();
    }
}