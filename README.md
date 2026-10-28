# Web_Crawler_Eleicao_2026

Script em Shell (`buscador.sh`) que consulta os resultados divulgados pelo TSE e exibe os candidatos em tabelas, por cargo.
Projeto evoluído em dupla, com **pair programming** e práticas de **Extreme Programming (XP)**, na disciplina de Engenharia de Software (UNIFACIMP WYDEN).

**Dupla:** Arylson Simão Lopes e Davy Lopes da Cruz

## Objetivo

Evoluir o script original, que consultava **um único município fixo** e **apenas o 1º turno**, para:

1. retornar resultados de **todos os municípios do Maranhão**;
2. permitir consultar e exibir **1º e 2º turno separadamente**;
3. **indicar claramente os candidatos eleitos**;
4. corrigir fragilidades e melhorar legibilidade, mensagens de erro e manutenção.

## Pré-requisitos

- Bash 4.4 ou superior (Linux, macOS com bash atualizado, ou WSL no Windows)
- `curl`
- `jq`
- Acesso à internet (para `https://resultados.tse.jus.br`)

```bash
sudo apt install curl jq      # Debian/Ubuntu/WSL
```

## Como executar

```bash
chmod +x buscador.sh
./buscador.sh --help
```

| Opção | Descrição | Padrão |
|---|---|---|
| `-t, --turno 1\|2\|ambos` | Turno exibido | `1` |
| `-m, --municipio CODIGOS` | `todos` ou códigos TSE de 5 dígitos separados por vírgula | `todos` |
| `-u, --uf UF` | Sigla da UF | `ma` |
| `-l, --limite N` | Candidatos por cargo (eleitos sempre aparecem) | `20` |
| `-e, --so-eleitos` | Mostra somente os eleitos | desligado |
| `-h, --help` | Ajuda | |

Variáveis de ambiente (opcionais, mantidas por compatibilidade com a versão original):
`TSE_RESULTS_BASE_URL`, `TSE_RESULTS_YEAR`, `TSE_RESULTS_UF`, `TSE_RESULTS_MUNICIPALITY`, `TSE_RESULTS_TURN`, `TSE_RESULTS_LIMIT`, `TSE_RESULTS_COLOR`, `TSE_RESULTS_FEDERAL_ELECTION`, `TSE_RESULTS_STATE_ELECTION`, `TSE_RESULTS_FEDERAL_ELECTION_2T`, `TSE_RESULTS_STATE_ELECTION_2T`.

### Exemplos de uso

```bash
./buscador.sh                              # todos os municípios do MA, 1º turno
./buscador.sh -m 07242                     # apenas um município
./buscador.sh -e                           # só os eleitos, em todos os municípios
./buscador.sh -t ambos -e                  # eleitos do 1º e do 2º turno, separados

# 2º turno exige os códigos de eleição do 2º turno (ver abaixo)
TSE_RESULTS_FEDERAL_ELECTION_2T=<codigo> \
TSE_RESULTS_STATE_ELECTION_2T=<codigo> \
./buscador.sh -t 2
```

**Códigos de eleição do 2º turno:** o TSE usa um código de eleição diferente para cada turno. Para descobri-los, abra `https://resultados.tse.jus.br`, selecione o 2º turno e, nas ferramentas do navegador (F12 → Rede/Network), veja o número que aparece na URL `.../ele2026/<codigo>/dados/...`. Apenas presidente (cargo 1) e governador (cargo 3) têm 2º turno; os demais cargos são ignorados nessa consulta.

## Diagnóstico inicial (antes de alterar o código)

Pontos encontrados ao executar e ler a versão original:

| # | Problema | Impacto |
|---|---|---|
| 1 | Município fixo (`07242`) como padrão | Só um município era consultado |
| 2 | Apenas um conjunto de códigos de eleição (1º turno) | Impossível consultar o 2º turno |
| 3 | Tabela mostra nome, número e votos, sem situação | Não dava para saber quem foi eleito |
| 4 | Qualquer falha (`die`) interrompia o script inteiro | Um dado ausente impedia ver os demais resultados |
| 5 | Configuração apenas por variáveis de ambiente, sem `--help` | Uso pouco descoberto |
| 6 | Alinhamento da tabela quebrava com acentos (`printf` conta bytes) | Tabelas desalinhadas (ex.: JOÃO, NÚMERO) |
| 7 | Mensagem de erro do curl repetida a cada tentativa | Mensagens confusas |
| 8 | Tabela vazia gerava saída sem explicação | Usuário sem feedback |

## Melhorias e correções realizadas

- **Todos os municípios:** o script lê a lista de municípios da UF no arquivo de configuração do TSE (`config/mun-e<eleição>-cm.json`) e percorre cada um; `--municipio` permite restringir.
- **Turnos separados:** `--turno 1|2|ambos`, com cabeçalho `1º TURNO` / `2º TURNO` e códigos de eleição próprios por turno.
- **Eleitos:** nova coluna `SITUAÇÃO` (`ELEITO`, `2º TURNO` ou `-`), linha destacada em verde quando há cores, e `--so-eleitos`. Eleitos nunca são cortados pelo `--limite`.
- **Robustez:** falha em um cargo/município vira aviso e o script continua; resumo final de consultas com sucesso e sem dados; código de saída 1 se nada foi obtido.
- **Legibilidade/manutenção:** funções pequenas (`list_municipios`, `show_cargo`, `election_for`, `print_table`), `--help`, validação de parâmetros com mensagens em português, alinhamento correto com acentos.

## Pair programming e XP

> **Atenção:** preencher a tabela abaixo com a divisão real de Driver/Navigator da dupla.

O código foi desenvolvido com auxílio do Claude (Anthropic); os commits trazem o trailer `Co-Authored-By`.

| Ciclo | Mudança | Driver | Navigator |
|---|---|---|---|
| 1 | Diagnóstico e plano no README | (preencher) | (preencher) |
| 2 | `--help`, argumentos e mensagens de erro | (preencher) | (preencher) |
| 3 | Todos os municípios do MA | (preencher) | (preencher) |
| 4 | Falhas viram aviso (script continua) | (preencher) | (preencher) |
| 5 | 1º e 2º turno | (preencher) | (preencher) |
| 6 | Indicação de eleitos | (preencher) | (preencher) |
| 7 | Alinhamento com acentos | (preencher) | (preencher) |

Práticas aplicadas: pair programming com troca de papéis a cada ciclo; pequenas mudanças (uma melhoria por vez); feedback curto (execução do script após cada alteração); refatoração contínua; integração frequente com commits pequenos e descritivos.

## Evidências de validação

### Validação com dados simulados (já realizada)

Como o site do TSE não estava acessível no ambiente de desenvolvimento, os cenários foram testados com arquivos JSON simulados no mesmo formato do TSE (`TSE_RESULTS_BASE_URL=file://...`). Saídas reais:

```text
$ ./buscador.sh -m 07242 -l 2
### município 07242 (07242) - 1º turno
  Cargo6 (cargo 6)
+------------+--------+-------+----------+
| NOME       | NÚMERO | VOTOS | SITUAÇÃO |
+------------+--------+-------+----------+
| BRUNO LIMA |   5555 |  7000 | -        |
| ANA SILVA  |   1234 |  5000 | ELEITO   |
+------------+--------+-------+----------+

$ ./buscador.sh -m 07242 -e
  Cargo6 (cargo 6)
+-----------+--------+-------+----------+
| NOME      | NÚMERO | VOTOS | SITUAÇÃO |
+-----------+--------+-------+----------+
| ANA SILVA |   1234 |  5000 | ELEITO   |
+-----------+--------+-------+----------+

$ TSE_RESULTS_FEDERAL_ELECTION_2T=7001 TSE_RESULTS_STATE_ELECTION_2T=7002 ./buscador.sh -t 2 -m 07242
==================== 2º TURNO ====================
  Governador (cargo 3)
+-------+--------+-------+----------+
| NOME  | NÚMERO | VOTOS | SITUAÇÃO |
+-------+--------+-------+----------+
| JOÃO  |     13 |  9000 | ELEITO   |
| MARIA |     22 |  8000 | -        |
+-------+--------+-------+----------+

$ ./buscador.sh -t 3
Erro: turno deve ser 1, 2 ou ambos
```

### Validação com o TSE real

> **[PENDENTE - a dupla deve executar com internet e colar aqui a saída, data/hora e prints]**

Cenários a executar:

| Cenário | Comando | Resultado esperado |
|---|---|---|
| Ajuda | `./buscador.sh --help` | Mostra opções |
| Todos os municípios | `./buscador.sh -l 3` | Uma seção por município do MA |
| Município único | `./buscador.sh -m 07242` | Apenas esse município |
| Eleitos | `./buscador.sh -e` | Só linhas `ELEITO` |
| 1º turno | `./buscador.sh -t 1` | Cabeçalho `1º TURNO` |
| 2º turno | `./buscador.sh -t 2` (com códigos `_2T`) | Cabeçalho `2º TURNO`, só presidente/governador |
| 2º turno sem códigos | `./buscador.sh -t 2` | Aviso claro e saída com erro |
| Parâmetro inválido | `./buscador.sh -t 3` | `Erro: turno deve ser 1, 2 ou ambos` |
| Sem `jq` | remover `jq` do PATH | `Erro: jq não encontrado ...` |
| Município inexistente | `./buscador.sh -m 99999` | Aviso por cargo e código de saída 1 |

## Limitações conhecidas

- Os códigos de eleição do 2º turno precisam ser informados (variáveis `*_2T`).
- Para cargos estaduais/federais, os votos exibidos são os do município, e a situação `ELEITO` vem do campo informado pelo TSE para o candidato; confira no site oficial.
- Consultar os ~217 municípios faz centenas de requisições e pode demorar.
