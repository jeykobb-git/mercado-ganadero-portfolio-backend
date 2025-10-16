--
-- PostgreSQL database dump
--

\restrict FQ5TBuFGhufnIf1OFzodFCJ6T1MIybJJZSWTjLgsymTFsGli5dBTsrE0lH9JiaW

-- Dumped from database version 16.10 (Debian 16.10-1.pgdg13+1)
-- Dumped by pg_dump version 16.10 (Debian 16.10-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: calculate_seller_reputation_score(integer); Type: FUNCTION; Schema: public; Owner: devuser
--

CREATE FUNCTION public.calculate_seller_reputation_score(p_user_id integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    avg_rating NUMERIC(3,2);
    total_reviews INTEGER;
    mortality_rate NUMERIC(3,2);
    reputation_score NUMERIC(3,2);
BEGIN
    -- Promedio de calificaciones
    SELECT COALESCE(AVG(rating), 5.0), COUNT(*)
    INTO avg_rating, total_reviews
    FROM reviews 
    WHERE reviewed_user_id = p_user_id AND deleted_at IS NULL;
    
    -- Tasa de mortalidad reportada (últimos 12 meses)
    SELECT COALESCE(
        (COUNT(CASE WHEN amr.animal_id IS NOT NULL THEN 1 END)::NUMERIC / 
         NULLIF(COUNT(a.animal_id), 0)) * 100, 0.0)
    INTO mortality_rate
    FROM animals a
    LEFT JOIN animal_mortality_reports amr ON a.animal_id = amr.animal_id 
        AND amr.death_date >= NOW() - INTERVAL '12 months'
    WHERE a.user_id = p_user_id;
    
    -- Calcular score (0.0 a 5.0)
    reputation_score := (avg_rating * 0.7) + 
                       ((5.0 - LEAST(mortality_rate / 20.0, 5.0)) * 0.3);
    
    RETURN LEAST(reputation_score, 5.0);
END;
$$;


ALTER FUNCTION public.calculate_seller_reputation_score(p_user_id integer) OWNER TO devuser;

--
-- Name: FUNCTION calculate_seller_reputation_score(p_user_id integer); Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON FUNCTION public.calculate_seller_reputation_score(p_user_id integer) IS 'Calculates a comprehensive reputation score (0.0 to 5.0) for a seller based on average ratings and mortality rates. Uses weighted formula: 70% average rating + 30% inverse mortality impact';


--
-- Name: can_transport_animal_to_zone(integer, integer); Type: FUNCTION; Schema: public; Owner: devuser
--

CREATE FUNCTION public.can_transport_animal_to_zone(p_animal_id integer, p_destination_zone_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_origin_zone_id INTEGER;
    v_is_hlc_certified BOOLEAN;
    v_requires_hlc BOOLEAN;
    v_restriction_count INTEGER;
BEGIN
    -- Obtener información del animal
    SELECT 
        a_addr.sanitary_zone_id,
        a.is_hlc_certified
    INTO v_origin_zone_id, v_is_hlc_certified
    FROM animals a
    JOIN addresses a_addr ON a.address_id = a_addr.address_id
    WHERE a.animal_id = p_animal_id;
    
    -- Si no hay zona de origen definida, asumir que requiere HLC
    IF v_origin_zone_id IS NULL THEN
        RETURN v_is_hlc_certified;
    END IF;
    
    -- Verificar si hay restricciones de movilidad
    SELECT COUNT(*), BOOL_OR(requires_hlc)
    INTO v_restriction_count, v_requires_hlc
    FROM mobility_restrictions mr
    WHERE mr.origin_zone_id = v_origin_zone_id 
        AND mr.destination_zone_id = p_destination_zone_id
        AND mr.is_active = TRUE
        AND (mr.expiration_date IS NULL OR mr.expiration_date > NOW());
    
    -- Si no hay restricciones específicas, permitir movimiento
    IF v_restriction_count = 0 THEN
        RETURN TRUE;
    END IF;
    
    -- Si requiere HLC y el animal no lo tiene, no puede moverse
    IF v_requires_hlc AND NOT v_is_hlc_certified THEN
        RETURN FALSE;
    END IF;
    
    -- En otros casos, permitir movimiento
    RETURN TRUE;
END;
$$;


ALTER FUNCTION public.can_transport_animal_to_zone(p_animal_id integer, p_destination_zone_id integer) OWNER TO devuser;

--
-- Name: FUNCTION can_transport_animal_to_zone(p_animal_id integer, p_destination_zone_id integer); Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON FUNCTION public.can_transport_animal_to_zone(p_animal_id integer, p_destination_zone_id integer) IS 'Determines if an animal can be legally transported from its current location to a specified sanitary zone. Considers HLC certification requirements and mobility restrictions';


--
-- Name: get_allowed_zones_for_animal(integer); Type: FUNCTION; Schema: public; Owner: devuser
--

CREATE FUNCTION public.get_allowed_zones_for_animal(p_animal_id integer) RETURNS TABLE(zone_id integer, zone_name character varying, can_transport boolean)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        sz.sanitary_zone_id,
        sz.zone_name,
        can_transport_animal_to_zone(p_animal_id, sz.sanitary_zone_id) as can_transport
    FROM sanitary_zones sz
    WHERE sz.is_active = TRUE
        AND (sz.expiration_date IS NULL OR sz.expiration_date > NOW());
END;
$$;


ALTER FUNCTION public.get_allowed_zones_for_animal(p_animal_id integer) OWNER TO devuser;

--
-- Name: FUNCTION get_allowed_zones_for_animal(p_animal_id integer); Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON FUNCTION public.get_allowed_zones_for_animal(p_animal_id integer) IS 'Returns all active sanitary zones and indicates which ones allow transport for a specific animal based on mobility restrictions and HLC certification';


--
-- Name: get_available_publications_for_user(integer, integer); Type: FUNCTION; Schema: public; Owner: devuser
--

CREATE FUNCTION public.get_available_publications_for_user(p_user_id integer, p_user_zone_id integer DEFAULT NULL::integer) RETURNS TABLE(publication_id integer, animal_id integer, can_purchase boolean)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_user_zone_id INTEGER;
BEGIN
    -- Si no se proporciona zona, obtenerla del usuario
    IF p_user_zone_id IS NULL THEN
        SELECT addr.sanitary_zone_id 
        INTO v_user_zone_id
        FROM users u 
        JOIN addresses addr ON u.address_id = addr.address_id
        WHERE u.user_id = p_user_id;
    ELSE
        v_user_zone_id := p_user_zone_id;
    END IF;
    
    RETURN QUERY
    SELECT 
        p.publication_id,
        p.animal_id,
        CASE 
            WHEN v_user_zone_id IS NULL THEN TRUE -- Si no hay zona definida, mostrar todo
            WHEN can_transport_animal_to_zone(p.animal_id, v_user_zone_id) THEN TRUE
            ELSE FALSE
        END as can_purchase
    FROM publications p
    WHERE p.deleted_at IS NULL
        AND p.publication_status_id = (SELECT publication_status_id FROM publication_statuses WHERE short_name = 'active');
END;
$$;


ALTER FUNCTION public.get_available_publications_for_user(p_user_id integer, p_user_zone_id integer) OWNER TO devuser;

--
-- Name: FUNCTION get_available_publications_for_user(p_user_id integer, p_user_zone_id integer); Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON FUNCTION public.get_available_publications_for_user(p_user_id integer, p_user_zone_id integer) IS 'Returns all active publications that a user can potentially purchase, filtered by transport feasibility to their sanitary zone';


--
-- Name: soft_delete_record(text, integer, text); Type: FUNCTION; Schema: public; Owner: devuser
--

CREATE FUNCTION public.soft_delete_record(p_table_name text, p_record_id integer, p_id_column text DEFAULT 'id'::text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_sql TEXT;
BEGIN
    -- Construye dinámicamente el comando UPDATE
    v_sql := FORMAT(
        'UPDATE public.%I 
         SET deleted_at = NOW(), is_active = FALSE 
         WHERE %I = %L AND deleted_at IS NULL',
        p_table_name, -- La tabla a la que se aplica (ej. 'animals')
        p_id_column,  -- La columna ID de la tabla (ej. 'animal_id')
        p_record_id   -- El valor del ID (ej. 123)
    );

    -- Ejecuta el comando SQL dinámico
    EXECUTE v_sql;

    -- Retorna TRUE si se afectó alguna fila
    RETURN FOUND;
END;
$$;


ALTER FUNCTION public.soft_delete_record(p_table_name text, p_record_id integer, p_id_column text) OWNER TO devuser;

--
-- Name: FUNCTION soft_delete_record(p_table_name text, p_record_id integer, p_id_column text); Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON FUNCTION public.soft_delete_record(p_table_name text, p_record_id integer, p_id_column text) IS 'Generic utility function for performing soft deletes on any table that has deleted_at and is_active columns. Prevents actual data removal';


--
-- Name: update_animal_transport_capability(); Type: FUNCTION; Schema: public; Owner: devuser
--

CREATE FUNCTION public.update_animal_transport_capability() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.can_transport_nationwide := (NEW.hlc_certificate_id IS NOT NULL AND NEW.is_hlc_certified = TRUE);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_animal_transport_capability() OWNER TO devuser;

--
-- Name: FUNCTION update_animal_transport_capability(); Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON FUNCTION public.update_animal_transport_capability() IS 'Trigger function that automatically sets can_transport_nationwide flag based on HLC certification status and certificate validity';


--
-- Name: update_session_activity(); Type: FUNCTION; Schema: public; Owner: devuser
--

CREATE FUNCTION public.update_session_activity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.last_activity = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_session_activity() OWNER TO devuser;

--
-- Name: FUNCTION update_session_activity(); Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON FUNCTION public.update_session_activity() IS 'Trigger function that automatically updates the last_activity timestamp whenever a user session record is modified';


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: devuser
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at_column() OWNER TO devuser;

--
-- Name: FUNCTION update_updated_at_column(); Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON FUNCTION public.update_updated_at_column() IS 'Generic trigger function that automatically updates the updated_at timestamp whenever a record is modified. Used across multiple tables';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: users; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.users (
    user_id integer NOT NULL,
    name character varying(100) NOT NULL,
    last_name character varying(200) NOT NULL,
    email character varying(250) NOT NULL,
    phone_number character varying(50) NOT NULL,
    user_type_id integer NOT NULL,
    address_id integer NOT NULL,
    subscription_plan_id integer NOT NULL,
    password_hash character varying(255) NOT NULL,
    password_salt character varying(255) NOT NULL,
    password_algorithm character varying(50) DEFAULT 'argon2id'::character varying,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    last_login timestamp with time zone,
    is_active boolean DEFAULT true,
    email_verified boolean DEFAULT false,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    tfa_secret text,
    tfa_enabled boolean DEFAULT false,
    email_verification_token text,
    notification_preferences jsonb DEFAULT '{"sms": false, "push": true, "email": true}'::jsonb,
    password_reset_token text,
    password_reset_token_expiry_date timestamp with time zone,
    email_verified_at timestamp with time zone
);


ALTER TABLE public.users OWNER TO devuser;

--
-- Name: TABLE users; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.users IS 'Stores system users who can publish, buy, and manage livestock in the marketplace';


--
-- Name: COLUMN users.user_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.user_id IS 'Primary key of the user';


--
-- Name: COLUMN users.name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.name IS 'First name of the user';


--
-- Name: COLUMN users.last_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.last_name IS 'Last name of the user';


--
-- Name: COLUMN users.email; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.email IS 'Email of the user (must be unique)';


--
-- Name: COLUMN users.phone_number; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.phone_number IS 'Phone number of the user';


--
-- Name: COLUMN users.user_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.user_type_id IS 'Foreign key to user_types table';


--
-- Name: COLUMN users.address_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.address_id IS 'Foreign key to addresses table';


--
-- Name: COLUMN users.subscription_plan_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.subscription_plan_id IS 'Foreign key to subscription_plans table';


--
-- Name: COLUMN users.password_hash; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.password_hash IS 'Hashed password for the user (do NOT store plaintext passwords).';


--
-- Name: COLUMN users.password_salt; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.password_salt IS 'Salt used when hashing the user''s password (if applicable).';


--
-- Name: COLUMN users.password_algorithm; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.password_algorithm IS 'Name of the algorithm used to hash the user''s password (e.g., argon2id).';


--
-- Name: COLUMN users.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.created_at IS 'Timestamp when the user account was created.';


--
-- Name: COLUMN users.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.updated_at IS 'Timestamp of the last update to the user record.';


--
-- Name: COLUMN users.deleted_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.deleted_at IS 'Timestamp when the user account was soft-deleted (NULL if active).';


--
-- Name: COLUMN users.last_login; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.last_login IS 'Timestamp of the user''s last successful login.';


--
-- Name: COLUMN users.is_active; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.is_active IS 'Indicates whether the user account is active (can log in and interact).';


--
-- Name: COLUMN users.email_verified; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.email_verified IS 'Indicates whether the user''s email address has been verified.';


--
-- Name: COLUMN users.settings; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.settings IS 'Stores denormalized user-specific settings in JSONB format (e.g., language, theme, notification preferences).';


--
-- Name: COLUMN users.tfa_secret; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.tfa_secret IS 'Stores the secret key (TOTP) to generate 2FA codes.Stores the secret key (TOTP) to generate 2FA codes.';


--
-- Name: COLUMN users.tfa_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.tfa_enabled IS 'Indicates whether the user has configured and enabled 2FA.';


--
-- Name: COLUMN users.email_verification_token; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.email_verification_token IS 'Stores a single-use token to verify identity when registering or changing email addresses.';


--
-- Name: COLUMN users.notification_preferences; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.users.notification_preferences IS 'User''s preferences for receiving notifications, stored in JSONB.';


--
-- Name: active_users; Type: VIEW; Schema: public; Owner: devuser
--

CREATE VIEW public.active_users AS
 SELECT user_id,
    name,
    last_name,
    email,
    phone_number,
    user_type_id,
    address_id,
    subscription_plan_id,
    created_at,
    last_login,
    email_verified,
    settings
   FROM public.users t1
  WHERE ((deleted_at IS NULL) AND (is_active = true));


ALTER VIEW public.active_users OWNER TO devuser;

--
-- Name: VIEW active_users; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON VIEW public.active_users IS 'Provides a filtered list of all users who are currently active and not soft-deleted. Excludes sensitive data like password hashes and session tokens.';


--
-- Name: addresses; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.addresses (
    address_id integer NOT NULL,
    animal_pen character varying(50),
    ranch_name character varying(50),
    street character varying(250) NOT NULL,
    reference_notes character varying(500),
    postal_code_id integer NOT NULL,
    outside_number character varying(50) NOT NULL,
    inside_number character varying(50),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);


ALTER TABLE public.addresses OWNER TO devuser;

--
-- Name: TABLE addresses; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.addresses IS 'Stores physical addresses related to ranches, pens, and users';


--
-- Name: COLUMN addresses.address_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.addresses.address_id IS 'Primary key of the address';


--
-- Name: COLUMN addresses.animal_pen; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.addresses.animal_pen IS 'Animal pen name or identifier';


--
-- Name: COLUMN addresses.ranch_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.addresses.ranch_name IS 'Name of the ranch';


--
-- Name: COLUMN addresses.street; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.addresses.street IS 'Street name of the address';


--
-- Name: COLUMN addresses.reference_notes; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.addresses.reference_notes IS 'Additional reference notes for the address';


--
-- Name: COLUMN addresses.postal_code_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.addresses.postal_code_id IS 'Foreign key to postal_codes table';


--
-- Name: COLUMN addresses.outside_number; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.addresses.outside_number IS 'Outside (external) number of the address';


--
-- Name: COLUMN addresses.inside_number; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.addresses.inside_number IS 'Inside (internal) number of the address';


--
-- Name: COLUMN addresses.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.addresses.created_at IS 'Timestamp when the address record was created.';


--
-- Name: COLUMN addresses.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.addresses.updated_at IS 'Timestamp of the last update to the address record.';


--
-- Name: COLUMN addresses.deleted_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.addresses.deleted_at IS 'Timestamp when the address record was soft-deleted (NULL if active).';


--
-- Name: animal_health_statuses; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.animal_health_statuses (
    health_status_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.animal_health_statuses OWNER TO devuser;

--
-- Name: TABLE animal_health_statuses; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.animal_health_statuses IS 'Catalog of health statuses for animals.';


--
-- Name: COLUMN animal_health_statuses.health_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_health_statuses.health_status_id IS 'Unique identifier for the animal health status.';


--
-- Name: COLUMN animal_health_statuses.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_health_statuses.short_name IS 'Short, coded name for the status (e.g., "healthy"). Used for application logic.';


--
-- Name: COLUMN animal_health_statuses.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_health_statuses.full_name IS 'Full, descriptive name of the health status.';


--
-- Name: COLUMN animal_health_statuses.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_health_statuses.description IS 'Detailed description of the health status.';


--
-- Name: COLUMN animal_health_statuses.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_health_statuses.is_enabled IS 'If false, this status cannot be assigned to new records.';


--
-- Name: animal_health_statuses_health_status_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.animal_health_statuses ALTER COLUMN health_status_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.animal_health_statuses_health_status_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: animals; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.animals (
    animal_id integer NOT NULL,
    user_id integer NOT NULL,
    breed_id integer NOT NULL,
    gender_id integer NOT NULL,
    livestock_type_id integer NOT NULL,
    ear_tag character varying(100) NOT NULL,
    age integer NOT NULL,
    exact_weight numeric(8,2) NOT NULL,
    description text,
    health_certificate_url character varying(500),
    first_publication_date timestamp with time zone NOT NULL,
    address_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    approximate_lower_weight numeric(8,2),
    approximate_maximum_weight numeric(8,2),
    health_status_id integer,
    health_certificate_date timestamp with time zone,
    vaccination_records jsonb DEFAULT '[]'::jsonb,
    medical_notes text,
    hlc_certificate_id integer,
    is_hlc_certified boolean DEFAULT false,
    hlc_verification_date timestamp with time zone,
    mobility_restrictions jsonb DEFAULT '{}'::jsonb,
    can_transport_nationwide boolean DEFAULT false
);


ALTER TABLE public.animals OWNER TO devuser;

--
-- Name: TABLE animals; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.animals IS 'Stores animals listed in the marketplace';


--
-- Name: COLUMN animals.animal_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.animal_id IS 'Primary key of the animal';


--
-- Name: COLUMN animals.user_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.user_id IS 'Foreign key to users (owner of the animal)';


--
-- Name: COLUMN animals.breed_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.breed_id IS 'Foreign key to breeds table';


--
-- Name: COLUMN animals.gender_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.gender_id IS 'Foreign key to genders table';


--
-- Name: COLUMN animals.livestock_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.livestock_type_id IS 'Foreign key to livestock_types table';


--
-- Name: COLUMN animals.ear_tag; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.ear_tag IS 'Unique ear tag identifier of the animal per user';


--
-- Name: COLUMN animals.age; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.age IS 'Age of the animal in years';


--
-- Name: COLUMN animals.exact_weight; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.exact_weight IS 'Weight of the animal in kilograms';


--
-- Name: COLUMN animals.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.description IS 'Optional description of the animal';


--
-- Name: COLUMN animals.health_certificate_url; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.health_certificate_url IS 'URL to the health certificate document';


--
-- Name: COLUMN animals.first_publication_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.first_publication_date IS 'Date when the animal was published for first time on the marketplace';


--
-- Name: COLUMN animals.address_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.address_id IS 'Foreign key to addresses (location of the animal)';


--
-- Name: COLUMN animals.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.created_at IS 'Timestamp when the animal record was created.';


--
-- Name: COLUMN animals.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.updated_at IS 'Timestamp of the last update to the animal record.';


--
-- Name: COLUMN animals.deleted_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.deleted_at IS 'Timestamp when the animal record was soft-deleted (NULL if active).';


--
-- Name: COLUMN animals.approximate_lower_weight; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.approximate_lower_weight IS 'Lower bound of the animal''s estimated weight in kilograms.';


--
-- Name: COLUMN animals.approximate_maximum_weight; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.approximate_maximum_weight IS 'Upper bound of the animal''s estimated weight in kilograms.';


--
-- Name: COLUMN animals.health_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.health_status_id IS 'Foreign key to the current health status of the animal.';


--
-- Name: COLUMN animals.health_certificate_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.health_certificate_date IS 'Date of the last health certificate/exam.';


--
-- Name: COLUMN animals.vaccination_records; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.vaccination_records IS 'Record of vaccinations, stored as an array of JSON objects.';


--
-- Name: COLUMN animals.medical_notes; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.medical_notes IS 'General notes regarding the animal''s health history.';


--
-- Name: COLUMN animals.hlc_certificate_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.hlc_certificate_id IS 'Reference to the HLC certificate if the animal is certified';


--
-- Name: COLUMN animals.is_hlc_certified; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.is_hlc_certified IS 'Indicates if the animal comes from a certified free herd';


--
-- Name: COLUMN animals.hlc_verification_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.hlc_verification_date IS 'Date when the HLC certification for this animal was last verified or updated';


--
-- Name: COLUMN animals.mobility_restrictions; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.mobility_restrictions IS 'JSON object storing any specific mobility restrictions or requirements for this individual animal';


--
-- Name: COLUMN animals.can_transport_nationwide; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animals.can_transport_nationwide IS 'Computed field: true if animal can be transported nationwide';


--
-- Name: animal_id_animal_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.animals ALTER COLUMN animal_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.animal_id_animal_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: animal_mortality_reports; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.animal_mortality_reports (
    mortality_report_id integer NOT NULL,
    animal_id integer NOT NULL,
    death_date timestamp with time zone NOT NULL,
    death_cause_id integer,
    reported_by_user_id integer NOT NULL,
    report_date timestamp with time zone DEFAULT now() NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.animal_mortality_reports OWNER TO devuser;

--
-- Name: TABLE animal_mortality_reports; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.animal_mortality_reports IS 'Reports of animal deaths with cause and verification.';


--
-- Name: COLUMN animal_mortality_reports.mortality_report_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_mortality_reports.mortality_report_id IS 'Unique identifier for the mortality report.';


--
-- Name: COLUMN animal_mortality_reports.animal_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_mortality_reports.animal_id IS 'Foreign key to the animal that died.';


--
-- Name: COLUMN animal_mortality_reports.death_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_mortality_reports.death_date IS 'Exact date and time of death.';


--
-- Name: COLUMN animal_mortality_reports.death_cause_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_mortality_reports.death_cause_id IS 'Foreign key to the cause of death catalog.';


--
-- Name: COLUMN animal_mortality_reports.reported_by_user_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_mortality_reports.reported_by_user_id IS 'Foreign key to the user who created the report.';


--
-- Name: COLUMN animal_mortality_reports.report_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_mortality_reports.report_date IS 'Date the report was submitted.';


--
-- Name: COLUMN animal_mortality_reports.notes; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_mortality_reports.notes IS 'Additional notes or details about the death.';


--
-- Name: COLUMN animal_mortality_reports.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_mortality_reports.created_at IS 'Timestamp of record creation.';


--
-- Name: COLUMN animal_mortality_reports.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.animal_mortality_reports.updated_at IS 'Timestamp of last update.';


--
-- Name: animal_mortality_reports_mortality_report_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.animal_mortality_reports ALTER COLUMN mortality_report_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.animal_mortality_reports_mortality_report_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: app_config; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.app_config (
    config_key character varying(100) NOT NULL,
    config_value jsonb NOT NULL,
    description text,
    is_public boolean DEFAULT false,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by integer
);


ALTER TABLE public.app_config OWNER TO devuser;

--
-- Name: TABLE app_config; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.app_config IS 'Centralized table for managing application-wide configuration parameters.';


--
-- Name: COLUMN app_config.config_key; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.app_config.config_key IS 'Unique key identifying the configuration set (e.g., "email_settings").';


--
-- Name: COLUMN app_config.config_value; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.app_config.config_value IS 'The configuration data stored as a key-value JSONB structure.';


--
-- Name: COLUMN app_config.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.app_config.description IS 'Detailed description of what this configuration set manages.';


--
-- Name: COLUMN app_config.is_public; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.app_config.is_public IS 'Flag indicating if this configuration can be exposed to the client-side (frontend).';


--
-- Name: COLUMN app_config.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.app_config.updated_at IS 'Timestamp of the last modification.';


--
-- Name: COLUMN app_config.updated_by; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.app_config.updated_by IS 'Foreign key to the user who last updated this configuration.';


--
-- Name: audit_actions; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.audit_actions (
    audit_action_id integer NOT NULL,
    description character varying(500),
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.audit_actions OWNER TO devuser;

--
-- Name: TABLE audit_actions; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.audit_actions IS 'Catalog of possible audit actions performed by users in the system';


--
-- Name: COLUMN audit_actions.audit_action_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.audit_actions.audit_action_id IS 'Primary key of the audit action';


--
-- Name: COLUMN audit_actions.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.audit_actions.description IS 'Detailed description of the action';


--
-- Name: COLUMN audit_actions.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.audit_actions.short_name IS 'Short name of the action';


--
-- Name: COLUMN audit_actions.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.audit_actions.full_name IS 'Full name of the action';


--
-- Name: COLUMN audit_actions.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.audit_actions.is_enabled IS 'If false, this action cannot be used in new logs.';


--
-- Name: breeds; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.breeds (
    breed_id integer NOT NULL,
    species_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(100),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.breeds OWNER TO devuser;

--
-- Name: TABLE breeds; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.breeds IS 'Catalog of animal breeds grouped by species';


--
-- Name: COLUMN breeds.breed_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.breeds.breed_id IS 'Primary key of the breed';


--
-- Name: COLUMN breeds.species_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.breeds.species_id IS 'Foreign key to species table';


--
-- Name: COLUMN breeds.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.breeds.short_name IS 'Short name of the breed';


--
-- Name: COLUMN breeds.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.breeds.full_name IS 'Full name of the breed';


--
-- Name: COLUMN breeds.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.breeds.description IS 'Optional description of the breed';


--
-- Name: COLUMN breeds.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.breeds.is_enabled IS 'If false, this breed cannot be selected for new animals.';


--
-- Name: entity_types; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.entity_types (
    entity_type_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.entity_types OWNER TO devuser;

--
-- Name: TABLE entity_types; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.entity_types IS 'Defines the types of entities that can be linked to multimedia files (e.g., animals, users, publications)';


--
-- Name: COLUMN entity_types.entity_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.entity_types.entity_type_id IS 'Primary key of the entity type';


--
-- Name: COLUMN entity_types.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.entity_types.short_name IS 'Short name of the entity type';


--
-- Name: COLUMN entity_types.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.entity_types.full_name IS 'Full descriptive name of the entity type';


--
-- Name: COLUMN entity_types.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.entity_types.description IS 'Optional description of the entity type';


--
-- Name: COLUMN entity_types.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.entity_types.is_enabled IS 'If false, this entity type cannot be used.';


--
-- Name: cat__tipo_entidad_id_tipo_entidad_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.entity_types ALTER COLUMN entity_type_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.cat__tipo_entidad_id_tipo_entidad_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cat_acciones_historial_id_accion_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.audit_actions ALTER COLUMN audit_action_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.cat_acciones_historial_id_accion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.subscription_plans (
    subscription_plan_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    description character varying(500),
    monthly_fee numeric(10,2) DEFAULT 0 NOT NULL,
    annual_fee numeric(10,2) DEFAULT 0 NOT NULL,
    max_publications numeric(5,0) DEFAULT 0 NOT NULL,
    full_name character varying(250),
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.subscription_plans OWNER TO devuser;

--
-- Name: TABLE subscription_plans; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.subscription_plans IS 'Catalog of subscription plans available for users';


--
-- Name: COLUMN subscription_plans.subscription_plan_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.subscription_plans.subscription_plan_id IS 'Primary key of the subscription plan';


--
-- Name: COLUMN subscription_plans.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.subscription_plans.short_name IS 'Short name of the subscription plan';


--
-- Name: COLUMN subscription_plans.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.subscription_plans.description IS 'Description of the subscription plan';


--
-- Name: COLUMN subscription_plans.monthly_fee; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.subscription_plans.monthly_fee IS 'Monthly subscription fee';


--
-- Name: COLUMN subscription_plans.annual_fee; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.subscription_plans.annual_fee IS 'Annual subscription fee';


--
-- Name: COLUMN subscription_plans.max_publications; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.subscription_plans.max_publications IS 'Maximum number of publications allowed under this plan';


--
-- Name: COLUMN subscription_plans.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.subscription_plans.full_name IS 'Full name of the subscription plan';


--
-- Name: COLUMN subscription_plans.settings; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.subscription_plans.settings IS 'Stores plan-specific settings and limits in JSONB format (e.g., storage capacity, max animal entries, special features).';


--
-- Name: COLUMN subscription_plans.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.subscription_plans.is_enabled IS 'If false, this subscription plan is not available for new users.';


--
-- Name: cat_paquete_id_paquete_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.subscription_plans ALTER COLUMN subscription_plan_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.cat_paquete_id_paquete_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: neighborhoods; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.neighborhoods (
    neighborhood_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    municipality_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);


ALTER TABLE public.neighborhoods OWNER TO devuser;

--
-- Name: TABLE neighborhoods; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.neighborhoods IS 'Catalog of neighborhoods linked to municipalities';


--
-- Name: COLUMN neighborhoods.neighborhood_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.neighborhoods.neighborhood_id IS 'Primary key of the neighborhood';


--
-- Name: COLUMN neighborhoods.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.neighborhoods.short_name IS 'Short name of the neighborhood';


--
-- Name: COLUMN neighborhoods.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.neighborhoods.full_name IS 'Full name of the neighborhood';


--
-- Name: COLUMN neighborhoods.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.neighborhoods.description IS 'Optional description of the neighborhood';


--
-- Name: COLUMN neighborhoods.municipality_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.neighborhoods.municipality_id IS 'Foreign key to municipalities table';


--
-- Name: COLUMN neighborhoods.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.neighborhoods.created_at IS 'Timestamp when the neighborhood record was created.';


--
-- Name: COLUMN neighborhoods.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.neighborhoods.updated_at IS 'Timestamp of the last update to the neighborhood record.';


--
-- Name: COLUMN neighborhoods.deleted_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.neighborhoods.deleted_at IS 'Timestamp when the neighborhood record was soft-deleted (NULL if active).';


--
-- Name: catcolonia_id_colonia_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.neighborhoods ALTER COLUMN neighborhood_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.catcolonia_id_colonia_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: municipalities; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.municipalities (
    municipality_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    state_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);


ALTER TABLE public.municipalities OWNER TO devuser;

--
-- Name: TABLE municipalities; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.municipalities IS 'Catalog of municipalities linked to states';


--
-- Name: COLUMN municipalities.municipality_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.municipalities.municipality_id IS 'Primary key of the municipality';


--
-- Name: COLUMN municipalities.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.municipalities.short_name IS 'Short name of the municipality';


--
-- Name: COLUMN municipalities.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.municipalities.full_name IS 'Full name of the municipality';


--
-- Name: COLUMN municipalities.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.municipalities.description IS 'Optional description of the municipality';


--
-- Name: COLUMN municipalities.state_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.municipalities.state_id IS 'Foreign key to states table';


--
-- Name: COLUMN municipalities.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.municipalities.created_at IS 'Timestamp when the municipality record was created.';


--
-- Name: COLUMN municipalities.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.municipalities.updated_at IS 'Timestamp of the last update to the municipality record.';


--
-- Name: COLUMN municipalities.deleted_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.municipalities.deleted_at IS 'Timestamp when the municipality record was soft-deleted (NULL if active).';


--
-- Name: catmunicipio_id_municipio_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.municipalities ALTER COLUMN municipality_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.catmunicipio_id_municipio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: countries; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.countries (
    country_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.countries OWNER TO devuser;

--
-- Name: TABLE countries; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.countries IS 'Catalog of countries';


--
-- Name: COLUMN countries.country_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.countries.country_id IS 'Primary key of the country';


--
-- Name: COLUMN countries.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.countries.short_name IS 'Short name of the country';


--
-- Name: COLUMN countries.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.countries.full_name IS 'Full name of the country';


--
-- Name: COLUMN countries.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.countries.is_enabled IS 'If false, this country cannot be selected in addresses.';


--
-- Name: catpais_id_pais_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.countries ALTER COLUMN country_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.catpais_id_pais_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: death_causes; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.death_causes (
    death_cause_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.death_causes OWNER TO devuser;

--
-- Name: TABLE death_causes; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.death_causes IS 'Catalog of possible causes of death for animals.';


--
-- Name: COLUMN death_causes.death_cause_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.death_causes.death_cause_id IS 'Unique identifier for the cause of death.';


--
-- Name: COLUMN death_causes.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.death_causes.short_name IS 'Short, coded name for the cause (e.g., "natural", "disease"). Used for application logic.';


--
-- Name: COLUMN death_causes.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.death_causes.full_name IS 'Full, descriptive name of the cause of death.';


--
-- Name: COLUMN death_causes.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.death_causes.description IS 'Detailed description of the cause of death.';


--
-- Name: COLUMN death_causes.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.death_causes.is_enabled IS 'If false, this cause of death cannot be selected.';


--
-- Name: death_causes_death_cause_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.death_causes ALTER COLUMN death_cause_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.death_causes_death_cause_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: delivery_statuses; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.delivery_statuses (
    delivery_status_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.delivery_statuses OWNER TO devuser;

--
-- Name: TABLE delivery_statuses; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.delivery_statuses IS 'Catalog of possible delivery statuses for sales';


--
-- Name: COLUMN delivery_statuses.delivery_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.delivery_statuses.delivery_status_id IS 'Primary key of the delivery status';


--
-- Name: COLUMN delivery_statuses.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.delivery_statuses.short_name IS 'Short name of the delivery status';


--
-- Name: COLUMN delivery_statuses.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.delivery_statuses.full_name IS 'Full name of the delivery status';


--
-- Name: COLUMN delivery_statuses.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.delivery_statuses.description IS 'Optional description of the delivery status';


--
-- Name: COLUMN delivery_statuses.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.delivery_statuses.is_enabled IS 'If false, this delivery status cannot be used.';


--
-- Name: domicilio_animal_id_domicilio_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.addresses ALTER COLUMN address_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.domicilio_animal_id_domicilio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: postal_codes; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.postal_codes (
    postal_code_id integer NOT NULL,
    postal_code integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    municipality_id integer NOT NULL
);


ALTER TABLE public.postal_codes OWNER TO devuser;

--
-- Name: TABLE postal_codes; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.postal_codes IS 'Catalog of postal codes linked to neighborhoods';


--
-- Name: COLUMN postal_codes.postal_code_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.postal_codes.postal_code_id IS 'Primary key of the postal code';


--
-- Name: COLUMN postal_codes.postal_code; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.postal_codes.postal_code IS 'Postal code value';


--
-- Name: COLUMN postal_codes.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.postal_codes.created_at IS 'Timestamp when the postal code record was created.';


--
-- Name: COLUMN postal_codes.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.postal_codes.updated_at IS 'Timestamp of the last update to the postal code record.';


--
-- Name: COLUMN postal_codes.deleted_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.postal_codes.deleted_at IS 'Timestamp when the postal code record was soft-deleted (NULL if active).';


--
-- Name: COLUMN postal_codes.municipality_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.postal_codes.municipality_id IS 'Foreign key to municipalities table';


--
-- Name: domicilio_id_domicilio_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.postal_codes ALTER COLUMN postal_code_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.domicilio_id_domicilio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: escrow_statuses; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.escrow_statuses (
    escrow_status_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.escrow_statuses OWNER TO devuser;

--
-- Name: TABLE escrow_statuses; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.escrow_statuses IS 'Catalog of statuses for secure/escrow payments.';


--
-- Name: COLUMN escrow_statuses.escrow_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.escrow_statuses.escrow_status_id IS 'Unique identifier for the escrow status.';


--
-- Name: COLUMN escrow_statuses.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.escrow_statuses.short_name IS 'Short, coded name for the status (e.g., "held", "released").';


--
-- Name: COLUMN escrow_statuses.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.escrow_statuses.full_name IS 'Full, descriptive name of the escrow status.';


--
-- Name: COLUMN escrow_statuses.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.escrow_statuses.description IS 'Detailed description of the escrow status.';


--
-- Name: COLUMN escrow_statuses.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.escrow_statuses.is_enabled IS 'If false, this escrow status cannot be used.';


--
-- Name: escrow_statuses_escrow_status_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.escrow_statuses ALTER COLUMN escrow_status_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.escrow_statuses_escrow_status_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: species; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.species (
    species_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.species OWNER TO devuser;

--
-- Name: TABLE species; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.species IS 'Catalog of animal species (e.g., cattle, pigs, goats)';


--
-- Name: COLUMN species.species_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.species.species_id IS 'Primary key of the species';


--
-- Name: COLUMN species.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.species.short_name IS 'Short name of the species';


--
-- Name: COLUMN species.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.species.full_name IS 'Full name of the species';


--
-- Name: COLUMN species.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.species.description IS 'Optional description of the species';


--
-- Name: COLUMN species.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.species.is_enabled IS 'If false, this species cannot be selected for new animals.';


--
-- Name: especie_id_especie_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.species ALTER COLUMN species_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.especie_id_especie_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: estado_entrega_id_estado_entrega_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.delivery_statuses ALTER COLUMN delivery_status_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.estado_entrega_id_estado_entrega_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: states; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.states (
    state_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    country_id integer NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.states OWNER TO devuser;

--
-- Name: TABLE states; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.states IS 'Catalog of states linked to countries';


--
-- Name: COLUMN states.state_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.states.state_id IS 'Primary key of the state';


--
-- Name: COLUMN states.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.states.short_name IS 'Short name of the state';


--
-- Name: COLUMN states.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.states.full_name IS 'Full name of the state';


--
-- Name: COLUMN states.country_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.states.country_id IS 'Foreign key to countries table';


--
-- Name: COLUMN states.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.states.is_enabled IS 'If false, this state is not available for selection.';


--
-- Name: estado_id_estado_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.states ALTER COLUMN state_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.estado_id_estado_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: offer_statuses; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.offer_statuses (
    offer_status_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.offer_statuses OWNER TO devuser;

--
-- Name: TABLE offer_statuses; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.offer_statuses IS 'Catalog of possible statuses for purchase offers';


--
-- Name: COLUMN offer_statuses.offer_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offer_statuses.offer_status_id IS 'Primary key of the offer status';


--
-- Name: COLUMN offer_statuses.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offer_statuses.short_name IS 'Short name of the offer status';


--
-- Name: COLUMN offer_statuses.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offer_statuses.full_name IS 'Full name of the offer status';


--
-- Name: COLUMN offer_statuses.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offer_statuses.description IS 'Optional description of the offer status';


--
-- Name: COLUMN offer_statuses.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offer_statuses.is_enabled IS 'If false, this offer status cannot be used.';


--
-- Name: estado_oferta_id_estado_oferta_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.offer_statuses ALTER COLUMN offer_status_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.estado_oferta_id_estado_oferta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sale_statuses; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.sale_statuses (
    sale_status_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.sale_statuses OWNER TO devuser;

--
-- Name: TABLE sale_statuses; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.sale_statuses IS 'Catalog of possible statuses for sales transactions';


--
-- Name: COLUMN sale_statuses.sale_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sale_statuses.sale_status_id IS 'Primary key of the sale status';


--
-- Name: COLUMN sale_statuses.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sale_statuses.short_name IS 'Short name of the sale status';


--
-- Name: COLUMN sale_statuses.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sale_statuses.full_name IS 'Full name of the sale status';


--
-- Name: COLUMN sale_statuses.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sale_statuses.description IS 'Optional description of the sale status';


--
-- Name: COLUMN sale_statuses.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sale_statuses.is_enabled IS 'If false, this sale status cannot be used.';


--
-- Name: estado_venta_id_estado_venta_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.sale_statuses ALTER COLUMN sale_status_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.estado_venta_id_estado_venta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: file_types; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.file_types (
    file_type_id integer NOT NULL,
    description character varying(500),
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    file_extension character varying(50) NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.file_types OWNER TO devuser;

--
-- Name: TABLE file_types; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.file_types IS 'Catalog of file types allowed in the system';


--
-- Name: COLUMN file_types.file_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.file_types.file_type_id IS 'Primary key of the file type';


--
-- Name: COLUMN file_types.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.file_types.description IS 'Description of the file type';


--
-- Name: COLUMN file_types.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.file_types.short_name IS 'Short name of the file type';


--
-- Name: COLUMN file_types.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.file_types.full_name IS 'Full name of the file type';


--
-- Name: COLUMN file_types.file_extension; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.file_types.file_extension IS 'File extension (e.g., .jpg, .pdf)';


--
-- Name: COLUMN file_types.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.file_types.is_enabled IS 'If false, this file type cannot be used for uploads.';


--
-- Name: genders; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.genders (
    gender_id integer NOT NULL,
    description character varying(50) NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.genders OWNER TO devuser;

--
-- Name: TABLE genders; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.genders IS 'Catalog of genders for animals';


--
-- Name: COLUMN genders.gender_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.genders.gender_id IS 'Primary key of the gender';


--
-- Name: COLUMN genders.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.genders.description IS 'Description of the gender (e.g., male, female)';


--
-- Name: COLUMN genders.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.genders.is_enabled IS 'If false, this gender cannot be selected for new animals.';


--
-- Name: hlc_certificates; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.hlc_certificates (
    hlc_certificate_id integer NOT NULL,
    user_id integer NOT NULL,
    ranch_address_id integer NOT NULL,
    certificate_number character varying(100) NOT NULL,
    certificate_type character varying(50) NOT NULL,
    issued_date timestamp with time zone NOT NULL,
    expiration_date timestamp with time zone NOT NULL,
    is_active boolean DEFAULT true,
    senasica_office character varying(200),
    veterinary_officer character varying(200),
    last_inspection_date timestamp with time zone,
    next_inspection_date timestamp with time zone,
    total_animals_certified integer DEFAULT 0,
    certificate_url character varying(500),
    status character varying(50) DEFAULT 'active'::character varying,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.hlc_certificates OWNER TO devuser;

--
-- Name: TABLE hlc_certificates; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.hlc_certificates IS 'Free herd certificates (Hato Libre Certificado) issued by SENASICA';


--
-- Name: COLUMN hlc_certificates.certificate_type; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.hlc_certificates.certificate_type IS 'Type of HLC certificate (e.g., "tuberculosis_free", "brucellosis_free", "dual_certification")';


--
-- Name: COLUMN hlc_certificates.senasica_office; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.hlc_certificates.senasica_office IS 'Name of the SENASICA office that issued this certificate';


--
-- Name: COLUMN hlc_certificates.veterinary_officer; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.hlc_certificates.veterinary_officer IS 'Name of the veterinary officer who signed or authorized this certificate';


--
-- Name: COLUMN hlc_certificates.last_inspection_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.hlc_certificates.last_inspection_date IS 'Date of the most recent inspection that validated this certificate';


--
-- Name: COLUMN hlc_certificates.next_inspection_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.hlc_certificates.next_inspection_date IS 'Scheduled date for the next required inspection to maintain certification';


--
-- Name: COLUMN hlc_certificates.total_animals_certified; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.hlc_certificates.total_animals_certified IS 'Total number of animals currently covered under this HLC certificate';


--
-- Name: COLUMN hlc_certificates.certificate_url; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.hlc_certificates.certificate_url IS 'URL or path to the digital copy of the official certificate document';


--
-- Name: COLUMN hlc_certificates.status; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.hlc_certificates.status IS 'Current status of the certificate (active, expired, suspended, revoked)';


--
-- Name: COLUMN hlc_certificates.notes; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.hlc_certificates.notes IS 'Additional notes or observations related to this certificate';


--
-- Name: hlc_certificates_hlc_certificate_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.hlc_certificates ALTER COLUMN hlc_certificate_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.hlc_certificates_hlc_certificate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: livestock_types; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.livestock_types (
    livestock_type_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.livestock_types OWNER TO devuser;

--
-- Name: TABLE livestock_types; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.livestock_types IS 'Catalog of livestock types (e.g., dairy cattle, beef cattle)';


--
-- Name: COLUMN livestock_types.livestock_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.livestock_types.livestock_type_id IS 'Primary key of the livestock type';


--
-- Name: COLUMN livestock_types.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.livestock_types.short_name IS 'Short name of the livestock type';


--
-- Name: COLUMN livestock_types.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.livestock_types.full_name IS 'Full name of the livestock type';


--
-- Name: COLUMN livestock_types.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.livestock_types.description IS 'Optional description of the livestock type';


--
-- Name: COLUMN livestock_types.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.livestock_types.is_enabled IS 'If false, this type cannot be selected for new animals.';


--
-- Name: mobility_restrictions; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.mobility_restrictions (
    restriction_id integer NOT NULL,
    origin_zone_id integer NOT NULL,
    destination_zone_id integer NOT NULL,
    requires_hlc boolean DEFAULT true,
    requires_additional_tests boolean DEFAULT false,
    restriction_type character varying(50) NOT NULL,
    additional_requirements jsonb DEFAULT '{}'::jsonb,
    effective_date timestamp with time zone NOT NULL,
    expiration_date timestamp with time zone,
    is_active boolean DEFAULT true,
    senasica_reference character varying(100),
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.mobility_restrictions OWNER TO devuser;

--
-- Name: TABLE mobility_restrictions; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.mobility_restrictions IS 'Movement restrictions between sanitary zones';


--
-- Name: COLUMN mobility_restrictions.requires_additional_tests; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.mobility_restrictions.requires_additional_tests IS 'Indicates if additional veterinary tests are required beyond HLC certification';


--
-- Name: COLUMN mobility_restrictions.restriction_type; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.mobility_restrictions.restriction_type IS 'Type of restriction applied (e.g., "quarantine", "testing_required", "hlc_mandatory")';


--
-- Name: COLUMN mobility_restrictions.additional_requirements; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.mobility_restrictions.additional_requirements IS 'JSON object storing any additional requirements specific to this restriction';


--
-- Name: COLUMN mobility_restrictions.senasica_reference; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.mobility_restrictions.senasica_reference IS 'Official SENASICA document or regulation number that establishes this restriction';


--
-- Name: COLUMN mobility_restrictions.notes; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.mobility_restrictions.notes IS 'Additional details or context about this mobility restriction';


--
-- Name: mobility_restrictions_restriction_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.mobility_restrictions ALTER COLUMN restriction_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.mobility_restrictions_restriction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: multimedia; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.multimedia (
    multimedia_id integer NOT NULL,
    file_type_id integer NOT NULL,
    file_url character varying(1000) NOT NULL,
    file_path character varying(500) NOT NULL,
    file_size_bytes integer NOT NULL,
    original_name character varying(250) NOT NULL,
    mime_type character varying(100) NOT NULL,
    entity_type_id integer NOT NULL,
    entity_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    width integer,
    height integer,
    is_primary boolean DEFAULT false,
    alt_text character varying(255)
);


ALTER TABLE public.multimedia OWNER TO devuser;

--
-- Name: TABLE multimedia; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.multimedia IS 'Stores multimedia files uploaded to the system, linked to different entities';


--
-- Name: COLUMN multimedia.multimedia_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.multimedia_id IS 'Primary key of the multimedia record';


--
-- Name: COLUMN multimedia.file_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.file_type_id IS 'Foreign key to file_types table';


--
-- Name: COLUMN multimedia.file_url; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.file_url IS 'Public URL to access the file';


--
-- Name: COLUMN multimedia.file_path; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.file_path IS 'Internal storage path of the file';


--
-- Name: COLUMN multimedia.file_size_bytes; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.file_size_bytes IS 'File size in bytes';


--
-- Name: COLUMN multimedia.original_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.original_name IS 'Original name of the uploaded file';


--
-- Name: COLUMN multimedia.mime_type; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.mime_type IS 'MIME type of the file';


--
-- Name: COLUMN multimedia.entity_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.entity_type_id IS 'Foreign key to entity_types (what type of entity this file belongs to)';


--
-- Name: COLUMN multimedia.entity_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.entity_id IS 'Identifier of the linked entity';


--
-- Name: COLUMN multimedia.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.created_at IS 'Timestamp when the multimedia record was created.';


--
-- Name: COLUMN multimedia.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.updated_at IS 'Timestamp of the last update to the multimedia record.';


--
-- Name: COLUMN multimedia.deleted_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.deleted_at IS 'Timestamp when the multimedia record was soft-deleted (NULL if active).';


--
-- Name: COLUMN multimedia.width; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.width IS 'Width of the media in pixels (for images/videos) if applicable.';


--
-- Name: COLUMN multimedia.height; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.height IS 'Height of the media in pixels (for images/videos) if applicable.';


--
-- Name: COLUMN multimedia.is_primary; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.is_primary IS 'Flag indicating if this media is the primary (main) file for the associated entity.';


--
-- Name: COLUMN multimedia.alt_text; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.multimedia.alt_text IS 'Alternative text for the multimedia file, used for accessibility and SEO.';


--
-- Name: multimedia_id_multimedia_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.multimedia ALTER COLUMN multimedia_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.multimedia_id_multimedia_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: offers; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.offers (
    offer_id integer NOT NULL,
    publication_id integer NOT NULL,
    user_id integer NOT NULL,
    offer_status_id integer NOT NULL,
    amount_offered numeric(10,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);


ALTER TABLE public.offers OWNER TO devuser;

--
-- Name: TABLE offers; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.offers IS 'Stores purchase offers made by users for published animals';


--
-- Name: COLUMN offers.offer_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offers.offer_id IS 'Primary key of the offer';


--
-- Name: COLUMN offers.publication_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offers.publication_id IS 'Foreign key to publications table';


--
-- Name: COLUMN offers.user_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offers.user_id IS 'Foreign key to users table (buyer)';


--
-- Name: COLUMN offers.offer_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offers.offer_status_id IS 'Foreign key to offer_statuses table';


--
-- Name: COLUMN offers.amount_offered; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offers.amount_offered IS 'Amount offered by the user';


--
-- Name: COLUMN offers.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offers.created_at IS 'Timestamp when the offer record was created.';


--
-- Name: COLUMN offers.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offers.updated_at IS 'Timestamp of the last update to the offer record.';


--
-- Name: COLUMN offers.deleted_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.offers.deleted_at IS 'Timestamp when the offer record was soft-deleted (NULL if active).';


--
-- Name: oferta_id_oferta_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.offers ALTER COLUMN offer_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.oferta_id_oferta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: payment_methods; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.payment_methods (
    payment_method_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.payment_methods OWNER TO devuser;

--
-- Name: TABLE payment_methods; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.payment_methods IS 'Catalog of payment methods available to users.';


--
-- Name: COLUMN payment_methods.payment_method_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_methods.payment_method_id IS 'Unique identifier for the payment method.';


--
-- Name: COLUMN payment_methods.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_methods.short_name IS 'Short, coded name for the method (e.g., "card", "bank_transfer").';


--
-- Name: COLUMN payment_methods.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_methods.full_name IS 'Full, descriptive name of the payment method.';


--
-- Name: COLUMN payment_methods.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_methods.description IS 'Detailed description of the payment method.';


--
-- Name: COLUMN payment_methods.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_methods.is_enabled IS 'If false, this payment method is not available.';


--
-- Name: payment_methods_payment_method_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.payment_methods ALTER COLUMN payment_method_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.payment_methods_payment_method_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: payment_providers; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.payment_providers (
    payment_provider_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.payment_providers OWNER TO devuser;

--
-- Name: TABLE payment_providers; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.payment_providers IS 'Catalog of payment gateway providers (e.g., Stripe, PayPal).';


--
-- Name: COLUMN payment_providers.payment_provider_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_providers.payment_provider_id IS 'Unique identifier for the payment provider (gateway).';


--
-- Name: COLUMN payment_providers.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_providers.short_name IS 'Short, coded name for the provider (e.g., "stripe", "paypal").';


--
-- Name: COLUMN payment_providers.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_providers.full_name IS 'Full, descriptive name of the payment provider.';


--
-- Name: COLUMN payment_providers.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_providers.description IS 'Detailed description of the payment provider.';


--
-- Name: COLUMN payment_providers.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_providers.is_enabled IS 'If false, this payment provider is not available.';


--
-- Name: payment_providers_payment_provider_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.payment_providers ALTER COLUMN payment_provider_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.payment_providers_payment_provider_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: payment_statuses; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.payment_statuses (
    payment_status_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.payment_statuses OWNER TO devuser;

--
-- Name: TABLE payment_statuses; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.payment_statuses IS 'Catalog of possible payment statuses for transactions (e.g., pending, completed, failed).';


--
-- Name: COLUMN payment_statuses.payment_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_statuses.payment_status_id IS 'Primary key of the payment status';


--
-- Name: COLUMN payment_statuses.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_statuses.short_name IS 'Short code/name of the payment status (e.g., "pending", "completed")';


--
-- Name: COLUMN payment_statuses.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_statuses.full_name IS 'Full descriptive name of the payment status';


--
-- Name: COLUMN payment_statuses.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_statuses.description IS 'Optional description or notes about the payment status';


--
-- Name: COLUMN payment_statuses.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.payment_statuses.is_enabled IS 'If false, this payment status cannot be used.';


--
-- Name: payment_statuses_payment_status_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.payment_statuses ALTER COLUMN payment_status_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.payment_statuses_payment_status_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: postal_code_neighborhoods; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.postal_code_neighborhoods (
    postal_code_neighborhood_id integer NOT NULL,
    postal_code_id integer NOT NULL,
    neighborhood_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.postal_code_neighborhoods OWNER TO devuser;

--
-- Name: COLUMN postal_code_neighborhoods.postal_code_neighborhood_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.postal_code_neighborhoods.postal_code_neighborhood_id IS 'Primary key for this junction table. It automatically generates a unique, sequential integer ID.';


--
-- Name: COLUMN postal_code_neighborhoods.postal_code_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.postal_code_neighborhoods.postal_code_id IS 'Foreign key referencing the ''postal_codes'' table. It links to the specific postal code.';


--
-- Name: COLUMN postal_code_neighborhoods.neighborhood_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.postal_code_neighborhoods.neighborhood_id IS 'Foreign key referencing the ''neighborhoods'' table. It links to the specific neighborhood (or ''colonia'').Foreign key referencing the ''neighborhoods'' table. It links to the specific neighborhood (or ''colonia'').';


--
-- Name: COLUMN postal_code_neighborhoods.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.postal_code_neighborhoods.created_at IS 'Timestamp (with timezone) recording when this specific relationship was created.';


--
-- Name: postal_code_neighborhoods_postal_code_neighborhood_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

CREATE SEQUENCE public.postal_code_neighborhoods_postal_code_neighborhood_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.postal_code_neighborhoods_postal_code_neighborhood_id_seq OWNER TO devuser;

--
-- Name: postal_code_neighborhoods_postal_code_neighborhood_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: devuser
--

ALTER SEQUENCE public.postal_code_neighborhoods_postal_code_neighborhood_id_seq OWNED BY public.postal_code_neighborhoods.postal_code_neighborhood_id;


--
-- Name: promotion_types; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.promotion_types (
    promotion_type_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.promotion_types OWNER TO devuser;

--
-- Name: TABLE promotion_types; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.promotion_types IS 'Catalog of available promotion types for publications.';


--
-- Name: COLUMN promotion_types.promotion_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.promotion_types.promotion_type_id IS 'Unique identifier for the promotion type.';


--
-- Name: COLUMN promotion_types.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.promotion_types.short_name IS 'Short, coded name for the promotion (e.g., "featured").';


--
-- Name: COLUMN promotion_types.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.promotion_types.full_name IS 'Full, descriptive name of the promotion type.';


--
-- Name: COLUMN promotion_types.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.promotion_types.description IS 'Detailed description of the promotion type.';


--
-- Name: COLUMN promotion_types.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.promotion_types.is_enabled IS 'If false, this promotion type is not available.';


--
-- Name: promotion_types_promotion_type_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.promotion_types ALTER COLUMN promotion_type_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.promotion_types_promotion_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: publications; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.publications (
    publication_id integer NOT NULL,
    animal_id integer NOT NULL,
    publication_type_id integer NOT NULL,
    transport_responsible_user_id integer NOT NULL,
    price numeric(10,2) NOT NULL,
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone NOT NULL,
    additional_description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    publication_status_id integer NOT NULL,
    geographic_reach_km integer DEFAULT 50,
    promotion_score numeric(5,2) DEFAULT 0.0,
    hlc_required boolean DEFAULT false,
    restricted_zones jsonb DEFAULT '[]'::jsonb,
    allowed_zones jsonb DEFAULT '[]'::jsonb
);


ALTER TABLE public.publications OWNER TO devuser;

--
-- Name: TABLE publications; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.publications IS 'Stores animal sale/rental publications in the marketplace';


--
-- Name: COLUMN publications.publication_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.publication_id IS 'Primary key of the publication';


--
-- Name: COLUMN publications.animal_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.animal_id IS 'Foreign key to animals table';


--
-- Name: COLUMN publications.publication_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.publication_type_id IS 'Foreign key to publication_types table';


--
-- Name: COLUMN publications.transport_responsible_user_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.transport_responsible_user_id IS 'Foreign key to users table (responsible for transport)';


--
-- Name: COLUMN publications.price; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.price IS 'Price assigned to the publication';


--
-- Name: COLUMN publications.start_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.start_date IS 'Start date of the publication';


--
-- Name: COLUMN publications.end_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.end_date IS 'End date of the publication';


--
-- Name: COLUMN publications.additional_description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.additional_description IS 'Additional description of the publication';


--
-- Name: COLUMN publications.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.created_at IS 'Timestamp when the publication record was created.';


--
-- Name: COLUMN publications.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.updated_at IS 'Timestamp of the last update to the publication record.';


--
-- Name: COLUMN publications.deleted_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.deleted_at IS 'Timestamp when the publication record was soft-deleted (NULL if active).';


--
-- Name: COLUMN publications.publication_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.publication_status_id IS 'Foreign key to publication_statuses table';


--
-- Name: COLUMN publications.geographic_reach_km; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.geographic_reach_km IS 'Radius in kilometers where the publication is visible.';


--
-- Name: COLUMN publications.promotion_score; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.promotion_score IS 'Dynamic score used to rank and order publications based on promotions.';


--
-- Name: COLUMN publications.hlc_required; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.hlc_required IS 'Indicates whether buyers must have HLC certification to purchase this animal';


--
-- Name: COLUMN publications.restricted_zones; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.restricted_zones IS 'JSON array of sanitary zone IDs where this publication is not available due to restrictions';


--
-- Name: COLUMN publications.allowed_zones; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publications.allowed_zones IS 'JSON array of sanitary zone IDs where this publication is specifically allowed (overrides general restrictions)';


--
-- Name: publicacion_id_publicacion_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.publications ALTER COLUMN publication_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.publicacion_id_publicacion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: publication_municipalities; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.publication_municipalities (
    publication_id integer NOT NULL,
    municipality_id integer NOT NULL,
    municipality_publication_id integer NOT NULL
);


ALTER TABLE public.publication_municipalities OWNER TO devuser;

--
-- Name: TABLE publication_municipalities; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.publication_municipalities IS 'Links publications to the municipalities where they are available';


--
-- Name: COLUMN publication_municipalities.publication_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_municipalities.publication_id IS 'Foreign key to publications table';


--
-- Name: COLUMN publication_municipalities.municipality_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_municipalities.municipality_id IS 'Foreign key to municipalities table';


--
-- Name: COLUMN publication_municipalities.municipality_publication_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_municipalities.municipality_publication_id IS 'Primary key of the municipality-publication relation';


--
-- Name: publicacion_municipio_id_publicacion_municipio_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.publication_municipalities ALTER COLUMN municipality_publication_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.publicacion_municipio_id_publicacion_municipio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: publication_promotions; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.publication_promotions (
    promotion_id integer NOT NULL,
    publication_id integer NOT NULL,
    promotion_type_id integer NOT NULL,
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone NOT NULL,
    amount_paid numeric(10,2) NOT NULL,
    boost_multiplier numeric(3,2) DEFAULT 1.0,
    geographic_radius_km integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT true
);


ALTER TABLE public.publication_promotions OWNER TO devuser;

--
-- Name: TABLE publication_promotions; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.publication_promotions IS 'Paid promotions to boost publication visibility.';


--
-- Name: COLUMN publication_promotions.promotion_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_promotions.promotion_id IS 'Unique identifier for the promotion instance.';


--
-- Name: COLUMN publication_promotions.publication_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_promotions.publication_id IS 'Foreign key to the publication being promoted.';


--
-- Name: COLUMN publication_promotions.promotion_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_promotions.promotion_type_id IS 'Foreign key to the type of promotion being applied.';


--
-- Name: COLUMN publication_promotions.start_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_promotions.start_date IS 'Date and time the promotion starts.';


--
-- Name: COLUMN publication_promotions.end_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_promotions.end_date IS 'Date and time the promotion ends.';


--
-- Name: COLUMN publication_promotions.amount_paid; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_promotions.amount_paid IS 'Amount paid by the user for this promotion.';


--
-- Name: COLUMN publication_promotions.boost_multiplier; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_promotions.boost_multiplier IS 'Factor by which visibility is multiplied (e.g., 1.5x).';


--
-- Name: COLUMN publication_promotions.geographic_radius_km; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_promotions.geographic_radius_km IS 'Additional geographic radius granted by the promotion.';


--
-- Name: COLUMN publication_promotions.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_promotions.created_at IS 'Timestamp of record creation.';


--
-- Name: COLUMN publication_promotions.is_active; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_promotions.is_active IS 'Indicates if the promotion is currently running.';


--
-- Name: publication_promotions_promotion_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.publication_promotions ALTER COLUMN promotion_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.publication_promotions_promotion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: publication_statuses; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.publication_statuses (
    publication_status_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.publication_statuses OWNER TO devuser;

--
-- Name: TABLE publication_statuses; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.publication_statuses IS 'Catalog of possible statuses for publications (e.g., active, expired, sold, suspended)';


--
-- Name: COLUMN publication_statuses.publication_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_statuses.publication_status_id IS 'Primary key of the publication status';


--
-- Name: COLUMN publication_statuses.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_statuses.short_name IS 'Short coded name for the status used in application logic';


--
-- Name: COLUMN publication_statuses.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_statuses.full_name IS 'Full descriptive name of the publication status';


--
-- Name: COLUMN publication_statuses.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_statuses.description IS 'Detailed description of what this status represents';


--
-- Name: COLUMN publication_statuses.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_statuses.is_enabled IS 'If false, this publication status cannot be used.';


--
-- Name: publication_statuses_publication_status_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.publication_statuses ALTER COLUMN publication_status_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.publication_statuses_publication_status_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: publication_types; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.publication_types (
    publication_type_id integer NOT NULL,
    description character varying(50) NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.publication_types OWNER TO devuser;

--
-- Name: TABLE publication_types; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.publication_types IS 'Catalog of publication types (e.g., sale, auction, rental)';


--
-- Name: COLUMN publication_types.publication_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_types.publication_type_id IS 'Primary key of the publication type';


--
-- Name: COLUMN publication_types.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_types.description IS 'Description of the publication type';


--
-- Name: COLUMN publication_types.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.publication_types.is_enabled IS 'If false, this publication type is not available.';


--
-- Name: raza_id_raza_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.breeds ALTER COLUMN breed_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.raza_id_raza_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_tokens; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.refresh_tokens (
    id bigint NOT NULL,
    token character varying(500) NOT NULL,
    user_id integer NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    replaced_by_token character varying(500),
    ip_address character varying(45),
    user_agent character varying(500)
);


ALTER TABLE public.refresh_tokens OWNER TO devuser;

--
-- Name: TABLE refresh_tokens; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.refresh_tokens IS 'Refresh tokens to renew access without re-authentication';


--
-- Name: COLUMN refresh_tokens.token; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.refresh_tokens.token IS 'Unique UUID token to refresh the access token';


--
-- Name: COLUMN refresh_tokens.revoked_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.refresh_tokens.revoked_at IS 'Manual revocation date (logout or suspected theft)';


--
-- Name: COLUMN refresh_tokens.replaced_by_token; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.refresh_tokens.replaced_by_token IS 'Token that replaced this one (to detect reuse)';


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

CREATE SEQUENCE public.refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.refresh_tokens_id_seq OWNER TO devuser;

--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: devuser
--

ALTER SEQUENCE public.refresh_tokens_id_seq OWNED BY public.refresh_tokens.id;


--
-- Name: report_types; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.report_types (
    report_type_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.report_types OWNER TO devuser;

--
-- Name: TABLE report_types; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.report_types IS 'Catalog of types of automated seller reports (e.g., mortality rate).';


--
-- Name: COLUMN report_types.report_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.report_types.report_type_id IS 'Unique identifier for the report type.';


--
-- Name: COLUMN report_types.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.report_types.short_name IS 'Short, coded name for the report type (e.g., "mortality_rate").';


--
-- Name: COLUMN report_types.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.report_types.full_name IS 'Full, descriptive name of the report type.';


--
-- Name: COLUMN report_types.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.report_types.description IS 'Detailed description of the report type.';


--
-- Name: COLUMN report_types.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.report_types.is_enabled IS 'If false, this report type is disabled.';


--
-- Name: report_types_report_type_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.report_types ALTER COLUMN report_type_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.report_types_report_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: review_types; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.review_types (
    review_type_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.review_types OWNER TO devuser;

--
-- Name: TABLE review_types; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.review_types IS 'Catalog of types of reviews (e.g., Seller review, Animal review).';


--
-- Name: COLUMN review_types.review_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.review_types.review_type_id IS 'Unique identifier for the review type.';


--
-- Name: COLUMN review_types.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.review_types.short_name IS 'Short, coded name for the review type (e.g., "seller", "animal").';


--
-- Name: COLUMN review_types.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.review_types.full_name IS 'Full, descriptive name of the review type.';


--
-- Name: COLUMN review_types.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.review_types.description IS 'Detailed description of the review type.';


--
-- Name: COLUMN review_types.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.review_types.is_enabled IS 'If false, this review type is disabled.';


--
-- Name: review_types_review_type_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.review_types ALTER COLUMN review_type_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.review_types_review_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reviews; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.reviews (
    review_id integer NOT NULL,
    reviewer_user_id integer NOT NULL,
    reviewed_user_id integer NOT NULL,
    animal_id integer,
    sale_id integer,
    rating integer NOT NULL,
    title character varying(200),
    comment text,
    review_type_id integer NOT NULL,
    is_verified_purchase boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);


ALTER TABLE public.reviews OWNER TO devuser;

--
-- Name: TABLE reviews; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.reviews IS 'Reviews and ratings for sellers and animals.';


--
-- Name: COLUMN reviews.review_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.review_id IS 'Unique identifier for the review.';


--
-- Name: COLUMN reviews.reviewer_user_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.reviewer_user_id IS 'Foreign key to the user who wrote the review.';


--
-- Name: COLUMN reviews.reviewed_user_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.reviewed_user_id IS 'Foreign key to the user (seller) being reviewed.';


--
-- Name: COLUMN reviews.animal_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.animal_id IS 'Optional foreign key to a specific animal being reviewed.';


--
-- Name: COLUMN reviews.sale_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.sale_id IS 'Optional foreign key to the associated sale transaction.';


--
-- Name: COLUMN reviews.rating; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.rating IS 'The score given (1 to 5).';


--
-- Name: COLUMN reviews.title; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.title IS 'Short title for the review.';


--
-- Name: COLUMN reviews.comment; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.comment IS 'Detailed text of the review.';


--
-- Name: COLUMN reviews.review_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.review_type_id IS 'Foreign key to the type of review (seller, animal, transaction).';


--
-- Name: COLUMN reviews.is_verified_purchase; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.is_verified_purchase IS 'Indicates if the review is linked to a confirmed sale.';


--
-- Name: COLUMN reviews.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.created_at IS 'Timestamp of record creation.';


--
-- Name: COLUMN reviews.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.updated_at IS 'Timestamp of last update.';


--
-- Name: COLUMN reviews.deleted_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.reviews.deleted_at IS 'Timestamp of soft deletion.';


--
-- Name: CONSTRAINT reviews_rating_check ON reviews; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON CONSTRAINT reviews_rating_check ON public.reviews IS 'Ensures review ratings are within valid range (1 to 5 stars)';


--
-- Name: reviews_review_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.reviews ALTER COLUMN review_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.reviews_review_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sales; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.sales (
    sale_id integer NOT NULL,
    sale_status_id integer NOT NULL,
    offer_id integer NOT NULL,
    delivery_status_id integer NOT NULL,
    delivery_date timestamp with time zone NOT NULL,
    sale_date timestamp with time zone NOT NULL,
    shipping_amount_paid numeric(8,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    subtotal numeric(10,2) DEFAULT 0.00 NOT NULL,
    tax_amount numeric(10,2) DEFAULT 0.00 NOT NULL,
    commission_amount numeric(8,2) DEFAULT 0.00 NOT NULL,
    total_amount numeric(12,2) NOT NULL,
    payment_status_id integer NOT NULL
);


ALTER TABLE public.sales OWNER TO devuser;

--
-- Name: TABLE sales; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.sales IS 'Stores completed sales transactions for animals';


--
-- Name: COLUMN sales.sale_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.sale_id IS 'Primary key of the sale';


--
-- Name: COLUMN sales.sale_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.sale_status_id IS 'Foreign key to sale_statuses table';


--
-- Name: COLUMN sales.offer_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.offer_id IS 'Foreign key to offers table';


--
-- Name: COLUMN sales.delivery_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.delivery_status_id IS 'Foreign key to delivery_statuses table';


--
-- Name: COLUMN sales.delivery_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.delivery_date IS 'Date when the delivery took place';


--
-- Name: COLUMN sales.sale_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.sale_date IS 'Date when the sale was confirmed';


--
-- Name: COLUMN sales.shipping_amount_paid; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.shipping_amount_paid IS 'Amount paid for shipping/delivery';


--
-- Name: COLUMN sales.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.created_at IS 'Timestamp when the sale record was created.';


--
-- Name: COLUMN sales.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.updated_at IS 'Timestamp of the last update to the sale record.';


--
-- Name: COLUMN sales.deleted_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.deleted_at IS 'Timestamp when the sale record was soft-deleted (NULL if active).';


--
-- Name: COLUMN sales.subtotal; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.subtotal IS 'Price of goods/animals before taxes or commissions.';


--
-- Name: COLUMN sales.tax_amount; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.tax_amount IS 'Total amount of tax applied to the transaction.';


--
-- Name: COLUMN sales.commission_amount; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.commission_amount IS 'Platform commission amount charged for the sale.';


--
-- Name: COLUMN sales.total_amount; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.total_amount IS 'The final total amount paid by the buyer.';


--
-- Name: COLUMN sales.payment_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.sales.payment_status_id IS 'Foreign key to the current payment status from the payment_statuses catalog.';


--
-- Name: saved_searches; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.saved_searches (
    saved_search_id integer NOT NULL,
    user_id integer NOT NULL,
    search_name character varying(100) NOT NULL,
    search_criteria jsonb NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_notification_sent timestamp with time zone
);


ALTER TABLE public.saved_searches OWNER TO devuser;

--
-- Name: TABLE saved_searches; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.saved_searches IS 'User-defined search alerts for real-time notifications.';


--
-- Name: COLUMN saved_searches.saved_search_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.saved_searches.saved_search_id IS 'Unique identifier for the saved search.';


--
-- Name: COLUMN saved_searches.user_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.saved_searches.user_id IS 'Foreign key to the user who saved the search.';


--
-- Name: COLUMN saved_searches.search_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.saved_searches.search_name IS 'Name given to the search by the user.';


--
-- Name: COLUMN saved_searches.search_criteria; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.saved_searches.search_criteria IS 'The actual search criteria stored in JSONB format.';


--
-- Name: COLUMN saved_searches.is_active; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.saved_searches.is_active IS 'Indicates if the search alert is currently running.';


--
-- Name: COLUMN saved_searches.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.saved_searches.created_at IS 'Timestamp of record creation.';


--
-- Name: COLUMN saved_searches.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.saved_searches.updated_at IS 'Timestamp of last update.';


--
-- Name: COLUMN saved_searches.last_notification_sent; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.saved_searches.last_notification_sent IS 'Timestamp when the last notification for this search was sent.';


--
-- Name: saved_searches_saved_search_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.saved_searches ALTER COLUMN saved_search_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.saved_searches_saved_search_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: search_notifications; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.search_notifications (
    notification_id integer NOT NULL,
    saved_search_id integer NOT NULL,
    publication_id integer NOT NULL,
    sent_at timestamp with time zone DEFAULT now() NOT NULL,
    was_read boolean DEFAULT false,
    read_at timestamp with time zone
);


ALTER TABLE public.search_notifications OWNER TO devuser;

--
-- Name: TABLE search_notifications; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.search_notifications IS 'Notifications sent when saved searches match new publications.';


--
-- Name: COLUMN search_notifications.notification_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.search_notifications.notification_id IS 'Unique identifier for the notification.';


--
-- Name: COLUMN search_notifications.saved_search_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.search_notifications.saved_search_id IS 'Foreign key to the saved search that triggered the notification.';


--
-- Name: COLUMN search_notifications.publication_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.search_notifications.publication_id IS 'Foreign key to the matching publication.';


--
-- Name: COLUMN search_notifications.sent_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.search_notifications.sent_at IS 'Timestamp when the notification was generated/sent.';


--
-- Name: COLUMN search_notifications.was_read; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.search_notifications.was_read IS 'Flag indicating if the user has read the notification.';


--
-- Name: COLUMN search_notifications.read_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.search_notifications.read_at IS 'Timestamp when the user read the notification.';


--
-- Name: search_notifications_notification_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.search_notifications ALTER COLUMN notification_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.search_notifications_notification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: secure_payments; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.secure_payments (
    secure_payment_id integer NOT NULL,
    offer_id integer NOT NULL,
    payment_amount numeric(10,2) NOT NULL,
    payment_method_id integer NOT NULL,
    payment_provider_id integer NOT NULL,
    payment_intent_id character varying(255),
    escrow_status_id integer NOT NULL,
    inspection_deadline timestamp with time zone,
    buyer_approval boolean DEFAULT false,
    rejection_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.secure_payments OWNER TO devuser;

--
-- Name: TABLE secure_payments; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.secure_payments IS 'Escrow payments for secure transactions with inspection period.';


--
-- Name: COLUMN secure_payments.secure_payment_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.secure_payment_id IS 'Unique identifier for the secure payment/escrow transaction.';


--
-- Name: COLUMN secure_payments.offer_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.offer_id IS 'Foreign key to the offer associated with the payment.';


--
-- Name: COLUMN secure_payments.payment_amount; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.payment_amount IS 'The total amount of the payment/escrow.';


--
-- Name: COLUMN secure_payments.payment_method_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.payment_method_id IS 'Foreign key to the payment method used.';


--
-- Name: COLUMN secure_payments.payment_provider_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.payment_provider_id IS 'Foreign key to the payment gateway used.';


--
-- Name: COLUMN secure_payments.payment_intent_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.payment_intent_id IS 'ID of the transaction provided by the payment gateway (e.g., Stripe Intent ID).';


--
-- Name: COLUMN secure_payments.escrow_status_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.escrow_status_id IS 'Current status of the funds in escrow.';


--
-- Name: COLUMN secure_payments.inspection_deadline; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.inspection_deadline IS 'Date and time until the buyer can inspect the animal/goods.';


--
-- Name: COLUMN secure_payments.buyer_approval; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.buyer_approval IS 'Flag indicating if the buyer has approved the payment release from escrow.';


--
-- Name: COLUMN secure_payments.rejection_reason; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.rejection_reason IS 'Reason provided if the payment/goods were rejected by the buyer.';


--
-- Name: COLUMN secure_payments.created_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.created_at IS 'Timestamp of record creation.';


--
-- Name: COLUMN secure_payments.updated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.secure_payments.updated_at IS 'Timestamp of last update.';


--
-- Name: secure_payments_secure_payment_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.secure_payments ALTER COLUMN secure_payment_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.secure_payments_secure_payment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: seller_reports; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.seller_reports (
    report_id integer NOT NULL,
    seller_user_id integer NOT NULL,
    report_type_id integer NOT NULL,
    report_data jsonb NOT NULL,
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    report_period_start timestamp with time zone NOT NULL,
    report_period_end timestamp with time zone NOT NULL,
    severity_score numeric(3,1),
    is_flagged boolean DEFAULT false
);


ALTER TABLE public.seller_reports OWNER TO devuser;

--
-- Name: TABLE seller_reports; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.seller_reports IS 'Automated reports tracking seller performance and issues.';


--
-- Name: COLUMN seller_reports.report_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.seller_reports.report_id IS 'Unique identifier for the seller report.';


--
-- Name: COLUMN seller_reports.seller_user_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.seller_reports.seller_user_id IS 'Foreign key to the seller user being reported.';


--
-- Name: COLUMN seller_reports.report_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.seller_reports.report_type_id IS 'Foreign key to the type of report generated.';


--
-- Name: COLUMN seller_reports.report_data; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.seller_reports.report_data IS 'Detailed data used to generate the report, in JSONB.';


--
-- Name: COLUMN seller_reports.generated_at; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.seller_reports.generated_at IS 'Timestamp when the report was automatically generated.';


--
-- Name: COLUMN seller_reports.report_period_start; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.seller_reports.report_period_start IS 'Start date of the data analysis period.';


--
-- Name: COLUMN seller_reports.report_period_end; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.seller_reports.report_period_end IS 'End date of the data analysis period.';


--
-- Name: COLUMN seller_reports.severity_score; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.seller_reports.severity_score IS 'Calculated score indicating the severity of the issue (0.0 to 10.0).';


--
-- Name: COLUMN seller_reports.is_flagged; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.seller_reports.is_flagged IS 'Flag indicating if the report requires manual review.';


--
-- Name: seller_reports_report_id_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.seller_reports ALTER COLUMN report_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.seller_reports_report_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sexo_id_sexo_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.genders ALTER COLUMN gender_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sexo_id_sexo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipo_archivo_id_tipo_archivo_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.file_types ALTER COLUMN file_type_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tipo_archivo_id_tipo_archivo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipo_ganado_id_tipo_ganado_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.livestock_types ALTER COLUMN livestock_type_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tipo_ganado_id_tipo_ganado_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tipo_publicacion_id_tipo_publicacion_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.publication_types ALTER COLUMN publication_type_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tipo_publicacion_id_tipo_publicacion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: user_types; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.user_types (
    user_type_id integer NOT NULL,
    short_name character varying(50) NOT NULL,
    full_name character varying(250),
    description character varying(500),
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE public.user_types OWNER TO devuser;

--
-- Name: TABLE user_types; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.user_types IS 'Catalog of user types (e.g., buyer, seller, admin)';


--
-- Name: COLUMN user_types.user_type_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.user_types.user_type_id IS 'Primary key of the user type';


--
-- Name: COLUMN user_types.short_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.user_types.short_name IS 'Short name of the user type';


--
-- Name: COLUMN user_types.full_name; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.user_types.full_name IS 'Full name of the user type';


--
-- Name: COLUMN user_types.description; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.user_types.description IS 'Optional description of the user type';


--
-- Name: COLUMN user_types.settings; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.user_types.settings IS 'Stores role-specific settings and permissions in JSONB format (e.g., max publications allowed, feature access).';


--
-- Name: COLUMN user_types.is_enabled; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.user_types.is_enabled IS 'If false, this user type cannot be assigned.';


--
-- Name: tipo_usuario_id_tipo_usuario_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.user_types ALTER COLUMN user_type_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tipo_usuario_id_tipo_usuario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: user_audit_logs; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.user_audit_logs (
    audit_action_log_id integer NOT NULL,
    audit_action_id integer NOT NULL,
    registration_date timestamp with time zone DEFAULT now() NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.user_audit_logs OWNER TO devuser;

--
-- Name: TABLE user_audit_logs; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.user_audit_logs IS 'Stores the history of actions performed by users for auditing purposes';


--
-- Name: COLUMN user_audit_logs.audit_action_log_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.user_audit_logs.audit_action_log_id IS 'Primary key of the audit log record';


--
-- Name: COLUMN user_audit_logs.audit_action_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.user_audit_logs.audit_action_id IS 'Foreign key to audit_actions table';


--
-- Name: COLUMN user_audit_logs.registration_date; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.user_audit_logs.registration_date IS 'Date and time when the action was registered';


--
-- Name: COLUMN user_audit_logs.user_id; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.user_audit_logs.user_id IS 'Foreign key to users table (user who performed the action)';


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: devuser
--

CREATE TABLE public.user_roles (
    user_id integer NOT NULL,
    role character varying(50) NOT NULL
);


ALTER TABLE public.user_roles OWNER TO devuser;

--
-- Name: TABLE user_roles; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TABLE public.user_roles IS 'Stores roles assigned to each user for granular authorization.';


--
-- Name: COLUMN user_roles.role; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON COLUMN public.user_roles.role IS 'User role from the UserRole enum: USER, ADMIN, SELLER, BUYER, MODERATOR';


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.users ALTER COLUMN user_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.usuario_id_usuario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: usuariohistorial_id_historial_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.user_audit_logs ALTER COLUMN audit_action_log_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.usuariohistorial_id_historial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: venta_id_venta_seq; Type: SEQUENCE; Schema: public; Owner: devuser
--

ALTER TABLE public.sales ALTER COLUMN sale_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.venta_id_venta_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: postal_code_neighborhoods postal_code_neighborhood_id; Type: DEFAULT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.postal_code_neighborhoods ALTER COLUMN postal_code_neighborhood_id SET DEFAULT nextval('public.postal_code_neighborhoods_postal_code_neighborhood_id_seq'::regclass);


--
-- Name: refresh_tokens id; Type: DEFAULT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.refresh_tokens ALTER COLUMN id SET DEFAULT nextval('public.refresh_tokens_id_seq'::regclass);


--
-- Name: app_config app_config_pkey; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.app_config
    ADD CONSTRAINT app_config_pkey PRIMARY KEY (config_key);


--
-- Name: hlc_certificates hlc_certificates_certificate_number_key; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.hlc_certificates
    ADD CONSTRAINT hlc_certificates_certificate_number_key UNIQUE (certificate_number);


--
-- Name: addresses pk_addresses; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.addresses
    ADD CONSTRAINT pk_addresses PRIMARY KEY (address_id);


--
-- Name: animals pk_animal; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT pk_animal PRIMARY KEY (animal_id);


--
-- Name: animal_health_statuses pk_animal_health_statuses; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animal_health_statuses
    ADD CONSTRAINT pk_animal_health_statuses PRIMARY KEY (health_status_id);


--
-- Name: animal_mortality_reports pk_animal_mortality_reports; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animal_mortality_reports
    ADD CONSTRAINT pk_animal_mortality_reports PRIMARY KEY (mortality_report_id);


--
-- Name: audit_actions pk_audit_actions; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.audit_actions
    ADD CONSTRAINT pk_audit_actions PRIMARY KEY (audit_action_id);


--
-- Name: breeds pk_breeds; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.breeds
    ADD CONSTRAINT pk_breeds PRIMARY KEY (breed_id);


--
-- Name: countries pk_countries; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT pk_countries PRIMARY KEY (country_id);


--
-- Name: death_causes pk_death_causes; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.death_causes
    ADD CONSTRAINT pk_death_causes PRIMARY KEY (death_cause_id);


--
-- Name: delivery_statuses pk_delivery_statuses; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.delivery_statuses
    ADD CONSTRAINT pk_delivery_statuses PRIMARY KEY (delivery_status_id);


--
-- Name: entity_types pk_entity_types; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.entity_types
    ADD CONSTRAINT pk_entity_types PRIMARY KEY (entity_type_id);


--
-- Name: escrow_statuses pk_escrow_statuses; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.escrow_statuses
    ADD CONSTRAINT pk_escrow_statuses PRIMARY KEY (escrow_status_id);


--
-- Name: file_types pk_file_types; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.file_types
    ADD CONSTRAINT pk_file_types PRIMARY KEY (file_type_id);


--
-- Name: genders pk_genders; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.genders
    ADD CONSTRAINT pk_genders PRIMARY KEY (gender_id);


--
-- Name: hlc_certificates pk_hlc_certificates; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.hlc_certificates
    ADD CONSTRAINT pk_hlc_certificates PRIMARY KEY (hlc_certificate_id);


--
-- Name: livestock_types pk_livestock_types; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.livestock_types
    ADD CONSTRAINT pk_livestock_types PRIMARY KEY (livestock_type_id);


--
-- Name: mobility_restrictions pk_mobility_restrictions; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.mobility_restrictions
    ADD CONSTRAINT pk_mobility_restrictions PRIMARY KEY (restriction_id);


--
-- Name: multimedia pk_multimedia; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.multimedia
    ADD CONSTRAINT pk_multimedia PRIMARY KEY (multimedia_id);


--
-- Name: municipalities pk_municipalities; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.municipalities
    ADD CONSTRAINT pk_municipalities PRIMARY KEY (municipality_id);


--
-- Name: neighborhoods pk_neighborhoods; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.neighborhoods
    ADD CONSTRAINT pk_neighborhoods PRIMARY KEY (neighborhood_id);


--
-- Name: offer_statuses pk_offer_statuses; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.offer_statuses
    ADD CONSTRAINT pk_offer_statuses PRIMARY KEY (offer_status_id);


--
-- Name: offers pk_offers; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.offers
    ADD CONSTRAINT pk_offers PRIMARY KEY (offer_id);


--
-- Name: payment_methods pk_payment_methods; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.payment_methods
    ADD CONSTRAINT pk_payment_methods PRIMARY KEY (payment_method_id);


--
-- Name: payment_providers pk_payment_providers; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.payment_providers
    ADD CONSTRAINT pk_payment_providers PRIMARY KEY (payment_provider_id);


--
-- Name: payment_statuses pk_payment_statuses; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.payment_statuses
    ADD CONSTRAINT pk_payment_statuses PRIMARY KEY (payment_status_id);


--
-- Name: postal_codes pk_postal_codes; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.postal_codes
    ADD CONSTRAINT pk_postal_codes PRIMARY KEY (postal_code_id);


--
-- Name: promotion_types pk_promotion_types; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.promotion_types
    ADD CONSTRAINT pk_promotion_types PRIMARY KEY (promotion_type_id);


--
-- Name: publication_municipalities pk_publication_municipalities; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publication_municipalities
    ADD CONSTRAINT pk_publication_municipalities PRIMARY KEY (municipality_publication_id);


--
-- Name: publication_promotions pk_publication_promotions; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publication_promotions
    ADD CONSTRAINT pk_publication_promotions PRIMARY KEY (promotion_id);


--
-- Name: publication_types pk_publication_types; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publication_types
    ADD CONSTRAINT pk_publication_types PRIMARY KEY (publication_type_id);


--
-- Name: publications pk_publications; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publications
    ADD CONSTRAINT pk_publications PRIMARY KEY (publication_id);


--
-- Name: report_types pk_report_types; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.report_types
    ADD CONSTRAINT pk_report_types PRIMARY KEY (report_type_id);


--
-- Name: review_types pk_review_types; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.review_types
    ADD CONSTRAINT pk_review_types PRIMARY KEY (review_type_id);


--
-- Name: reviews pk_reviews; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT pk_reviews PRIMARY KEY (review_id);


--
-- Name: sale_statuses pk_sale_statuses; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.sale_statuses
    ADD CONSTRAINT pk_sale_statuses PRIMARY KEY (sale_status_id);


--
-- Name: sales pk_sales; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT pk_sales PRIMARY KEY (sale_id);


--
-- Name: saved_searches pk_saved_searches; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.saved_searches
    ADD CONSTRAINT pk_saved_searches PRIMARY KEY (saved_search_id);


--
-- Name: search_notifications pk_search_notifications; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.search_notifications
    ADD CONSTRAINT pk_search_notifications PRIMARY KEY (notification_id);


--
-- Name: secure_payments pk_secure_payments; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.secure_payments
    ADD CONSTRAINT pk_secure_payments PRIMARY KEY (secure_payment_id);


--
-- Name: seller_reports pk_seller_reports; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.seller_reports
    ADD CONSTRAINT pk_seller_reports PRIMARY KEY (report_id);


--
-- Name: species pk_species; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.species
    ADD CONSTRAINT pk_species PRIMARY KEY (species_id);


--
-- Name: states pk_states; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.states
    ADD CONSTRAINT pk_states PRIMARY KEY (state_id);


--
-- Name: subscription_plans pk_subscription_plans; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT pk_subscription_plans PRIMARY KEY (subscription_plan_id);


--
-- Name: user_audit_logs pk_user_audit_logs; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.user_audit_logs
    ADD CONSTRAINT pk_user_audit_logs PRIMARY KEY (audit_action_log_id);


--
-- Name: user_types pk_user_types; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.user_types
    ADD CONSTRAINT pk_user_types PRIMARY KEY (user_type_id);


--
-- Name: users pk_users; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT pk_users PRIMARY KEY (user_id);


--
-- Name: postal_code_neighborhoods postal_code_neighborhoods_pkey; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.postal_code_neighborhoods
    ADD CONSTRAINT postal_code_neighborhoods_pkey PRIMARY KEY (postal_code_neighborhood_id);


--
-- Name: postal_code_neighborhoods postal_code_neighborhoods_postal_code_id_neighborhood_id_key; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.postal_code_neighborhoods
    ADD CONSTRAINT postal_code_neighborhoods_postal_code_id_neighborhood_id_key UNIQUE (postal_code_id, neighborhood_id);


--
-- Name: CONSTRAINT postal_code_neighborhoods_postal_code_id_neighborhood_id_key ON postal_code_neighborhoods; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON CONSTRAINT postal_code_neighborhoods_postal_code_id_neighborhood_id_key ON public.postal_code_neighborhoods IS 'Composite unique constraint to ensure that a specific pair (postal code, neighborhood). Can only exist once in the table, preventing duplicate relationships';


--
-- Name: publication_statuses publication_statuses_pk; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publication_statuses
    ADD CONSTRAINT publication_statuses_pk PRIMARY KEY (publication_status_id);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_token_key; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT refresh_tokens_token_key UNIQUE (token);


--
-- Name: animals uq_animals_user_ear_tag; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT uq_animals_user_ear_tag UNIQUE (user_id, ear_tag);


--
-- Name: CONSTRAINT uq_animals_user_ear_tag ON animals; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON CONSTRAINT uq_animals_user_ear_tag ON public.animals IS 'Ensures ear tag identifiers are unique within each user/owner scope';


--
-- Name: users uq_users_email; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT uq_users_email UNIQUE (email);


--
-- Name: CONSTRAINT uq_users_email ON users; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON CONSTRAINT uq_users_email ON public.users IS 'Ensures email addresses are unique across all users for login purposes';


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role);


--
-- Name: idx_addresses_active_created; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_addresses_active_created ON public.addresses USING btree (deleted_at, created_at);


--
-- Name: idx_addresses_created_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_addresses_created_at ON public.addresses USING btree (created_at);


--
-- Name: idx_addresses_postal_code_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_addresses_postal_code_id ON public.addresses USING btree (postal_code_id);


--
-- Name: idx_addresses_updated_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_addresses_updated_at ON public.addresses USING btree (updated_at);


--
-- Name: idx_animals_active_created; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_active_created ON public.animals USING btree (deleted_at, created_at);


--
-- Name: idx_animals_address_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_address_id ON public.animals USING btree (address_id);


--
-- Name: idx_animals_breed_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_breed_id ON public.animals USING btree (breed_id);


--
-- Name: idx_animals_created_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_created_at ON public.animals USING btree (created_at);


--
-- Name: idx_animals_ear_tag; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_ear_tag ON public.animals USING btree (ear_tag);


--
-- Name: idx_animals_gender_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_gender_id ON public.animals USING btree (gender_id);


--
-- Name: idx_animals_hlc_certified; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_hlc_certified ON public.animals USING btree (is_hlc_certified, hlc_certificate_id);


--
-- Name: INDEX idx_animals_hlc_certified; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON INDEX public.idx_animals_hlc_certified IS 'Optimizes queries filtering animals by HLC certification status for transport compliance checks';


--
-- Name: idx_animals_livestock_type_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_livestock_type_id ON public.animals USING btree (livestock_type_id);


--
-- Name: idx_animals_publication_date; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_publication_date ON public.animals USING btree (first_publication_date);


--
-- Name: idx_animals_updated_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_updated_at ON public.animals USING btree (updated_at);


--
-- Name: idx_animals_user_ear_tag; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_user_ear_tag ON public.animals USING btree (user_id, ear_tag);


--
-- Name: idx_animals_user_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_animals_user_id ON public.animals USING btree (user_id);


--
-- Name: idx_app_config_updated_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_app_config_updated_at ON public.app_config USING btree (updated_at);


--
-- Name: idx_breeds_species_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_breeds_species_id ON public.breeds USING btree (species_id);


--
-- Name: idx_death_causes_short_name; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_death_causes_short_name ON public.death_causes USING btree (short_name);


--
-- Name: idx_escrow_statuses_short_name; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_escrow_statuses_short_name ON public.escrow_statuses USING btree (short_name);


--
-- Name: idx_health_statuses_short_name; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_health_statuses_short_name ON public.animal_health_statuses USING btree (short_name);


--
-- Name: idx_hlc_certificates_expiration; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_hlc_certificates_expiration ON public.hlc_certificates USING btree (expiration_date, is_active);


--
-- Name: idx_hlc_certificates_user_active; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_hlc_certificates_user_active ON public.hlc_certificates USING btree (user_id, is_active);


--
-- Name: idx_mortality_reports_animal_date; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_mortality_reports_animal_date ON public.animal_mortality_reports USING btree (animal_id, death_date);


--
-- Name: idx_multimedia_active_created; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_multimedia_active_created ON public.multimedia USING btree (deleted_at, created_at);


--
-- Name: idx_multimedia_created_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_multimedia_created_at ON public.multimedia USING btree (created_at);


--
-- Name: idx_multimedia_entity; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_multimedia_entity ON public.multimedia USING btree (entity_type_id, entity_id);


--
-- Name: idx_multimedia_entity_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_multimedia_entity_id ON public.multimedia USING btree (entity_id);


--
-- Name: idx_multimedia_entity_type_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_multimedia_entity_type_id ON public.multimedia USING btree (entity_type_id);


--
-- Name: idx_multimedia_file_type_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_multimedia_file_type_id ON public.multimedia USING btree (file_type_id);


--
-- Name: idx_multimedia_file_url; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_multimedia_file_url ON public.multimedia USING btree (file_url);


--
-- Name: idx_multimedia_updated_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_multimedia_updated_at ON public.multimedia USING btree (updated_at);


--
-- Name: idx_municipalities_active_created; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_municipalities_active_created ON public.municipalities USING btree (deleted_at, created_at);


--
-- Name: idx_municipalities_created_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_municipalities_created_at ON public.municipalities USING btree (created_at);


--
-- Name: idx_municipalities_state_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_municipalities_state_id ON public.municipalities USING btree (state_id);


--
-- Name: idx_municipalities_updated_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_municipalities_updated_at ON public.municipalities USING btree (updated_at);


--
-- Name: idx_neighborhoods_active_created; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_neighborhoods_active_created ON public.neighborhoods USING btree (deleted_at, created_at);


--
-- Name: idx_neighborhoods_created_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_neighborhoods_created_at ON public.neighborhoods USING btree (created_at);


--
-- Name: idx_neighborhoods_municipality_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_neighborhoods_municipality_id ON public.neighborhoods USING btree (municipality_id);


--
-- Name: idx_neighborhoods_updated_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_neighborhoods_updated_at ON public.neighborhoods USING btree (updated_at);


--
-- Name: idx_offers_active_created; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_offers_active_created ON public.offers USING btree (deleted_at, created_at);


--
-- Name: idx_offers_created_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_offers_created_at ON public.offers USING btree (created_at);


--
-- Name: idx_offers_offer_status_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_offers_offer_status_id ON public.offers USING btree (offer_status_id);


--
-- Name: idx_offers_publication_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_offers_publication_id ON public.offers USING btree (publication_id);


--
-- Name: idx_offers_publication_status; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_offers_publication_status ON public.offers USING btree (publication_id, offer_status_id);


--
-- Name: idx_offers_updated_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_offers_updated_at ON public.offers USING btree (updated_at);


--
-- Name: idx_offers_user_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_offers_user_id ON public.offers USING btree (user_id);


--
-- Name: idx_payment_methods_short_name; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_payment_methods_short_name ON public.payment_methods USING btree (short_name);


--
-- Name: idx_payment_providers_short_name; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_payment_providers_short_name ON public.payment_providers USING btree (short_name);


--
-- Name: idx_pcn_neighborhood; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_pcn_neighborhood ON public.postal_code_neighborhoods USING btree (postal_code_id);


--
-- Name: idx_pcn_postal_code; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_pcn_postal_code ON public.postal_code_neighborhoods USING btree (postal_code_id);


--
-- Name: idx_postal_codes_active_created; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_postal_codes_active_created ON public.postal_codes USING btree (deleted_at, created_at);


--
-- Name: idx_postal_codes_created_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_postal_codes_created_at ON public.postal_codes USING btree (created_at);


--
-- Name: idx_postal_codes_postal_code; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_postal_codes_postal_code ON public.postal_codes USING btree (postal_code);


--
-- Name: idx_postal_codes_updated_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_postal_codes_updated_at ON public.postal_codes USING btree (updated_at);


--
-- Name: idx_promotion_types_short_name; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_promotion_types_short_name ON public.promotion_types USING btree (short_name);


--
-- Name: idx_promotions_active_dates; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_promotions_active_dates ON public.publication_promotions USING btree (is_active, start_date, end_date);


--
-- Name: idx_publication_municipalities_municipality_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publication_municipalities_municipality_id ON public.publication_municipalities USING btree (municipality_id);


--
-- Name: idx_publication_municipalities_publication_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publication_municipalities_publication_id ON public.publication_municipalities USING btree (publication_id);


--
-- Name: idx_publications_active_created; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_active_created ON public.publications USING btree (deleted_at, created_at);


--
-- Name: idx_publications_animal_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_animal_id ON public.publications USING btree (animal_id);


--
-- Name: idx_publications_created_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_created_at ON public.publications USING btree (created_at);


--
-- Name: idx_publications_dates; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_dates ON public.publications USING btree (end_date, start_date);


--
-- Name: idx_publications_end_date; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_end_date ON public.publications USING btree (end_date);


--
-- Name: idx_publications_geographic_promoted; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_geographic_promoted ON public.publications USING btree (geographic_reach_km, promotion_score);


--
-- Name: INDEX idx_publications_geographic_promoted; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON INDEX public.idx_publications_geographic_promoted IS 'Optimizes publication searches by geographic reach and promotion ranking for marketplace display';


--
-- Name: idx_publications_hlc_zones; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_hlc_zones ON public.publications USING btree (hlc_required, restricted_zones, allowed_zones);


--
-- Name: idx_publications_publication_type_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_publication_type_id ON public.publications USING btree (publication_type_id);


--
-- Name: idx_publications_start_date; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_start_date ON public.publications USING btree (start_date);


--
-- Name: idx_publications_target_free; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_target_free ON public.publications USING btree (created_at);


--
-- Name: idx_publications_transport_responsible_user_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_transport_responsible_user_id ON public.publications USING btree (transport_responsible_user_id);


--
-- Name: idx_publications_updated_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_publications_updated_at ON public.publications USING btree (updated_at);


--
-- Name: idx_refresh_token; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_refresh_token ON public.refresh_tokens USING btree (token);


--
-- Name: idx_refresh_token_expires_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_refresh_token_expires_at ON public.refresh_tokens USING btree (expires_at);


--
-- Name: idx_refresh_token_user_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_refresh_token_user_id ON public.refresh_tokens USING btree (user_id);


--
-- Name: idx_report_types_short_name; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_report_types_short_name ON public.report_types USING btree (short_name);


--
-- Name: idx_review_types_short_name; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_review_types_short_name ON public.review_types USING btree (short_name);


--
-- Name: idx_reviews_animal_rating; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_reviews_animal_rating ON public.reviews USING btree (animal_id, rating, created_at);


--
-- Name: idx_reviews_reviewed_user_rating; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_reviews_reviewed_user_rating ON public.reviews USING btree (reviewed_user_id, rating, created_at);


--
-- Name: idx_sales_active_created; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_sales_active_created ON public.sales USING btree (deleted_at, created_at);


--
-- Name: idx_sales_created_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_sales_created_at ON public.sales USING btree (created_at);


--
-- Name: idx_sales_delivery_status_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_sales_delivery_status_id ON public.sales USING btree (delivery_status_id);


--
-- Name: idx_sales_offer_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_sales_offer_id ON public.sales USING btree (offer_id);


--
-- Name: idx_sales_sale_date; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_sales_sale_date ON public.sales USING btree (sale_date);


--
-- Name: idx_sales_sale_status_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_sales_sale_status_id ON public.sales USING btree (sale_status_id);


--
-- Name: idx_sales_updated_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_sales_updated_at ON public.sales USING btree (updated_at);


--
-- Name: idx_saved_searches_active_user; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_saved_searches_active_user ON public.saved_searches USING btree (is_active, user_id);


--
-- Name: idx_search_notifications_unread; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_search_notifications_unread ON public.search_notifications USING btree (was_read, sent_at);


--
-- Name: idx_states_country_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_states_country_id ON public.states USING btree (country_id);


--
-- Name: idx_subscription_plans_settings_gin; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_subscription_plans_settings_gin ON public.subscription_plans USING gin (settings);


--
-- Name: idx_user_audit_logs_audit_action_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_user_audit_logs_audit_action_id ON public.user_audit_logs USING btree (audit_action_id);


--
-- Name: idx_user_audit_logs_registration_date; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_user_audit_logs_registration_date ON public.user_audit_logs USING btree (registration_date);


--
-- Name: idx_user_audit_logs_user_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_user_audit_logs_user_id ON public.user_audit_logs USING btree (user_id);


--
-- Name: idx_user_roles_role; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_user_roles_role ON public.user_roles USING btree (role);


--
-- Name: idx_user_types_settings_gin; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_user_types_settings_gin ON public.user_types USING gin (settings);


--
-- Name: idx_users_active_created; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_users_active_created ON public.users USING btree (deleted_at, created_at);


--
-- Name: idx_users_address_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_users_address_id ON public.users USING btree (address_id);


--
-- Name: idx_users_created_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_users_created_at ON public.users USING btree (created_at);


--
-- Name: idx_users_email; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_users_email ON public.users USING btree (email);


--
-- Name: idx_users_settings_gin; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_users_settings_gin ON public.users USING gin (settings);


--
-- Name: idx_users_subscription_plan_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_users_subscription_plan_id ON public.users USING btree (subscription_plan_id);


--
-- Name: idx_users_updated_at; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_users_updated_at ON public.users USING btree (updated_at);


--
-- Name: idx_users_user_type_id; Type: INDEX; Schema: public; Owner: devuser
--

CREATE INDEX idx_users_user_type_id ON public.users USING btree (user_type_id);


--
-- Name: addresses update_addresses_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_addresses_updated_at BEFORE UPDATE ON public.addresses FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_addresses_updated_at ON addresses; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_addresses_updated_at ON public.addresses IS 'Automatically updates the updated_at timestamp when address records are modified';


--
-- Name: animals update_animal_transport_capability_trigger; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_animal_transport_capability_trigger BEFORE INSERT OR UPDATE OF hlc_certificate_id, is_hlc_certified ON public.animals FOR EACH ROW EXECUTE FUNCTION public.update_animal_transport_capability();


--
-- Name: TRIGGER update_animal_transport_capability_trigger ON animals; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_animal_transport_capability_trigger ON public.animals IS 'Automatically updates transport capability flags when HLC certification status changes';


--
-- Name: animals update_animals_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_animals_updated_at BEFORE UPDATE ON public.animals FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_animals_updated_at ON animals; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_animals_updated_at ON public.animals IS 'Automatically updates the updated_at timestamp when animal records are modified';


--
-- Name: hlc_certificates update_hlc_certificates_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_hlc_certificates_updated_at BEFORE UPDATE ON public.hlc_certificates FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_hlc_certificates_updated_at ON hlc_certificates; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_hlc_certificates_updated_at ON public.hlc_certificates IS 'Automatically updates the updated_at timestamp when HLC certificate records are modified';


--
-- Name: animal_mortality_reports update_mortality_reports_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_mortality_reports_updated_at BEFORE UPDATE ON public.animal_mortality_reports FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_mortality_reports_updated_at ON animal_mortality_reports; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_mortality_reports_updated_at ON public.animal_mortality_reports IS 'Automatically updates the updated_at timestamp when mortality report records are modified';


--
-- Name: multimedia update_multimedia_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_multimedia_updated_at BEFORE UPDATE ON public.multimedia FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_multimedia_updated_at ON multimedia; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_multimedia_updated_at ON public.multimedia IS 'Automatically updates the updated_at timestamp when multimedia records are modified';


--
-- Name: municipalities update_municipalities_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_municipalities_updated_at BEFORE UPDATE ON public.municipalities FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_municipalities_updated_at ON municipalities; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_municipalities_updated_at ON public.municipalities IS 'Automatically updates the updated_at timestamp when municipality records are modified';


--
-- Name: neighborhoods update_neighborhoods_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_neighborhoods_updated_at BEFORE UPDATE ON public.neighborhoods FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_neighborhoods_updated_at ON neighborhoods; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_neighborhoods_updated_at ON public.neighborhoods IS 'Automatically updates the updated_at timestamp when neighborhood records are modified';


--
-- Name: offers update_offers_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_offers_updated_at BEFORE UPDATE ON public.offers FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_offers_updated_at ON offers; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_offers_updated_at ON public.offers IS 'Automatically updates the updated_at timestamp when offer records are modified';


--
-- Name: postal_codes update_postal_codes_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_postal_codes_updated_at BEFORE UPDATE ON public.postal_codes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_postal_codes_updated_at ON postal_codes; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_postal_codes_updated_at ON public.postal_codes IS 'Automatically updates the updated_at timestamp when postal code records are modified';


--
-- Name: publications update_publications_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_publications_updated_at BEFORE UPDATE ON public.publications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_publications_updated_at ON publications; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_publications_updated_at ON public.publications IS 'Automatically updates the updated_at timestamp when publication records are modified';


--
-- Name: reviews update_reviews_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_reviews_updated_at BEFORE UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_reviews_updated_at ON reviews; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_reviews_updated_at ON public.reviews IS 'Automatically updates the updated_at timestamp when review records are modified';


--
-- Name: sales update_sales_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_sales_updated_at BEFORE UPDATE ON public.sales FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_sales_updated_at ON sales; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_sales_updated_at ON public.sales IS 'Automatically updates the updated_at timestamp when sales records are modified';


--
-- Name: saved_searches update_saved_searches_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_saved_searches_updated_at BEFORE UPDATE ON public.saved_searches FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_saved_searches_updated_at ON saved_searches; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_saved_searches_updated_at ON public.saved_searches IS 'Automatically updates the updated_at timestamp when saved search records are modified';


--
-- Name: secure_payments update_secure_payments_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_secure_payments_updated_at BEFORE UPDATE ON public.secure_payments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_secure_payments_updated_at ON secure_payments; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_secure_payments_updated_at ON public.secure_payments IS 'Automatically updates the updated_at timestamp when secure payment records are modified';


--
-- Name: users update_users_updated_at; Type: TRIGGER; Schema: public; Owner: devuser
--

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: TRIGGER update_users_updated_at ON users; Type: COMMENT; Schema: public; Owner: devuser
--

COMMENT ON TRIGGER update_users_updated_at ON public.users IS 'Automatically updates the updated_at timestamp when user records are modified';


--
-- Name: app_config app_config_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.app_config
    ADD CONSTRAINT app_config_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(user_id);


--
-- Name: addresses fk_addresses_postal_code; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.addresses
    ADD CONSTRAINT fk_addresses_postal_code FOREIGN KEY (postal_code_id) REFERENCES public.postal_codes(postal_code_id);


--
-- Name: animals fk_animals_address; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT fk_animals_address FOREIGN KEY (address_id) REFERENCES public.addresses(address_id);


--
-- Name: animals fk_animals_breed; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT fk_animals_breed FOREIGN KEY (breed_id) REFERENCES public.breeds(breed_id);


--
-- Name: animals fk_animals_gender; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT fk_animals_gender FOREIGN KEY (gender_id) REFERENCES public.genders(gender_id);


--
-- Name: animals fk_animals_health_status; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT fk_animals_health_status FOREIGN KEY (health_status_id) REFERENCES public.animal_health_statuses(health_status_id);


--
-- Name: animals fk_animals_hlc_certificate; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT fk_animals_hlc_certificate FOREIGN KEY (hlc_certificate_id) REFERENCES public.hlc_certificates(hlc_certificate_id);


--
-- Name: animals fk_animals_livestock_type; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT fk_animals_livestock_type FOREIGN KEY (livestock_type_id) REFERENCES public.livestock_types(livestock_type_id);


--
-- Name: animals fk_animals_user; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT fk_animals_user FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: breeds fk_breeds_species; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.breeds
    ADD CONSTRAINT fk_breeds_species FOREIGN KEY (species_id) REFERENCES public.species(species_id);


--
-- Name: hlc_certificates fk_hlc_certificates_address; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.hlc_certificates
    ADD CONSTRAINT fk_hlc_certificates_address FOREIGN KEY (ranch_address_id) REFERENCES public.addresses(address_id);


--
-- Name: hlc_certificates fk_hlc_certificates_user; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.hlc_certificates
    ADD CONSTRAINT fk_hlc_certificates_user FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: animal_mortality_reports fk_mortality_reports_animal; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animal_mortality_reports
    ADD CONSTRAINT fk_mortality_reports_animal FOREIGN KEY (animal_id) REFERENCES public.animals(animal_id);


--
-- Name: animal_mortality_reports fk_mortality_reports_death_cause; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animal_mortality_reports
    ADD CONSTRAINT fk_mortality_reports_death_cause FOREIGN KEY (death_cause_id) REFERENCES public.death_causes(death_cause_id);


--
-- Name: animal_mortality_reports fk_mortality_reports_reported_by; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.animal_mortality_reports
    ADD CONSTRAINT fk_mortality_reports_reported_by FOREIGN KEY (reported_by_user_id) REFERENCES public.users(user_id);


--
-- Name: multimedia fk_multimedia_entity_type; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.multimedia
    ADD CONSTRAINT fk_multimedia_entity_type FOREIGN KEY (entity_type_id) REFERENCES public.entity_types(entity_type_id);


--
-- Name: multimedia fk_multimedia_file_type; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.multimedia
    ADD CONSTRAINT fk_multimedia_file_type FOREIGN KEY (file_type_id) REFERENCES public.file_types(file_type_id);


--
-- Name: municipalities fk_municipalities_state; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.municipalities
    ADD CONSTRAINT fk_municipalities_state FOREIGN KEY (state_id) REFERENCES public.states(state_id);


--
-- Name: neighborhoods fk_neighborhoods_municipality; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.neighborhoods
    ADD CONSTRAINT fk_neighborhoods_municipality FOREIGN KEY (municipality_id) REFERENCES public.municipalities(municipality_id);


--
-- Name: offers fk_offers_offer_status; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.offers
    ADD CONSTRAINT fk_offers_offer_status FOREIGN KEY (offer_status_id) REFERENCES public.offer_statuses(offer_status_id);


--
-- Name: offers fk_offers_publication; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.offers
    ADD CONSTRAINT fk_offers_publication FOREIGN KEY (publication_id) REFERENCES public.publications(publication_id);


--
-- Name: offers fk_offers_user; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.offers
    ADD CONSTRAINT fk_offers_user FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: publication_municipalities fk_publication_municipalities_municipality; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publication_municipalities
    ADD CONSTRAINT fk_publication_municipalities_municipality FOREIGN KEY (municipality_id) REFERENCES public.municipalities(municipality_id);


--
-- Name: publication_municipalities fk_publication_municipalities_publication; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publication_municipalities
    ADD CONSTRAINT fk_publication_municipalities_publication FOREIGN KEY (publication_id) REFERENCES public.publications(publication_id);


--
-- Name: publication_promotions fk_publication_promotions_promotion_type; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publication_promotions
    ADD CONSTRAINT fk_publication_promotions_promotion_type FOREIGN KEY (promotion_type_id) REFERENCES public.promotion_types(promotion_type_id);


--
-- Name: publication_promotions fk_publication_promotions_publication; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publication_promotions
    ADD CONSTRAINT fk_publication_promotions_publication FOREIGN KEY (publication_id) REFERENCES public.publications(publication_id);


--
-- Name: publications fk_publications_animal; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publications
    ADD CONSTRAINT fk_publications_animal FOREIGN KEY (animal_id) REFERENCES public.animals(animal_id);


--
-- Name: publications fk_publications_publication_type; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publications
    ADD CONSTRAINT fk_publications_publication_type FOREIGN KEY (publication_type_id) REFERENCES public.publication_types(publication_type_id);


--
-- Name: publications fk_publications_transport_responsible_user; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publications
    ADD CONSTRAINT fk_publications_transport_responsible_user FOREIGN KEY (transport_responsible_user_id) REFERENCES public.users(user_id);


--
-- Name: refresh_tokens fk_refresh_token_user; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT fk_refresh_token_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: reviews fk_reviews_animal; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT fk_reviews_animal FOREIGN KEY (animal_id) REFERENCES public.animals(animal_id);


--
-- Name: reviews fk_reviews_review_type; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT fk_reviews_review_type FOREIGN KEY (review_type_id) REFERENCES public.review_types(review_type_id);


--
-- Name: reviews fk_reviews_reviewed_user; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT fk_reviews_reviewed_user FOREIGN KEY (reviewed_user_id) REFERENCES public.users(user_id);


--
-- Name: reviews fk_reviews_reviewer; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT fk_reviews_reviewer FOREIGN KEY (reviewer_user_id) REFERENCES public.users(user_id);


--
-- Name: reviews fk_reviews_sale; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT fk_reviews_sale FOREIGN KEY (sale_id) REFERENCES public.sales(sale_id);


--
-- Name: sales fk_sales_delivery_status; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_sales_delivery_status FOREIGN KEY (delivery_status_id) REFERENCES public.delivery_statuses(delivery_status_id);


--
-- Name: sales fk_sales_offer; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_sales_offer FOREIGN KEY (offer_id) REFERENCES public.offers(offer_id);


--
-- Name: sales fk_sales_payment_status; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_sales_payment_status FOREIGN KEY (payment_status_id) REFERENCES public.payment_statuses(payment_status_id);


--
-- Name: sales fk_sales_sale_status; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT fk_sales_sale_status FOREIGN KEY (sale_status_id) REFERENCES public.sale_statuses(sale_status_id);


--
-- Name: saved_searches fk_saved_searches_user; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.saved_searches
    ADD CONSTRAINT fk_saved_searches_user FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: search_notifications fk_search_notifications_publication; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.search_notifications
    ADD CONSTRAINT fk_search_notifications_publication FOREIGN KEY (publication_id) REFERENCES public.publications(publication_id);


--
-- Name: search_notifications fk_search_notifications_saved_search; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.search_notifications
    ADD CONSTRAINT fk_search_notifications_saved_search FOREIGN KEY (saved_search_id) REFERENCES public.saved_searches(saved_search_id);


--
-- Name: secure_payments fk_secure_payments_escrow_status; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.secure_payments
    ADD CONSTRAINT fk_secure_payments_escrow_status FOREIGN KEY (escrow_status_id) REFERENCES public.escrow_statuses(escrow_status_id);


--
-- Name: secure_payments fk_secure_payments_method; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.secure_payments
    ADD CONSTRAINT fk_secure_payments_method FOREIGN KEY (payment_method_id) REFERENCES public.payment_methods(payment_method_id);


--
-- Name: secure_payments fk_secure_payments_offer; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.secure_payments
    ADD CONSTRAINT fk_secure_payments_offer FOREIGN KEY (offer_id) REFERENCES public.offers(offer_id);


--
-- Name: secure_payments fk_secure_payments_provider; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.secure_payments
    ADD CONSTRAINT fk_secure_payments_provider FOREIGN KEY (payment_provider_id) REFERENCES public.payment_providers(payment_provider_id);


--
-- Name: seller_reports fk_seller_reports_report_type; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.seller_reports
    ADD CONSTRAINT fk_seller_reports_report_type FOREIGN KEY (report_type_id) REFERENCES public.report_types(report_type_id);


--
-- Name: seller_reports fk_seller_reports_seller; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.seller_reports
    ADD CONSTRAINT fk_seller_reports_seller FOREIGN KEY (seller_user_id) REFERENCES public.users(user_id);


--
-- Name: states fk_states_country; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.states
    ADD CONSTRAINT fk_states_country FOREIGN KEY (country_id) REFERENCES public.countries(country_id);


--
-- Name: user_audit_logs fk_user_audit_logs_audit_action; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.user_audit_logs
    ADD CONSTRAINT fk_user_audit_logs_audit_action FOREIGN KEY (audit_action_id) REFERENCES public.audit_actions(audit_action_id);


--
-- Name: user_audit_logs fk_user_audit_logs_user; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.user_audit_logs
    ADD CONSTRAINT fk_user_audit_logs_user FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: user_roles fk_user_roles_user; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: users fk_users_adress; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_users_adress FOREIGN KEY (address_id) REFERENCES public.addresses(address_id);


--
-- Name: users fk_users_subscription_plan; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_users_subscription_plan FOREIGN KEY (subscription_plan_id) REFERENCES public.subscription_plans(subscription_plan_id);


--
-- Name: users fk_users_user_type; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_users_user_type FOREIGN KEY (user_type_id) REFERENCES public.user_types(user_type_id);


--
-- Name: postal_code_neighborhoods postal_code_neighborhoods_neighborhood_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.postal_code_neighborhoods
    ADD CONSTRAINT postal_code_neighborhoods_neighborhood_id_fkey FOREIGN KEY (neighborhood_id) REFERENCES public.neighborhoods(neighborhood_id);


--
-- Name: postal_code_neighborhoods postal_code_neighborhoods_postal_code_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.postal_code_neighborhoods
    ADD CONSTRAINT postal_code_neighborhoods_postal_code_id_fkey FOREIGN KEY (postal_code_id) REFERENCES public.postal_codes(postal_code_id);


--
-- Name: postal_codes postal_codes_municipalities_fk; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.postal_codes
    ADD CONSTRAINT postal_codes_municipalities_fk FOREIGN KEY (municipality_id) REFERENCES public.municipalities(municipality_id);


--
-- Name: publications publications_publication_statuses_fk; Type: FK CONSTRAINT; Schema: public; Owner: devuser
--

ALTER TABLE ONLY public.publications
    ADD CONSTRAINT publications_publication_statuses_fk FOREIGN KEY (publication_status_id) REFERENCES public.publication_statuses(publication_status_id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO readonly_user;
GRANT USAGE ON SCHEMA public TO app_user;
GRANT USAGE ON SCHEMA public TO data_admin;


--
-- Name: FUNCTION calculate_seller_reputation_score(p_user_id integer); Type: ACL; Schema: public; Owner: devuser
--

GRANT ALL ON FUNCTION public.calculate_seller_reputation_score(p_user_id integer) TO app_user;
GRANT ALL ON FUNCTION public.calculate_seller_reputation_score(p_user_id integer) TO data_admin;


--
-- Name: FUNCTION can_transport_animal_to_zone(p_animal_id integer, p_destination_zone_id integer); Type: ACL; Schema: public; Owner: devuser
--

GRANT ALL ON FUNCTION public.can_transport_animal_to_zone(p_animal_id integer, p_destination_zone_id integer) TO app_user;
GRANT ALL ON FUNCTION public.can_transport_animal_to_zone(p_animal_id integer, p_destination_zone_id integer) TO data_admin;


--
-- Name: FUNCTION get_allowed_zones_for_animal(p_animal_id integer); Type: ACL; Schema: public; Owner: devuser
--

GRANT ALL ON FUNCTION public.get_allowed_zones_for_animal(p_animal_id integer) TO app_user;
GRANT ALL ON FUNCTION public.get_allowed_zones_for_animal(p_animal_id integer) TO data_admin;


--
-- Name: FUNCTION get_available_publications_for_user(p_user_id integer, p_user_zone_id integer); Type: ACL; Schema: public; Owner: devuser
--

GRANT ALL ON FUNCTION public.get_available_publications_for_user(p_user_id integer, p_user_zone_id integer) TO app_user;
GRANT ALL ON FUNCTION public.get_available_publications_for_user(p_user_id integer, p_user_zone_id integer) TO data_admin;


--
-- Name: FUNCTION soft_delete_record(p_table_name text, p_record_id integer, p_id_column text); Type: ACL; Schema: public; Owner: devuser
--

GRANT ALL ON FUNCTION public.soft_delete_record(p_table_name text, p_record_id integer, p_id_column text) TO app_user;
GRANT ALL ON FUNCTION public.soft_delete_record(p_table_name text, p_record_id integer, p_id_column text) TO data_admin;


--
-- Name: FUNCTION update_animal_transport_capability(); Type: ACL; Schema: public; Owner: devuser
--

GRANT ALL ON FUNCTION public.update_animal_transport_capability() TO app_user;
GRANT ALL ON FUNCTION public.update_animal_transport_capability() TO data_admin;


--
-- Name: FUNCTION update_session_activity(); Type: ACL; Schema: public; Owner: devuser
--

GRANT ALL ON FUNCTION public.update_session_activity() TO app_user;
GRANT ALL ON FUNCTION public.update_session_activity() TO data_admin;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: public; Owner: devuser
--

GRANT ALL ON FUNCTION public.update_updated_at_column() TO app_user;
GRANT ALL ON FUNCTION public.update_updated_at_column() TO data_admin;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.users TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.users TO app_user;
GRANT ALL ON TABLE public.users TO data_admin;


--
-- Name: TABLE active_users; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.active_users TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.active_users TO app_user;
GRANT ALL ON TABLE public.active_users TO data_admin;


--
-- Name: TABLE addresses; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.addresses TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.addresses TO app_user;
GRANT ALL ON TABLE public.addresses TO data_admin;


--
-- Name: TABLE animal_health_statuses; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.animal_health_statuses TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.animal_health_statuses TO app_user;
GRANT ALL ON TABLE public.animal_health_statuses TO data_admin;


--
-- Name: SEQUENCE animal_health_statuses_health_status_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.animal_health_statuses_health_status_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.animal_health_statuses_health_status_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.animal_health_statuses_health_status_id_seq TO data_admin;


--
-- Name: TABLE animals; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.animals TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.animals TO app_user;
GRANT ALL ON TABLE public.animals TO data_admin;


--
-- Name: SEQUENCE animal_id_animal_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.animal_id_animal_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.animal_id_animal_seq TO app_user;
GRANT ALL ON SEQUENCE public.animal_id_animal_seq TO data_admin;


--
-- Name: TABLE animal_mortality_reports; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.animal_mortality_reports TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.animal_mortality_reports TO app_user;
GRANT ALL ON TABLE public.animal_mortality_reports TO data_admin;


--
-- Name: SEQUENCE animal_mortality_reports_mortality_report_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.animal_mortality_reports_mortality_report_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.animal_mortality_reports_mortality_report_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.animal_mortality_reports_mortality_report_id_seq TO data_admin;


--
-- Name: TABLE app_config; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.app_config TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.app_config TO app_user;
GRANT ALL ON TABLE public.app_config TO data_admin;


--
-- Name: TABLE audit_actions; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.audit_actions TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.audit_actions TO app_user;
GRANT ALL ON TABLE public.audit_actions TO data_admin;


--
-- Name: TABLE breeds; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.breeds TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.breeds TO app_user;
GRANT ALL ON TABLE public.breeds TO data_admin;


--
-- Name: TABLE entity_types; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.entity_types TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.entity_types TO app_user;
GRANT ALL ON TABLE public.entity_types TO data_admin;


--
-- Name: SEQUENCE cat__tipo_entidad_id_tipo_entidad_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.cat__tipo_entidad_id_tipo_entidad_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.cat__tipo_entidad_id_tipo_entidad_seq TO app_user;
GRANT ALL ON SEQUENCE public.cat__tipo_entidad_id_tipo_entidad_seq TO data_admin;


--
-- Name: SEQUENCE cat_acciones_historial_id_accion_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.cat_acciones_historial_id_accion_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.cat_acciones_historial_id_accion_seq TO app_user;
GRANT ALL ON SEQUENCE public.cat_acciones_historial_id_accion_seq TO data_admin;


--
-- Name: TABLE subscription_plans; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.subscription_plans TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.subscription_plans TO app_user;
GRANT ALL ON TABLE public.subscription_plans TO data_admin;


--
-- Name: SEQUENCE cat_paquete_id_paquete_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.cat_paquete_id_paquete_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.cat_paquete_id_paquete_seq TO app_user;
GRANT ALL ON SEQUENCE public.cat_paquete_id_paquete_seq TO data_admin;


--
-- Name: TABLE neighborhoods; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.neighborhoods TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.neighborhoods TO app_user;
GRANT ALL ON TABLE public.neighborhoods TO data_admin;


--
-- Name: SEQUENCE catcolonia_id_colonia_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.catcolonia_id_colonia_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.catcolonia_id_colonia_seq TO app_user;
GRANT ALL ON SEQUENCE public.catcolonia_id_colonia_seq TO data_admin;


--
-- Name: TABLE municipalities; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.municipalities TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.municipalities TO app_user;
GRANT ALL ON TABLE public.municipalities TO data_admin;


--
-- Name: SEQUENCE catmunicipio_id_municipio_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.catmunicipio_id_municipio_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.catmunicipio_id_municipio_seq TO app_user;
GRANT ALL ON SEQUENCE public.catmunicipio_id_municipio_seq TO data_admin;


--
-- Name: TABLE countries; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.countries TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.countries TO app_user;
GRANT ALL ON TABLE public.countries TO data_admin;


--
-- Name: SEQUENCE catpais_id_pais_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.catpais_id_pais_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.catpais_id_pais_seq TO app_user;
GRANT ALL ON SEQUENCE public.catpais_id_pais_seq TO data_admin;


--
-- Name: TABLE death_causes; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.death_causes TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.death_causes TO app_user;
GRANT ALL ON TABLE public.death_causes TO data_admin;


--
-- Name: SEQUENCE death_causes_death_cause_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.death_causes_death_cause_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.death_causes_death_cause_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.death_causes_death_cause_id_seq TO data_admin;


--
-- Name: TABLE delivery_statuses; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.delivery_statuses TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.delivery_statuses TO app_user;
GRANT ALL ON TABLE public.delivery_statuses TO data_admin;


--
-- Name: SEQUENCE domicilio_animal_id_domicilio_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.domicilio_animal_id_domicilio_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.domicilio_animal_id_domicilio_seq TO app_user;
GRANT ALL ON SEQUENCE public.domicilio_animal_id_domicilio_seq TO data_admin;


--
-- Name: TABLE postal_codes; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.postal_codes TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.postal_codes TO app_user;
GRANT ALL ON TABLE public.postal_codes TO data_admin;


--
-- Name: SEQUENCE domicilio_id_domicilio_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.domicilio_id_domicilio_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.domicilio_id_domicilio_seq TO app_user;
GRANT ALL ON SEQUENCE public.domicilio_id_domicilio_seq TO data_admin;


--
-- Name: TABLE escrow_statuses; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.escrow_statuses TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.escrow_statuses TO app_user;
GRANT ALL ON TABLE public.escrow_statuses TO data_admin;


--
-- Name: SEQUENCE escrow_statuses_escrow_status_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.escrow_statuses_escrow_status_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.escrow_statuses_escrow_status_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.escrow_statuses_escrow_status_id_seq TO data_admin;


--
-- Name: TABLE species; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.species TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.species TO app_user;
GRANT ALL ON TABLE public.species TO data_admin;


--
-- Name: SEQUENCE especie_id_especie_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.especie_id_especie_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.especie_id_especie_seq TO app_user;
GRANT ALL ON SEQUENCE public.especie_id_especie_seq TO data_admin;


--
-- Name: SEQUENCE estado_entrega_id_estado_entrega_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.estado_entrega_id_estado_entrega_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.estado_entrega_id_estado_entrega_seq TO app_user;
GRANT ALL ON SEQUENCE public.estado_entrega_id_estado_entrega_seq TO data_admin;


--
-- Name: TABLE states; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.states TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.states TO app_user;
GRANT ALL ON TABLE public.states TO data_admin;


--
-- Name: SEQUENCE estado_id_estado_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.estado_id_estado_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.estado_id_estado_seq TO app_user;
GRANT ALL ON SEQUENCE public.estado_id_estado_seq TO data_admin;


--
-- Name: TABLE offer_statuses; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.offer_statuses TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.offer_statuses TO app_user;
GRANT ALL ON TABLE public.offer_statuses TO data_admin;


--
-- Name: SEQUENCE estado_oferta_id_estado_oferta_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.estado_oferta_id_estado_oferta_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.estado_oferta_id_estado_oferta_seq TO app_user;
GRANT ALL ON SEQUENCE public.estado_oferta_id_estado_oferta_seq TO data_admin;


--
-- Name: TABLE sale_statuses; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.sale_statuses TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.sale_statuses TO app_user;
GRANT ALL ON TABLE public.sale_statuses TO data_admin;


--
-- Name: SEQUENCE estado_venta_id_estado_venta_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.estado_venta_id_estado_venta_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.estado_venta_id_estado_venta_seq TO app_user;
GRANT ALL ON SEQUENCE public.estado_venta_id_estado_venta_seq TO data_admin;


--
-- Name: TABLE file_types; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.file_types TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.file_types TO app_user;
GRANT ALL ON TABLE public.file_types TO data_admin;


--
-- Name: TABLE genders; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.genders TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.genders TO app_user;
GRANT ALL ON TABLE public.genders TO data_admin;


--
-- Name: TABLE hlc_certificates; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.hlc_certificates TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.hlc_certificates TO app_user;
GRANT ALL ON TABLE public.hlc_certificates TO data_admin;


--
-- Name: SEQUENCE hlc_certificates_hlc_certificate_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.hlc_certificates_hlc_certificate_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.hlc_certificates_hlc_certificate_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.hlc_certificates_hlc_certificate_id_seq TO data_admin;


--
-- Name: TABLE livestock_types; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.livestock_types TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.livestock_types TO app_user;
GRANT ALL ON TABLE public.livestock_types TO data_admin;


--
-- Name: TABLE mobility_restrictions; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.mobility_restrictions TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.mobility_restrictions TO app_user;
GRANT ALL ON TABLE public.mobility_restrictions TO data_admin;


--
-- Name: SEQUENCE mobility_restrictions_restriction_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.mobility_restrictions_restriction_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.mobility_restrictions_restriction_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.mobility_restrictions_restriction_id_seq TO data_admin;


--
-- Name: TABLE multimedia; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.multimedia TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.multimedia TO app_user;
GRANT ALL ON TABLE public.multimedia TO data_admin;


--
-- Name: SEQUENCE multimedia_id_multimedia_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.multimedia_id_multimedia_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.multimedia_id_multimedia_seq TO app_user;
GRANT ALL ON SEQUENCE public.multimedia_id_multimedia_seq TO data_admin;


--
-- Name: TABLE offers; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.offers TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.offers TO app_user;
GRANT ALL ON TABLE public.offers TO data_admin;


--
-- Name: SEQUENCE oferta_id_oferta_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.oferta_id_oferta_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.oferta_id_oferta_seq TO app_user;
GRANT ALL ON SEQUENCE public.oferta_id_oferta_seq TO data_admin;


--
-- Name: TABLE payment_methods; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.payment_methods TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.payment_methods TO app_user;
GRANT ALL ON TABLE public.payment_methods TO data_admin;


--
-- Name: SEQUENCE payment_methods_payment_method_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.payment_methods_payment_method_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.payment_methods_payment_method_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.payment_methods_payment_method_id_seq TO data_admin;


--
-- Name: TABLE payment_providers; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.payment_providers TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.payment_providers TO app_user;
GRANT ALL ON TABLE public.payment_providers TO data_admin;


--
-- Name: SEQUENCE payment_providers_payment_provider_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.payment_providers_payment_provider_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.payment_providers_payment_provider_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.payment_providers_payment_provider_id_seq TO data_admin;


--
-- Name: TABLE payment_statuses; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.payment_statuses TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.payment_statuses TO app_user;
GRANT ALL ON TABLE public.payment_statuses TO data_admin;


--
-- Name: SEQUENCE payment_statuses_payment_status_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.payment_statuses_payment_status_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.payment_statuses_payment_status_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.payment_statuses_payment_status_id_seq TO data_admin;


--
-- Name: TABLE postal_code_neighborhoods; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.postal_code_neighborhoods TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.postal_code_neighborhoods TO app_user;
GRANT ALL ON TABLE public.postal_code_neighborhoods TO data_admin;


--
-- Name: SEQUENCE postal_code_neighborhoods_postal_code_neighborhood_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.postal_code_neighborhoods_postal_code_neighborhood_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.postal_code_neighborhoods_postal_code_neighborhood_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.postal_code_neighborhoods_postal_code_neighborhood_id_seq TO data_admin;


--
-- Name: TABLE promotion_types; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.promotion_types TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.promotion_types TO app_user;
GRANT ALL ON TABLE public.promotion_types TO data_admin;


--
-- Name: SEQUENCE promotion_types_promotion_type_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.promotion_types_promotion_type_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.promotion_types_promotion_type_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.promotion_types_promotion_type_id_seq TO data_admin;


--
-- Name: TABLE publications; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.publications TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.publications TO app_user;
GRANT ALL ON TABLE public.publications TO data_admin;


--
-- Name: SEQUENCE publicacion_id_publicacion_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.publicacion_id_publicacion_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.publicacion_id_publicacion_seq TO app_user;
GRANT ALL ON SEQUENCE public.publicacion_id_publicacion_seq TO data_admin;


--
-- Name: TABLE publication_municipalities; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.publication_municipalities TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.publication_municipalities TO app_user;
GRANT ALL ON TABLE public.publication_municipalities TO data_admin;


--
-- Name: SEQUENCE publicacion_municipio_id_publicacion_municipio_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.publicacion_municipio_id_publicacion_municipio_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.publicacion_municipio_id_publicacion_municipio_seq TO app_user;
GRANT ALL ON SEQUENCE public.publicacion_municipio_id_publicacion_municipio_seq TO data_admin;


--
-- Name: TABLE publication_promotions; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.publication_promotions TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.publication_promotions TO app_user;
GRANT ALL ON TABLE public.publication_promotions TO data_admin;


--
-- Name: SEQUENCE publication_promotions_promotion_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.publication_promotions_promotion_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.publication_promotions_promotion_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.publication_promotions_promotion_id_seq TO data_admin;


--
-- Name: TABLE publication_statuses; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.publication_statuses TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.publication_statuses TO app_user;
GRANT ALL ON TABLE public.publication_statuses TO data_admin;


--
-- Name: SEQUENCE publication_statuses_publication_status_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.publication_statuses_publication_status_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.publication_statuses_publication_status_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.publication_statuses_publication_status_id_seq TO data_admin;


--
-- Name: TABLE publication_types; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.publication_types TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.publication_types TO app_user;
GRANT ALL ON TABLE public.publication_types TO data_admin;


--
-- Name: SEQUENCE raza_id_raza_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.raza_id_raza_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.raza_id_raza_seq TO app_user;
GRANT ALL ON SEQUENCE public.raza_id_raza_seq TO data_admin;


--
-- Name: TABLE refresh_tokens; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.refresh_tokens TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.refresh_tokens TO app_user;
GRANT ALL ON TABLE public.refresh_tokens TO data_admin;


--
-- Name: SEQUENCE refresh_tokens_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT,USAGE ON SEQUENCE public.refresh_tokens_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.refresh_tokens_id_seq TO data_admin;


--
-- Name: TABLE report_types; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.report_types TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.report_types TO app_user;
GRANT ALL ON TABLE public.report_types TO data_admin;


--
-- Name: SEQUENCE report_types_report_type_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.report_types_report_type_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.report_types_report_type_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.report_types_report_type_id_seq TO data_admin;


--
-- Name: TABLE review_types; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.review_types TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.review_types TO app_user;
GRANT ALL ON TABLE public.review_types TO data_admin;


--
-- Name: SEQUENCE review_types_review_type_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.review_types_review_type_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.review_types_review_type_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.review_types_review_type_id_seq TO data_admin;


--
-- Name: TABLE reviews; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.reviews TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.reviews TO app_user;
GRANT ALL ON TABLE public.reviews TO data_admin;


--
-- Name: SEQUENCE reviews_review_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.reviews_review_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.reviews_review_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.reviews_review_id_seq TO data_admin;


--
-- Name: TABLE sales; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.sales TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.sales TO app_user;
GRANT ALL ON TABLE public.sales TO data_admin;


--
-- Name: TABLE saved_searches; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.saved_searches TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.saved_searches TO app_user;
GRANT ALL ON TABLE public.saved_searches TO data_admin;


--
-- Name: SEQUENCE saved_searches_saved_search_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.saved_searches_saved_search_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.saved_searches_saved_search_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.saved_searches_saved_search_id_seq TO data_admin;


--
-- Name: TABLE search_notifications; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.search_notifications TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.search_notifications TO app_user;
GRANT ALL ON TABLE public.search_notifications TO data_admin;


--
-- Name: SEQUENCE search_notifications_notification_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.search_notifications_notification_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.search_notifications_notification_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.search_notifications_notification_id_seq TO data_admin;


--
-- Name: TABLE secure_payments; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.secure_payments TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.secure_payments TO app_user;
GRANT ALL ON TABLE public.secure_payments TO data_admin;


--
-- Name: SEQUENCE secure_payments_secure_payment_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.secure_payments_secure_payment_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.secure_payments_secure_payment_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.secure_payments_secure_payment_id_seq TO data_admin;


--
-- Name: TABLE seller_reports; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.seller_reports TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.seller_reports TO app_user;
GRANT ALL ON TABLE public.seller_reports TO data_admin;


--
-- Name: SEQUENCE seller_reports_report_id_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.seller_reports_report_id_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.seller_reports_report_id_seq TO app_user;
GRANT ALL ON SEQUENCE public.seller_reports_report_id_seq TO data_admin;


--
-- Name: SEQUENCE sexo_id_sexo_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.sexo_id_sexo_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.sexo_id_sexo_seq TO app_user;
GRANT ALL ON SEQUENCE public.sexo_id_sexo_seq TO data_admin;


--
-- Name: SEQUENCE tipo_archivo_id_tipo_archivo_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.tipo_archivo_id_tipo_archivo_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.tipo_archivo_id_tipo_archivo_seq TO app_user;
GRANT ALL ON SEQUENCE public.tipo_archivo_id_tipo_archivo_seq TO data_admin;


--
-- Name: SEQUENCE tipo_ganado_id_tipo_ganado_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.tipo_ganado_id_tipo_ganado_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.tipo_ganado_id_tipo_ganado_seq TO app_user;
GRANT ALL ON SEQUENCE public.tipo_ganado_id_tipo_ganado_seq TO data_admin;


--
-- Name: SEQUENCE tipo_publicacion_id_tipo_publicacion_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.tipo_publicacion_id_tipo_publicacion_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.tipo_publicacion_id_tipo_publicacion_seq TO app_user;
GRANT ALL ON SEQUENCE public.tipo_publicacion_id_tipo_publicacion_seq TO data_admin;


--
-- Name: TABLE user_types; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.user_types TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.user_types TO app_user;
GRANT ALL ON TABLE public.user_types TO data_admin;


--
-- Name: SEQUENCE tipo_usuario_id_tipo_usuario_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.tipo_usuario_id_tipo_usuario_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.tipo_usuario_id_tipo_usuario_seq TO app_user;
GRANT ALL ON SEQUENCE public.tipo_usuario_id_tipo_usuario_seq TO data_admin;


--
-- Name: TABLE user_audit_logs; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.user_audit_logs TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.user_audit_logs TO app_user;
GRANT ALL ON TABLE public.user_audit_logs TO data_admin;


--
-- Name: TABLE user_roles; Type: ACL; Schema: public; Owner: devuser
--

GRANT SELECT ON TABLE public.user_roles TO readonly_user;
GRANT SELECT,INSERT,UPDATE ON TABLE public.user_roles TO app_user;
GRANT ALL ON TABLE public.user_roles TO data_admin;


--
-- Name: SEQUENCE usuario_id_usuario_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.usuario_id_usuario_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.usuario_id_usuario_seq TO app_user;
GRANT ALL ON SEQUENCE public.usuario_id_usuario_seq TO data_admin;


--
-- Name: SEQUENCE usuariohistorial_id_historial_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.usuariohistorial_id_historial_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.usuariohistorial_id_historial_seq TO app_user;
GRANT ALL ON SEQUENCE public.usuariohistorial_id_historial_seq TO data_admin;


--
-- Name: SEQUENCE venta_id_venta_seq; Type: ACL; Schema: public; Owner: devuser
--

GRANT USAGE ON SEQUENCE public.venta_id_venta_seq TO readonly_user;
GRANT SELECT,USAGE ON SEQUENCE public.venta_id_venta_seq TO app_user;
GRANT ALL ON SEQUENCE public.venta_id_venta_seq TO data_admin;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: devuser
--

ALTER DEFAULT PRIVILEGES FOR ROLE devuser IN SCHEMA public GRANT SELECT,USAGE ON SEQUENCES TO app_user;
ALTER DEFAULT PRIVILEGES FOR ROLE devuser IN SCHEMA public GRANT ALL ON SEQUENCES TO data_admin;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: devuser
--

ALTER DEFAULT PRIVILEGES FOR ROLE devuser IN SCHEMA public GRANT ALL ON FUNCTIONS TO app_user;
ALTER DEFAULT PRIVILEGES FOR ROLE devuser IN SCHEMA public GRANT ALL ON FUNCTIONS TO data_admin;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: devuser
--

ALTER DEFAULT PRIVILEGES FOR ROLE devuser IN SCHEMA public GRANT SELECT ON TABLES TO readonly_user;
ALTER DEFAULT PRIVILEGES FOR ROLE devuser IN SCHEMA public GRANT SELECT,INSERT,UPDATE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES FOR ROLE devuser IN SCHEMA public GRANT ALL ON TABLES TO data_admin;


--
-- PostgreSQL database dump complete
--

\unrestrict FQ5TBuFGhufnIf1OFzodFCJ6T1MIybJJZSWTjLgsymTFsGli5dBTsrE0lH9JiaW

