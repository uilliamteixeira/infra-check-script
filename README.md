# Infra Check Script

Utilitario para diagnostico e manutencao segura de computadores Windows, pensado para rotinas de suporte tecnico. Ele ajuda a registrar sinais de gargalo em equipamentos limitados — como notebooks com Celeron e 4 GB de RAM — sem aplicar "otimizacoes" arriscadas.

## O que ele faz

- coleta memoria total, memoria livre e percentual de uso;
- mostra espaco livre das unidades locais e alerta quando esta baixo;
- verifica Spooler, Windows Update e Microsoft Defender;
- lista processos com maior consumo de memoria e de CPU;
- consulta erros recentes do log do Sistema;
- lista itens de inicializacao para revisao manual;
- limpa temporarios do usuario e do Windows, alem da Lixeira;
- grava cada execucao em `logs/infra-check-AAAAMMDD-HHMMSS.log`.

## O que ele nao faz

O script nao desativa Windows Update, Defender, servicos do sistema ou arquivo de paginacao. Essas alteracoes podem mascarar o problema e reduzir a seguranca do computador. Ele tambem nao substitui diagnostico de hardware: disco degradado, superaquecimento e memoria insuficiente precisam de avaliacao tecnica.

## Como executar

1. Baixe ou clone o repositorio.
2. Clique com o botao direito em `infra-check.bat` e escolha **Executar como administrador**.
3. Escolha uma opcao no menu:
   - **1**: somente diagnostico;
   - **2**: somente manutencao segura;
   - **3**: diagnostico e manutencao na sequencia.
4. Consulte o arquivo criado na pasta `logs`.

Tambem e possivel executar o PowerShell diretamente:

```powershell
.\scripts\InfraCheck.ps1 -Mode Diagnose
.\scripts\InfraCheck.ps1 -Mode Maintenance
```

## Caso de uso: notebook com 4 GB de RAM

Em um equipamento limitado, os travamentos podem ser causados por memoria saturada, pouco espaco em disco, processos em segundo plano, atualizacoes, disco lento ou falha de hardware. Use primeiro o diagnostico e compare os logs antes e depois da manutencao. Se o uso de memoria continuar acima de 85% durante o trabalho normal, a melhoria mais efetiva costuma ser reduzir programas de inicializacao, instalar SSD e, quando suportado, ampliar a memoria para 8 GB.

## Requisitos

- Windows 10 ou 11;
- PowerShell 5.1 ou superior;
- permissao de administrador para a manutencao e a leitura completa de alguns dados do sistema.

## Estrutura

```text
infra-check-script/
├── infra-check.bat
├── scripts/InfraCheck.ps1
└── logs/
```
