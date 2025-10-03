package com.mercadoganadero.entity;

import jakarta.persistence.*;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.util.Map;

/**
 * Representa la tabla user_types, con el campo settings como objeto Java.
 */
@Entity
@Table(name = "user_types")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class UserType {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "user_type_id")
    private Integer userTypeId;

    @Column(name = "short_name", nullable = false, length = 50)
    private String shortName;

    @Column(name = "full_name", length = 250)
    private String fullName;

    @Column(name = "description", length = 500)
    private String description;

    // APLICACIÓN DEL CONVERSOR
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "settings", nullable = false, columnDefinition = "jsonb")
    private Map<String, Object> settings;
}