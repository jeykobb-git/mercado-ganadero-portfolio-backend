package com.mercadoganadero;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.jpa.repository.config.EnableJpaAuditing;

@SpringBootApplication
@EnableJpaAuditing
public class MercadoGanaderoApplication {

    public static void main(String[] args) {
        SpringApplication.run(MercadoGanaderoApplication.class, args);
    }
}