#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>
#include <stdbool.h>

/* Ligação ao AppleSMC. Abre em modo leitura; nunca escreve. */
bool   csmc_open(void);
void   csmc_close(void);

/* Lê uma chave de 4 caracteres e converte para double.
   Devolve false se a chave não existir ou o tipo não for suportado.
   `type_out` (>= 5 bytes) recebe o tipo SMC ("flt ", "ui16", ...). */
bool   csmc_read(const char *key, double *value_out, char *type_out);

/* Enumeração: número total de chaves e a chave no índice dado. */
uint32_t csmc_key_count(void);
bool     csmc_key_at(uint32_t index, char *key_out /* >= 5 bytes */);

#endif
