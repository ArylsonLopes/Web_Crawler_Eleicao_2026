# Web_Crawler_Eleicao_2026

Script em Shell (`buscador.sh`) que consulta os resultados divulgados pelo TSE e exibe os candidatos em tabelas, por cargo.

Projeto da disciplina de Engenharia de Software (UNIFACIMP WYDEN), evoluído em dupla com **pair programming** e práticas de **Extreme Programming (XP)**.

**Dupla:** Arylson Simão Lopes e Davy Lopes da Cruz

## Diagnóstico inicial (antes de alterar o código)

Pontos encontrados ao executar e ler a versão original:

| # | Problema | Impacto |
|---|---|---|
| 1 | Município fixo (`07242`) como padrão | Só um município era consultado |
| 2 | Apenas um conjunto de códigos de eleição (1º turno) | Impossível consultar o 2º turno |
| 3 | Tabela mostra nome, número e votos, sem situação | Não dá para saber quem foi eleito |
| 4 | Qualquer falha (`die`) interrompe o script inteiro | Um dado ausente impede ver os demais resultados |
| 5 | Configuração apenas por variáveis de ambiente, sem `--help` | Uso pouco descoberto |
| 6 | Alinhamento da tabela quebra com acentos (`printf` conta bytes) | Tabelas desalinhadas |
| 7 | Mensagem de erro do curl repetida a cada tentativa | Mensagens confusas |
| 8 | Tabela vazia sem explicação | Usuário sem feedback |

## Melhorias planejadas

1. `--help` e opções de linha de comando, com mensagens de erro claras.
2. Consultar **todos os municípios do Maranhão**.
3. Falha em um cargo/município vira aviso, e o script continua.
4. Consultar **1º e 2º turno** separadamente.
5. **Indicar os candidatos eleitos** na tabela.
6. Corrigir o alinhamento com acentos e a mensagem de erro do curl.
