package com.mercadoganadero.security.jwt;

import com.mercadoganadero.security.CustomUserDetailsService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * Filtro JWT que intercepta cada petición HTTP
 * Extrae el token del header Authorization, lo valida y establece la autenticación
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtTokenProvider tokenProvider; // Clase utilitaria para JWT
    private final CustomUserDetailsService userDetailsService; // Servicio para cargar el usuario

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        try {
            // 1. Extraer el JWT del header Authorization
            String jwt = getJwtFromRequest(request);

            // 2. Validar el token y extraer información del usuario
            if (StringUtils.hasText(jwt) && tokenProvider.validateToken(jwt)) {
                // Obtener la identidad (username/email) del token
                String username = tokenProvider.getUsernameFromJWT(jwt);

                // 3. Cargar los detalles completos del usuario (incluidos roles)
                UserDetails userDetails = userDetailsService.loadUserByUsername(username);

                // 4. Crear el objeto de autenticación
                UsernamePasswordAuthenticationToken authentication =
                        new UsernamePasswordAuthenticationToken(
                                userDetails,
                                null,
                                userDetails.getAuthorities() // Incluye los roles
                        );

                authentication.setDetails(
                        new WebAuthenticationDetailsSource().buildDetails(request)
                );

                // 5. Establecer la autenticación en el contexto de seguridad
                SecurityContextHolder.getContext().setAuthentication(authentication);

                log.debug("Usuario autenticado: {} con roles: {}",
                        username, userDetails.getAuthorities());
            }
        } catch (Exception ex) {
            // Manejar errores de token inválido/expirado
            logger.error("No se pudo establecer la autenticación del usuario en el contexto de seguridad", ex);
        }

        filterChain.doFilter(request, response);
    }

    /**
     * Extrae el JWT del header Authorization
     * Formato esperado: "Authorization: Bearer <token>"
     */
    private String getJwtFromRequest(HttpServletRequest request) {
        String bearerToken = request.getHeader("Authorization");
        // Buscar el patrón "Bearer <token>"
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7); // Eliminar "Bearer " del inicio
        }
        return null;
    }
}