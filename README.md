# Desarrollo de un modelo SVAR con restricciones estructurales para cuantificar el impacto de choques externos (precios del oro y demanda industrial de EE. UU.) sobre las exportaciones nicaragüenses.

# Introducción
Este proyecto es un ejercicio de corte técnico y exploratorio, no busca responder de forma 100% rigurosa; busca solamente poner en práctica habilidades estadísticas aterrizandolas en un contexto económico. Los datos Nacionales IMAE y Exportaciones, fueron sacados de las bases de datos del BCN y las variables internacionales, el IPI de la FED y el PIO de Investing.com
El sector exportador de Nicaragua posee una dependencia estructural de factores exógenos y de la capacidad productiva interna. Este modelo busca capturar la sensibilidad de las Exportaciones ante tres pilares fundamentales:

- PIO (Precio Internacional del Oro): Representando la principal actividad minera del país.
- IPI (Índice de Producción Industrial de EE. UU.): Reflejando la demanda del principal socio comercial y destino de insumos industriales.
- IMAE: El indicador de la actividad económica interna, que funciona como termómetro de la capacidad de oferta.

<img width="3000" height="2400" alt="01_series_temporales" src="https://github.com/user-attachments/assets/d9c3b106-d247-4f09-9d9e-699606987f6a" />

# Metodología y resultados
Para el análisis se empleó un modelo Vector Autoregresivo Estructural (SVAR) con 2 rezagos ($p=2$), seleccionado bajo criterios de información (AIC/BIC).

- **Estabilidad del Modelo**: El sistema es estacionario, ya que todas las raíces del polinomio característico se encuentran fuera del círculo unitario. Esto garantiza que los choques representados en las funciones impulso-respuesta sean transitorios y que el modelo no genere divergencias explosivas a largo plazo.

- **Matriz de Restricción (Subset VAR)**: Se aplicó una estructura de "país pequeño". Se restringió el modelo para que el PIO y el IPI (variables globales) solo dependan de su propia historia en los rezagos, impidiendo que variables locales (IMAE o Exportaciones) influyan en los precios internacionales o la industria estadounidense.
<img width="729" height="147" alt="image" src="https://github.com/user-attachments/assets/8ff86d05-1d0c-4ebd-aeb9-4f693cd8a844" />

- Choque en PIO $\rightarrow$ Exportaciones: Se observa un impacto positivo y persistente. Dado que el oro es el principal rubro de exportación, un incremento en el precio internacional se traduce de forma casi inmediata en un mayor valor exportado. El efecto alcanza su madurez hacia el tercer mes y se estabiliza lentamente.

- Choque en IPI $\rightarrow$ Exportaciones: La respuesta es positiva, confirmando la hipótesis de que las exportaciones nicaragüenses actúan como insumos para la industria estadounidense. Una expansión en la manufactura de EE. UU. "jala" la demanda de productos locales.

- Choque en IMAE $\rightarrow$ Exportaciones: Existe una correlación procíclica clara. Un aumento en la actividad económica interna genera el excedente productivo necesario para colocar productos en el mercado exterior.

<img width="721" height="146" alt="image" src="https://github.com/user-attachments/assets/30e77df9-d69f-4e10-87aa-a57dc8005ec3" />

# Conclusiones

**Vulnerabilidad Exógena**: Las exportaciones de Nicaragua son altamente sensibles a factores que el país no controla (precios del oro y demanda industrial de EE. UU.). Esto subraya la importancia de la diversificación de mercados.

**Transmisión de Choques**: Los choques externos tienen una memoria de aproximadamente 6 a 8 meses antes de diluirse, lo que permite una ventana de planeación macroeconómica ante cambios en los precios internacionales.

**Validación del Modelo**: La estabilidad del VAR y el sentido económico de las restricciones impuestas validan este algoritmo como una herramienta robusta para la proyección de flujos comerciales bajo diferentes escenarios de precios de commodities.








