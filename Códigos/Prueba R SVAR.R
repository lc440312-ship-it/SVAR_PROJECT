# ==============================================================================
# 1. VERIFICACIÓN, INSTALACIÓN Y CARGA DE LIBRERÍAS
# ==============================================================================
# Lista de paquetes requeridos (Sin 'svars' ni 'gsl' para evitar errores)
paquetes_requeridos <- c(
  "readxl",     # Para leer el Excel
  "dplyr",      # Manipulación de datos
  "vars",       # Estimación de modelos VAR, IRF, FEVD y Restricciones
  "urca",       # Pruebas de raíz unitaria y cointegración
  "forecast",   # Pronósticos
  "tseries",    # Series de tiempo
  "tidyverse",  # Ecosistema de datos (incluye ggplot2, purrr, etc.)
  "ggplot2",    # Gráficos avanzados
  "purrr",      # Programación funcional
  "reshape2"    # Transformación de datos
)

# Identificar cuáles paquetes NO están instalados actualmente
paquetes_faltantes <- paquetes_requeridos[!(paquetes_requeridos %in% installed.packages()[,"Package"])]

# Instalar los paquetes que falten
if(length(paquetes_faltantes) > 0) {
  message("Instalando paquetes faltantes: ", paste(paquetes_faltantes, collapse = ", "))
  install.packages(paquetes_faltantes, dependencies = TRUE)
}

# Cargar todos los paquetes silenciosamente
invisible(lapply(paquetes_requeridos, library, character.only = TRUE))
message("¡Éxito! Todos los paquetes se han cargado correctamente.")


# ==============================================================================
# 2. DIRECTORIO DE TRABAJO Y CARGA DE DATOS
# ==============================================================================
ruta_archivo <- "C:/Users/Usuario/Downloads/TABLA DE DATOS SVAR.xlsx"

# Leer el Excel
df <- read_excel(ruta_archivo)

# Convertir Fecha a formato Date para gráficos
df$Fecha <- as.Date(df$Fecha)


# ==============================================================================
# 3. EXPLORACIÓN Y PREPARACIÓN DE DATOS
# ==============================================================================
# Eliminar filas con NAs si las hay
DATA_SVAR <- df %>% filter(complete.cases(.))

# Reorganizando los datos a formato largo para graficar
DATA_long <- DATA_SVAR %>%
  pivot_longer(cols = c(EXPORTACIONES, IMAE, PIO, IPI),
               names_to = "Indicator",
               values_to = "Value")

# Gráfico inicial de las series
grafico_series <- ggplot(DATA_long, aes(x = Fecha, y = Value)) +
  geom_line(color = "steelblue") +
  facet_wrap(~ Indicator, ncol = 1, scales = "free_y") +
  theme_minimal() +
  labs(title = "Evolución de los Indicadores Económicos (2022 - 2025)",
       x = "Fecha", y = "Valor")
print(grafico_series)
ggsave(filename = file.path(dirname(ruta_archivo), "01_series_temporales.png"), 
       plot = grafico_series, width = 10, height = 8, dpi = 300)

# Transformar los datos a formato de serie de tiempo (ts)
# Inicio: Enero 2022, Frecuencia: 12 (Mensual)
# Orden de variables: De la más exógena a la más endógena
vars_orden <- c("EXPORTACIONES", "IMAE", "PIO", "IPI")
tsd <- ts(DATA_SVAR[vars_orden], 
          start = c(2022, 1), 
          frequency = 12)


# ==============================================================================
# 4. MODELO VAR Y SVAR CON IDENTIFICACIÓN DE CHOLESKY
# ==============================================================================

# Criterios de información para elegir el número de rezagos (lag.max = 6 por muestra pequeña)
VARselect(tsd, lag.max = 6, type = "const") 

# Estimación del VAR en forma reducida (usamos p = 2, ajusta si VARselect sugiere otro)
var_model <- VAR(tsd, p = 2, type = "const")
print(summary(var_model))

# Prueba de Estabilidad
roots_var <- roots(var_model)
if(all(abs(roots_var) < 1)) {
  message("\nEXITO: Todas las raíces tienen módulo < 1. El VAR es estable.")
} else {
  warning("\nCUIDADO: El VAR NO es estable. Revisa si necesitas diferenciar las series.")
}

# Prueba de Causalidad de Granger
variables <- colnames(var_model$y)
for (var in variables) {
  causes <- setdiff(variables, var)
  granger_test <- causality(var_model, cause = causes)
  cat("\n--- Prueba de Causalidad de Granger para", var, "---\n")
  print(granger_test$Granger)
}

# --- Funciones de Impulso-Respuesta (IRF) ---
irf_results <- irf(
  var_model,
  impulse = vars_orden,
  response = vars_orden,
  n.ahead = 12, # 12 meses hacia adelante
  ortho = TRUE, # Identificación de Cholesky
  boot = TRUE,
  runs = 1000
)

# Normalizar cada impulso a una unidad
for (impulse_var in vars_orden) {
  initial_impact <- irf_results$irf[[impulse_var]][1, impulse_var]
  
  if (abs(initial_impact) > 1e-5) {
    # Si dividimos por un número negativo, debemos intercambiar Lower y Upper
    # para que el Ribbon de ggplot funcione correctamente (ymin < ymax)
    if (initial_impact < 0) {
      temp_lower <- irf_results$Lower[[impulse_var]] / initial_impact
      temp_upper <- irf_results$Upper[[impulse_var]] / initial_impact
      irf_results$Lower[[impulse_var]] <- temp_upper
      irf_results$Upper[[impulse_var]] <- temp_lower
    } else {
      irf_results$Lower[[impulse_var]] <- irf_results$Lower[[impulse_var]] / initial_impact
      irf_results$Upper[[impulse_var]] <- irf_results$Upper[[impulse_var]] / initial_impact
    }
    irf_results$irf[[impulse_var]] <- irf_results$irf[[impulse_var]] / initial_impact
  }
}

# Extraer datos de IRF para ggplot
irf_data <- map_dfr(names(irf_results$irf), function(impulse_var) {
  irf_mat <- irf_results$irf[[impulse_var]]
  lower_mat <- irf_results$Lower[[impulse_var]]
  upper_mat <- irf_results$Upper[[impulse_var]]
  
  tibble(
    horizon = rep(0:(nrow(irf_mat)-1), times = ncol(irf_mat)),
    impulse = impulse_var,
    response = rep(colnames(irf_mat), each = nrow(irf_mat)),
    irf = as.vector(irf_mat),
    lower = as.vector(lower_mat),
    upper = as.vector(upper_mat)
  )
})

irf_data <- irf_data %>% mutate(across(c(impulse, response), factor, levels = vars_orden))

# Gráfico IRF
grafico_irf <- ggplot(irf_data, aes(x = horizon, y = irf)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black", linewidth = 0.5) +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "steelblue", alpha = 0.2) +
  geom_line(color = "steelblue", linewidth = 1) +
  facet_wrap(~ response + impulse, scales = "free", ncol = 4, labeller = label_both) +
  theme_minimal(base_size = 12) +
  labs(
    title = "Funciones de Impulso-Respuesta (Descomposición de Cholesky)",
    subtitle = paste("Generado:", Sys.time()),
    x = "Horizonte (Meses)", y = "Respuesta",
    caption = "Intervalos de Confianza 95% vía Bootstrap"
  ) +
  theme(strip.text = element_text(face = "bold"),
        panel.grid.major = element_line(color = "gray90"),
        panel.grid.minor = element_blank())
print(grafico_irf)
ggsave(filename = file.path(dirname(ruta_archivo), "02_irf_cholesky.png"), 
       plot = grafico_irf, width = 12, height = 10, dpi = 300)

# --- Descomposición de Varianza (FEVD) ---
fevd_results <- fevd(var_model, n.ahead = 12)

fevd_data <- map_dfr(names(fevd_results), function(response_var) {
  as_tibble(fevd_results[[response_var]]) %>%
    mutate(horizon = row_number(), response = response_var) %>%
    pivot_longer(-c(horizon, response), names_to = "impulse", values_to = "variance_share")
}) %>%
  mutate(impulse = factor(impulse, levels = vars_orden))

grafico_fevd <- ggplot(fevd_data, aes(x = horizon, y = variance_share, fill = impulse)) +
  geom_area(color = "white", alpha = 0.8) +
  facet_wrap(~ response, scales = "free_y") +
  labs(
    title = "Descomposición de Varianza del Error de Pronóstico (FEVD)",
    x = "Horizonte (Meses)", y = "Proporción de Varianza Explicada", fill = "Shock de:"
  ) +
  theme_minimal() + theme(legend.position = "bottom")
print(grafico_fevd)
ggsave(filename = file.path(dirname(ruta_archivo), "03_fevd.png"), 
       plot = grafico_fevd, width = 10, height = 8, dpi = 300)


# ==============================================================================
# 5. MODELO SVAR RESTRINGIDO
# ==============================================================================

# Parámetros del VAR para las restricciones
K <- ncol(tsd)
p <- var_model$p
restr_mat <- matrix(1, nrow = K, ncol = K * p + 1)
colnames(restr_mat) <- c(paste0("L", rep(1:p, each = K), ".", rep(colnames(tsd), p)), "const")
rownames(restr_mat) <- colnames(tsd)

# Aplicar restricciones personalizadas:
# NOTA: La matriz se inicializa con 1s (todo influye a todo). Solo imponemos 0s donde queremos restringir.

# 1. Ecuación EXPORTACIONES: Depende de TODOS los rezagos. (Se deja con 1s).
# 2. Ecuación IMAE: Depende de TODOS los rezagos. (Se deja con 1s).

# 3. Ecuación IPI: Solo depende de sus propios rezagos (restringir EXPORTACIONES, IMAE, PIO)
vars_ajenos_ipi <- c("EXPORTACIONES", "IMAE", "PIO")
for (var in vars_ajenos_ipi) {
  for (lag in 1:p) restr_mat["IPI", paste0("L", lag, ".", var)] <- 0
}

# 4. Ecuación PIO: Solo depende de sus propios rezagos (restringir EXPORTACIONES, IMAE, IPI)
vars_ajenos_pio <- c("EXPORTACIONES", "IMAE", "IPI")
for (var in vars_ajenos_pio) {
  for (lag in 1:p) restr_mat["PIO", paste0("L", lag, ".", var)] <- 0
}

message("\nMatriz de Restricciones Aplicada:")
print(restr_mat)

# Estimación del VAR Restringido
var_restricted <- restrict(var_model, method = "manual", resmat = restr_mat)
print(summary(var_restricted))

# --- IRF del VAR Restringido ---
irf_rest <- irf(var_restricted, impulse = vars_orden, response = vars_orden,
                n.ahead = 12, ortho = TRUE, boot = TRUE, runs = 1000)

for (impulse_var in vars_orden) {
  initial_impact <- irf_rest$irf[[impulse_var]][1, impulse_var]
  
  if (abs(initial_impact) > 1e-5) {
    # Corrección de inversión de intervalos para valores negativos
    if (initial_impact < 0) {
      temp_lower <- irf_rest$Lower[[impulse_var]] / initial_impact
      temp_upper <- irf_rest$Upper[[impulse_var]] / initial_impact
      irf_rest$Lower[[impulse_var]] <- temp_upper
      irf_rest$Upper[[impulse_var]] <- temp_lower
    } else {
      irf_rest$Lower[[impulse_var]] <- irf_rest$Lower[[impulse_var]] / initial_impact
      irf_rest$Upper[[impulse_var]] <- irf_rest$Upper[[impulse_var]] / initial_impact
    }
    irf_rest$irf[[impulse_var]] <- irf_rest$irf[[impulse_var]] / initial_impact
  }
}

irf_data_rest <- map_dfr(names(irf_rest$irf), function(impulse_var) {
  tibble(
    horizon = rep(0:(nrow(irf_rest$irf[[impulse_var]])-1), times = ncol(irf_rest$irf[[impulse_var]])),
    impulse = impulse_var,
    response = rep(colnames(irf_rest$irf[[impulse_var]]), each = nrow(irf_rest$irf[[impulse_var]])),
    irf = as.vector(irf_rest$irf[[impulse_var]]),
    lower = as.vector(irf_rest$Lower[[impulse_var]]),
    upper = as.vector(irf_rest$Upper[[impulse_var]])
  )
}) %>% mutate(across(c(impulse, response), factor, levels = vars_orden))

grafico_irf_rest <- ggplot(irf_data_rest, aes(x = horizon, y = irf)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black", linewidth = 0.5) +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "darkgreen", alpha = 0.2) +
  geom_line(color = "darkgreen", linewidth = 1) +
  facet_wrap(~ response + impulse, scales = "free", ncol = 4, labeller = label_both) +
  theme_minimal(base_size = 12) +
  labs(
    title = "IRF - Modelo SVAR Restringido",
    subtitle = paste("Generado:", Sys.time()),
    x = "Meses", y = "Respuesta"
  ) +
  theme(strip.text = element_text(face = "bold"))
print(grafico_irf_rest)
ggsave(filename = file.path(dirname(ruta_archivo), "04_irf_restringido.png"), 
       plot = grafico_irf_rest, width = 12, height = 10, dpi = 300)

message("\n¡Proceso finalizado! Se han guardado 4 gráficos PNG en la carpeta: ", dirname(ruta_archivo))