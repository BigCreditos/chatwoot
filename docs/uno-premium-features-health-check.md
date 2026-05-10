# Uno premium features health check

Este runbook descreve a rotina que valida se uma instalacao esta com as configuracoes premium e as features padrao da Uno aplicadas.

## Quando usar

Use esta checagem depois de aplicar a migration `20251120120000_fix_uno_default_features_again.rb`, em deploys de cliente,
ou quando houver suspeita de que o plano/features voltaram para valores incorretos.

Migration corretiva:

```bash
bundle exec rails db:migrate:up VERSION=20251120120000
```

## Checagem manual

Rodar em uma instalacao local ou no container da aplicacao:

```bash
bundle exec rails chatwoot:ops:check_uno_premium_features
```

Via Docker:

```bash
docker exec -it <container_app> bundle exec rails chatwoot:ops:check_uno_premium_features
```

Para validar uma conta especifica:

```bash
ACCOUNT_ID=123 bundle exec rails chatwoot:ops:check_uno_premium_features
```

Resultado esperado:

```text
OK: Uno premium configs and account features are applied.
```

Se existir divergencia, a task retorna exit code `1` e lista os campos ou features incorretos.

## Checagem agendada

O Sidekiq agenda automaticamente o job `Internal::CheckUnoPremiumFeaturesJob` pelo `config/schedule.yml`.

Agendamento atual:

```yaml
check_uno_premium_features_job:
  cron: '0 2 * * *'
  class: 'Internal::CheckUnoPremiumFeaturesJob'
  queue: scheduled_jobs
```

Isso roda diariamente as `02:00 UTC` na fila `scheduled_jobs`.

Depois de deployar alteracoes no `config/schedule.yml`, reinicie o Sidekiq para recarregar o cron.

Para disparar manualmente pelo Rails:

```bash
bundle exec rails runner "Internal::CheckUnoPremiumFeaturesJob.perform_now"
```

## O que a rotina valida

- `INSTALLATION_PRICING_PLAN` deve estar como `premium`.
- `INSTALLATION_PRICING_PLAN_QUANTITY` deve estar como `1000000`.
- `CAPTAIN_CLOUD_PLAN_LIMITS` deve estar vazio.
- `ACCOUNT_LEVEL_FEATURE_DEFAULTS` deve refletir as features esperadas.
- As contas existentes devem estar com as features esperadas habilitadas/desabilitadas.

## Como corrigir divergencias

Se a rotina apontar divergencia, rode novamente a migration corretiva:

```bash
bundle exec rails db:migrate:up VERSION=20251120120000
```

Em seguida rode a checagem manual outra vez. Se o ambiente estiver em container, execute os comandos dentro do container da aplicacao.
