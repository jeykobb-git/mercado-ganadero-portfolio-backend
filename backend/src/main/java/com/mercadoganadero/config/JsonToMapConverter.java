package com.mercadoganadero.config;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Conversor para campos JSONB de PostgreSQL.
 * Convierte Map<String, Object> a String JSON y viceversa.
 */
@Converter(autoApply = false)
public class JsonToMapConverter implements AttributeConverter<Map<String, Object>, String> {

    private static final Logger logger = LoggerFactory.getLogger(JsonToMapConverter.class);
    // ObjectMapper de Jackson para la serialización/deserialización
    private final static ObjectMapper objectMapper = new ObjectMapper();

    /**
     * Convierte el objeto Java (Map) en la representación JSON (String) para la DB.
     */
    @Override
    public String convertToDatabaseColumn(Map<String, Object> attribute) {
        if (attribute == null || attribute.isEmpty()) {
            return null;
        }

        try {
            return objectMapper.writeValueAsString(attribute);
        } catch (JsonProcessingException e) {
            logger.error("Error al convertir Map a JSON: " + e.getMessage());
            return "{}";
        }
    }

    /**
     * Convierte la representación JSON (String) de la DB en el objeto Java (Map).
     */
    @Override
    public Map<String, Object> convertToEntityAttribute(String dbData) {
        if (dbData == null || dbData.trim().isEmpty()) {
            return new HashMap<>();
        }

        try {
            return objectMapper.readValue(dbData, Map.class);
        } catch (IOException e) {
            logger.error("Error al convertir JSON a Map: " + e.getMessage());
            return new HashMap<>();
        }
    }
}