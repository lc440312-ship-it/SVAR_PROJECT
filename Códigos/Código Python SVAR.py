# ==============================================================================
# 1. INSTALACIÓN Y CARGA DE LIBRERÍAS
# ==============================================================================
# Equivalentes a: readxl, dplyr, vars, urca, forecast, tseries, tidyverse, ggplot2
# pip install pandas openpyxl statsmodels matplotlib seaborn numpy

# Configuración para evitar ventanas emergentes (Headless mode)
import os
from statsmodels.tsa.vector_ar.var_model import VARProcess
import seaborn as sns
import matplotlib.pyplot as plt
from statsmodels.tsa.api import VAR
import statsmodels.api as sm
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')

# Clase necesaria para reconstruir el SVAR manual

print("¡Éxito! Todas las librerías se han cargado correctamente.")

# ==============================================================================
# 2. DIRECTORIO DE TRABAJO Y CARGA DE DATOS
# ==============================================================================
ruta_archivo = "C:/Users/Usuario/Downloads/TABLA DE DATOS SVAR.xlsx"
directorio_salida = os.path.dirname(ruta_archivo)

# Leer el Excel
if not os.path.exists(ruta_archivo):
    print(f"ERROR: No se encuentra el archivo en {ruta_archivo}")
    # Creamos datos dummy solo si no existe el archivo para evitar crash
    dates = pd.date_range(start='2022-01-01', periods=40, freq='M')
    data = np.random.randn(40, 4)
    df = pd.DataFrame(data, columns=["EXPORTACIONES", "IMAE", "PIO", "IPI"])
    df['Fecha'] = dates
else:
    df = pd.read_excel(ruta_archivo)

# Convertir Fecha a formato Datetime
df['Fecha'] = pd.to_datetime(df['Fecha'])

# ==============================================================================
# 3. EXPLORACIÓN Y PREPARACIÓN DE DATOS
# ==============================================================================
# Eliminar filas con NAs
DATA_SVAR = df.dropna()

# Reorganizar datos para graficar
DATA_long = DATA_SVAR.melt(
    id_vars=['Fecha'],
    value_vars=["EXPORTACIONES", "IMAE", "PIO", "IPI"],
    var_name="Indicator",
    value_name="Value"
)

# Gráfico inicial de las series
plt.figure(figsize=(10, 8))
g = sns.FacetGrid(DATA_long, col="Indicator", col_wrap=1,
                  sharey=False, aspect=3, height=2)
g.map(sns.lineplot, "Fecha", "Value", color="steelblue")
g.fig.suptitle("Evolución de los Indicadores Económicos (2022 - 2025)", y=1.02)
plt.savefig(os.path.join(directorio_salida,
            "01_series_temporales.png"), dpi=300, bbox_inches='tight')
plt.close()  # Cerramos el gráfico para no bloquear ejecución

# Transformar datos a Series de Tiempo
DATA_SVAR.set_index('Fecha', inplace=True)

# Orden de variables: De la más exógena a la más endógena
vars_orden = ["EXPORTACIONES", "IMAE", "PIO", "IPI"]
tsd = DATA_SVAR[vars_orden]

# ==============================================================================
# 4. MODELO VAR Y SVAR CON IDENTIFICACIÓN DE CHOLESKY
# ==============================================================================

# Criterios de información
model_selection = VAR(tsd)
selection_results = model_selection.select_order(maxlags=6)
print("\n--- Criterios de Selección de Rezagos ---")
print(selection_results.summary())

# Estimación del VAR
p = 2
var_model = VAR(tsd)
var_results = var_model.fit(p)
print("\n--- Resumen del Modelo VAR ---")
print(var_results.summary())

# Prueba de Estabilidad
# Usamos is_stable() que verifica raíces del polinomio > 1 (equivalente a eigen < 1 en R)
if var_results.is_stable():
    print("\nEXITO: El VAR es estable (Raíces fuera del círculo unitario).")
else:
    print("\nCUIDADO: El VAR NO es estable. Revisa si necesitas diferenciar las series.")

# Prueba de Causalidad de Granger
print("\n--- Pruebas de Causalidad de Granger ---")
for var in vars_orden:
    causes = [c for c in vars_orden if c != var]
    test_result = var_results.test_causality(var, causes, kind='f')
    print(f"Variable dependiente: {var}")
    print(test_result.summary())

# --- Funciones de Impulso-Respuesta (IRF) Cholesky ---
irf_results = var_results.irf(periods=12)
irf_vals = irf_results.orth_irfs  # Matriz (periodos x impulso x respuesta)

fig, axes = plt.subplots(nrows=len(vars_orden), ncols=len(
    vars_orden), figsize=(12, 10), sharex=True)
fig.suptitle(
    "Funciones de Impulso-Respuesta (Descomposición de Cholesky)", fontsize=16)

for i, response in enumerate(vars_orden):  # Fila
    for j, impulse in enumerate(vars_orden):  # Columna
        ax = axes[i, j]
        # Serie de tiempo del impulso j a la respuesta i
        # CORRECCIÓN: statsmodels usa [periodo, respuesta, impulso]
        series = irf_vals[:, i, j]

        # CORRECCIÓN: Normalizar por el impacto diagonal del SHOCK (como en R)
        # no por el impacto inicial de cada respuesta individual.
        diagonal_impact = irf_vals[0, j, j]
        if abs(diagonal_impact) > 1e-5:
            series = series / diagonal_impact

        ax.plot(series, color='steelblue', linewidth=1)
        ax.axhline(0, color='black', linestyle='--', linewidth=0.5)

        if i == 0:
            ax.set_title(f"Impulso: {impulse}", fontsize=10, weight='bold')
        if j == 0:
            ax.set_ylabel(f"Respuesta: {response}", fontsize=10, weight='bold')
        if i == len(vars_orden) - 1:
            ax.set_xlabel("Horizonte (Meses)", fontsize=9)

        ax.grid(True, linestyle=':', alpha=0.6)

plt.tight_layout(rect=[0, 0, 1, 0.95])
plt.savefig(os.path.join(directorio_salida, "02_irf_cholesky.png"), dpi=300)
plt.close()

# --- Descomposición de Varianza (FEVD) ---
fevd_results = var_results.fevd(12)
print("\n--- Descomposición de Varianza (FEVD) ---")
print(fevd_results.summary())

# Gráfico FEVD con Título Corregido
fig_fevd = fevd_results.plot()
fig_fevd.suptitle("Descomposición de Varianza del Error de Pronóstico (FEVD)",
                  fontsize=14, y=0.98)
plt.savefig(os.path.join(directorio_salida, "03_fevd.png"),
            dpi=300, bbox_inches='tight')
plt.close()


# ==============================================================================
# 5. MODELO SVAR RESTRINGIDO
# ==============================================================================
print("\n--- Estimando Modelo VAR Restringido (Subset VAR) ---")

# Preparar datos con rezagos (Lags)
data_lags = tsd.copy()
cols_lags = []
for lag in range(1, p + 1):
    for col in vars_orden:
        name = f"L{lag}.{col}"
        data_lags[name] = data_lags[col].shift(lag)
        cols_lags.append(name)

# Limpiar NAs generados por los rezagos
data_lags.dropna(inplace=True)

# Definir restricciones (Garantía de Especificación)
# - EXPORTACIONES e IMAE: Endógenas (Dependen de todo el sistema)
# - PIO e IPI: Exógenas en rezagos (Solo dependen de su propia historia)
restrictions_map = {
    "EXPORTACIONES": ["EXPORTACIONES", "IMAE", "PIO", "IPI"],
    "IPI":           ["IPI"],
    "PIO":           ["PIO"],
    "IMAE":          ["EXPORTACIONES", "IMAE", "PIO", "IPI"]
}

# --- VISUALIZACIÓN DE LA MATRIZ DE RESTRICCIÓN ---
print("\n--- Matriz de Restricción Implícita (1=Incluido, 0=Restringido) ---")
header_cols = [f"L{l}.{v[:3]}" for l in range(1, p+1) for v in vars_orden]
print(f"{'Ecuación':<15} | {'  '.join(header_cols)}")

for target in vars_orden:
    row_str = []
    for lag in range(1, p+1):
        for var in vars_orden:
            # Si la variable está en la lista permitida, es un 1, sino 0
            val = "1" if var in restrictions_map[target] else "0"
            row_str.append(f"{val:<6}")
    print(f"{target:<15} | {'  '.join(row_str)}")

# Contenedores para reconstruir el VARProcess
fitted_coefs = np.zeros((p, len(vars_orden), len(vars_orden)))
fitted_intercepts = np.zeros(len(vars_orden))
residuals = pd.DataFrame(index=data_lags.index, dtype=float)

for i, target_var in enumerate(vars_orden):
    # Variable dependiente
    y = data_lags[target_var]

    # Construir lista de regresores permitidos
    allowed_vars = restrictions_map[target_var]
    regressors_cols = []
    for lag in range(1, p + 1):
        for v in allowed_vars:
            regressors_cols.append(f"L{lag}.{v}")

    # Matriz X con constante
    X = sm.add_constant(data_lags[regressors_cols])

    # Ajuste OLS ecuación por ecuación
    model_ols = sm.OLS(y, X).fit()

    # Guardar residuos e intercepto
    residuals[target_var] = model_ols.resid
    if 'const' in model_ols.params:
        fitted_intercepts[i] = model_ols.params['const']

    # Mapear coeficientes a la matriz 3D
    # Coefs structure para VARProcess: [lag_idx, equation_idx, variable_idx]
    for lag in range(1, p + 1):
        for j, input_var in enumerate(vars_orden):
            # Buscamos si existe el coeficiente L{lag}.{variable} en esta ecuación
            param_name = f"L{lag}.{input_var}"
            if param_name in model_ols.params:
                fitted_coefs[lag-1, i, j] = model_ols.params[param_name]
            else:
                # Si no está, se mantiene en 0 (restricción impuesta)
                fitted_coefs[lag-1, i, j] = 0.0

# Matriz de covarianza de residuos (Sigma_u)
sigma_u_rest = residuals.cov()

# NOTE: coefs_exog expects a matrix of shape (K, M), where K is the number of
# variables and M is the number of exogenous variables.  In our case, we have
# K=4 variables and M=1 (the constant).

# Reconstruir proceso VAR manual
var_proc_rest = VARProcess(
    coefs=fitted_coefs,
    # NOTE: reshape intercepts to be (4, 1)
    coefs_exog=fitted_intercepts.reshape(-1, 1),
    sigma_u=sigma_u_rest,
    names=vars_orden
)

# --- IRF del VAR Restringido ---
# VARProcess no tiene método .irf(), usamos .orth_ma_rep() directamente.
# maxn=13 equivale a periods=12 (t=0 hasta t=12)
irf_rest_vals = var_proc_rest.orth_ma_rep(maxn=13)

# Gráfico Manual
fig2, axes2 = plt.subplots(nrows=len(vars_orden), ncols=len(
    vars_orden), figsize=(12, 10), sharex=True)
fig2.suptitle("IRF - Modelo SVAR Restringido", fontsize=16)

for i, response in enumerate(vars_orden):
    for j, impulse in enumerate(vars_orden):
        ax = axes2[i, j]
        # Serie de tiempo del impulso j a la respuesta i
        # CORRECCIÓN: statsmodels usa [periodo, respuesta, impulso]
        series = irf_rest_vals[:, i, j]

        # CORRECCIÓN: Normalizar por el impacto diagonal del SHOCK (como en R)
        # no por el impacto inicial de cada respuesta individual.
        diagonal_impact = irf_rest_vals[0, j, j]
        if abs(diagonal_impact) > 1e-5:
            series = series / diagonal_impact

        ax.plot(series, color='darkgreen', linewidth=1)
        ax.axhline(0, color='black', linestyle='--', linewidth=0.5)

        if i == 0:
            ax.set_title(f"Impulso: {impulse}", fontsize=10, weight='bold')
        if j == 0:
            ax.set_ylabel(f"Respuesta: {response}", fontsize=10, weight='bold')
        if i == len(vars_orden) - 1:
            ax.set_xlabel("Meses", fontsize=9)

        ax.grid(True, linestyle=':', alpha=0.6)

plt.tight_layout(rect=[0, 0, 1, 0.95])
plt.savefig(os.path.join(directorio_salida, "04_irf_restringido.png"), dpi=300)
plt.close()

print(f"\n¡Proceso finalizado! Gráficos guardados en: {directorio_salida}")
