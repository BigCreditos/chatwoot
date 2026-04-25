# Plano de implementacao do Chatwoot para grupos Meta-like

Este plano cobre somente o lado do Chatwoot/ViperChat. A ideia e preparar o
Chatwoot para consumir grupos vindos da Uno API em formato Meta-like hoje e, no
futuro, conseguir usar WhatsApp Cloud/BSP oficial sem redesenhar banco, UI e
contratos internos.

## Objetivo

Implementar conversas em grupo como entidade estruturada:

- conversa marcada com `group: true`;
- identificador externo do grupo em `group_source_id`;
- titulo do grupo em `group_title`;
- membros reais em `group_contacts`;
- remetente real da mensagem em `messages.sender`;
- UI mostrando grupo, membros e remetente sem depender de prefixo textual.

O comportamento legado, em que o grupo vira um contato falso e o texto recebe
prefixo `*Nome*:`, deve continuar disponivel por flag durante o rollout.

## 1. Contrato de entrada esperado

O Chatwoot deve aceitar webhooks de grupo em formato Meta-like.

Payload minimo inbound:

```json
{
  "object": "whatsapp_business_account",
  "entry": [
    {
      "id": "WABA_OR_SESSION_ID",
      "changes": [
        {
          "field": "messages",
          "value": {
            "messaging_product": "whatsapp",
            "metadata": {
              "display_phone_number": "556600000000",
              "phone_number_id": "556600000000"
            },
            "contacts": [
              {
                "wa_id": "556699999999",
                "profile": {
                  "name": "Maria",
                  "picture": "https://cdn.exemplo.com/profile/maria.jpg"
                },
                "group_id": "120363040468224422@g.us",
                "group_subject": "Equipe Comercial",
                "group_picture": "https://cdn.exemplo.com/groups/120363040468224422.jpg"
              }
            ],
            "messages": [
              {
                "from": "556699999999",
                "id": "wamid.HBgMNTU2Njk5OTk5OTk5FQIAEhgUM0E...",
                "timestamp": "1710000000",
                "type": "text",
                "group_id": "120363040468224422@g.us",
                "text": {
                  "body": "Bom dia pessoal"
                }
              }
            ]
          }
        }
      ]
    }
  ]
}
```

Regras do Chatwoot:

- `messages[0].group_id` e o campo principal para identificar grupo.
- `contacts[0].group_id` pode ser usado como fallback legado.
- `messages[0].from` e `contacts[0].wa_id` representam o participante real.
- `group_subject` deve virar `conversation.group_title`.
- `group_picture` pode alimentar avatar/metadado do grupo.

## 2. Banco de dados

Criar migrations novas. Nao editar migrations antigas.

### Conversations

Adicionar:

```ruby
add_column :conversations, :group, :boolean, default: false, null: false
add_column :conversations, :group_source_id, :string
add_column :conversations, :group_title, :string

add_index :conversations, :group
add_index :conversations, [:inbox_id, :group_source_id],
          unique: true,
          where: "group_source_id IS NOT NULL",
          name: "index_conversations_on_inbox_id_and_group_source_id"
```

Campos opcionais para fases futuras:

```ruby
add_column :conversations, :group_description, :text
add_column :conversations, :group_invite_link, :string
add_column :conversations, :group_join_approval_mode, :string
add_column :conversations, :group_suspended, :boolean, default: false, null: false
add_column :conversations, :group_created_at_external, :datetime
add_column :conversations, :group_contacts_synced_at, :datetime
```

Recomendacao inicial:

- implementar somente `group`, `group_source_id`, `group_title`;
- deixar os demais campos para o gerenciamento oficial de grupos.

### GroupContacts

Criar tabela:

```ruby
create_table :group_contacts do |t|
  t.references :account, null: false, foreign_key: true
  t.references :conversation, null: false, foreign_key: true
  t.references :contact, null: false, foreign_key: true
  t.jsonb :metadata, default: {}
  t.timestamps
end

add_index :group_contacts, [:conversation_id, :contact_id],
          unique: true,
          name: "index_group_contacts_on_conversation_id_and_contact_id"
```

`metadata` pode guardar campos opcionais do provider:

```json
{
  "jid": "556699999999",
  "lid": "123456789012345@lid",
  "role": "admin",
  "is_admin": true,
  "picture": "https://cdn.exemplo.com/profile/maria.jpg"
}
```

## 3. Modelos e associacoes

### Conversation

Adicionar:

```ruby
has_many :group_contacts, dependent: :destroy_async
has_many :additional_contacts, through: :group_contacts, source: :contact

scope :group_conversations, -> { where(group: true) }
scope :non_group_conversations, -> { where(group: false) }
```

Helpers:

```ruby
def group?
  group
end

def includes_contact?(target_contact)
  return false if target_contact.blank?
  return true if contact_id == target_contact.id

  group_contacts.exists?(contact_id: target_contact.id)
end

def group_member_count
  group_contacts.count + (contact_id.present? ? 1 : 0)
end
```

Importante:

- No primeiro rollout, manter `contact_id` e `contact_inbox_id` obrigatorios.
- Usar o contato falso legado do grupo como contato primario para reduzir risco.
- Nao tornar `belongs_to :contact` opcional ate auditar todos os call sites.

### GroupContact

Modelo:

```ruby
class GroupContact < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact

  validates :account_id, :conversation_id, :contact_id, presence: true
  validates :contact_id, uniqueness: { scope: :conversation_id }
  validate :conversation_must_be_group
  validate :contact_must_belong_to_account

  before_validation :set_account_id

  private

  def set_account_id
    self.account_id ||= conversation&.account_id
  end

  def conversation_must_be_group
    errors.add(:conversation, "must be a group conversation") if conversation && !conversation.group?
  end

  def contact_must_belong_to_account
    return if contact.blank? || conversation.blank?

    errors.add(:contact, "must belong to the same account") if contact.account_id != conversation.account_id
  end
end
```

## 4. Flag de rollout por inbox

Persistir em `channel_whatsapp.provider_config`:

```json
{
  "use_group_conversation_schema": true
}
```

Comportamento:

- ausente ou `false`: manter comportamento legado;
- `true`: usar schema estruturado para novas mensagens de grupo.

Label sugerida na UI:

```text
Usar novo modelo de conversas em grupo
```

Texto de ajuda:

```text
Armazena grupos como conversas estruturadas, com membros e remetente real. Use
somente com Uno API 3.0.61 ou superior ou canal compatível com grupos Meta-like.
```

## 5. Normalizador de payload de grupo

Criar uma camada independente de provider, para evitar amarrar o core a Uno.

Servico sugerido:

```ruby
Whatsapp::GroupPayloadNormalizer
```

Entrada:

- `processed_params`
- `inbox`

Saida:

```ruby
{
  group: true,
  group_source_id: "120363040468224422@g.us",
  group_title: "Equipe Comercial",
  group_picture: "https://cdn.exemplo.com/groups/120363040468224422.jpg",
  sender_identifier: "556699999999",
  sender_name: "Maria",
  sender_picture: "https://cdn.exemplo.com/profile/maria.jpg",
  message_source_id: "wamid...",
  message_from: "556699999999"
}
```

Deteccao:

```ruby
message = processed_params[:messages]&.first
contact = processed_params[:contacts]&.first

group_source_id = message[:group_id].presence || contact[:group_id].presence
```

Normalizacao:

```ruby
def normalize_group_id(value)
  raw = value.to_s.strip
  return "" if raw.blank?
  return raw if raw.end_with?("@g.us")

  digits = raw.gsub(/\D/, "")
  digits.present? ? "#{digits}@g.us" : raw
end
```

## 6. Adaptacao do inbound WhatsApp/Uno

Arquivos principais:

- `app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb`
- `app/services/whatsapp/incoming_message_unoapi_service.rb`
- `app/services/whatsapp/incoming_message_base_service.rb`

### Fluxo legado

Manter como esta:

- grupo vira contato/contact inbox;
- `message_content` prefixa `*Nome*:`;
- conversa segue parecendo one-to-one.

### Fluxo estruturado

Quando:

```ruby
channel.provider == "unoapi"
channel.provider_config["use_group_conversation_schema"] == true
group_message? == true
```

Executar:

1. Sincronizar participante real como `@contact`.
2. Guardar participante real como `@sender`.
3. Criar/encontrar contato falso do grupo apenas para compatibilidade.
4. Criar/encontrar conversa por `inbox_id + group_source_id`.
5. Marcar conversa como grupo.
6. Criar `GroupContact` do participante.
7. Criar mensagem com `sender: @sender`.
8. Nao prefixar `*Nome*:` no conteudo.

Exemplo de busca/criacao de conversa:

```ruby
def set_group_conversation(group_payload)
  legacy_group_contact_inbox = find_or_create_legacy_group_contact_inbox(group_payload)

  @conversation = Conversation.find_or_initialize_by(
    inbox_id: inbox.id,
    group_source_id: group_payload[:group_source_id]
  )

  @conversation.assign_attributes(
    account_id: inbox.account_id,
    contact_id: legacy_group_contact_inbox.contact_id,
    contact_inbox_id: legacy_group_contact_inbox.id,
    group: true,
    group_title: group_payload[:group_title].presence || group_payload[:group_source_id]
  )

  @conversation.save!
end
```

Criar membro:

```ruby
def sync_group_sender_contact
  @conversation.group_contacts.find_or_create_by!(contact: @sender) do |group_contact|
    group_contact.account_id = @conversation.account_id
    group_contact.metadata = {
      jid: group_payload[:sender_identifier],
      picture: group_payload[:sender_picture]
    }.compact
  end
end
```

Conteudo:

```ruby
def message_content(message)
  content = super(message)
  return content if structured_group_message?

  group_message? && !outgoing_message_type? && @sender ? "*#{@sender.name}*: #{content}" : content
end
```

## 7. Criacao de contato do participante

Participante PN:

```ruby
{
  source_id: "556699999999",
  contact_attributes: {
    name: "Maria",
    phone_number: "+556699999999",
    avatar_url: "https://cdn.exemplo.com/profile/maria.jpg"
  }
}
```

Participante LID:

```ruby
{
  source_id: "123456789012345@lid",
  contact_attributes: {
    name: "Maria",
    email: "123456789012345@lid",
    avatar_url: "https://cdn.exemplo.com/profile/maria.jpg"
  }
}
```

Regra:

- se for PN, normalizar telefone;
- se for LID, preservar `@lid` em `source_id` e usar `email` como identidade;
- se a Uno trouxer PN e LID, guardar LID em metadata.

## 8. Hidratacao de membros via Uno

Servico:

```ruby
Whatsapp::Unoapi::GroupParticipantsSyncService
```

Inputs:

```ruby
inbox:
conversation:
group_source_id:
```

Chamada:

```http
GET /v15.0/{phone}/groups/{groupId}/participants
Authorization: Bearer TOKEN
```

Resposta esperada:

```json
{
  "phone": "556600000000",
  "group": {
    "id": "120363040468224422@g.us",
    "jid": "120363040468224422@g.us",
    "subject": "Equipe Comercial",
    "picture": "https://cdn.exemplo.com/groups/120363040468224422.jpg"
  },
  "participants": [
    {
      "jid": "556699999999",
      "wa_id": "556699999999",
      "name": "Maria",
      "picture": "https://cdn.exemplo.com/profile/maria.jpg",
      "lid": "123456789012345@lid",
      "is_admin": true,
      "role": "admin"
    }
  ]
}
```

Comportamento:

- criar/atualizar contato de cada participante;
- criar `GroupContact`;
- atualizar metadata do membro;
- atualizar `conversation.group_title` se vier `group.subject`;
- opcionalmente atualizar avatar/metadado do grupo;
- tratar `404` como cache miss, nao como erro fatal.

Pseudo:

```ruby
def perform
  response = uno_client.group_participants(phone: phone, group_id: group_source_id)
  return handle_cache_miss if response.not_found?

  response.participants.each do |participant|
    contact_inbox = build_contact_inbox_from_participant(participant)
    conversation.group_contacts.find_or_create_by!(contact: contact_inbox.contact) do |member|
      member.account_id = conversation.account_id
      member.metadata = participant_metadata(participant)
    end
  end

  conversation.update!(group_contacts_synced_at: Time.current) if conversation.respond_to?(:group_contacts_synced_at)
end
```

Gatilhos:

- primeira mensagem de grupo estruturado;
- job periodico para conversas de grupo ativas;
- acao manual futura na UI.

Nao chamar em toda mensagem.

## 9. Outbound para grupo

Arquivo principal:

- `app/services/whatsapp/providers/whatsapp_cloud_service.rb`
- `app/services/whatsapp/providers/unoapi_service.rb`

Regra:

```ruby
if message.conversation.group?
  to = message.conversation.group_source_id
  recipient_type = "group"
else
  to = phone_number
  recipient_type = "individual"
end
```

Payload texto:

```json
{
  "messaging_product": "whatsapp",
  "recipient_type": "group",
  "to": "120363040468224422@g.us",
  "type": "text",
  "text": {
    "body": "Ola pessoal"
  }
}
```

Exemplo Ruby:

```ruby
def recipient_for(message, fallback_phone_number)
  return [message.conversation.group_source_id, "group"] if message.conversation.group?

  [fallback_phone_number, "individual"]
end

def send_text_message(phone_number, message)
  to, recipient_type = recipient_for(message, phone_number)

  payload = {
    messaging_product: "whatsapp",
    recipient_type: recipient_type,
    to: to,
    type: "text",
    text: { body: message.outgoing_content }
  }

  response = HTTParty.post(messages_path, headers: api_headers, body: payload.to_json)
  process_response(response, message)
end
```

Status/update payload:

```ruby
def message_update_payload(message)
  conversation = message[:conversation] || {}

  if conversation[:group] && conversation[:group_source_id].present?
    return {
      messaging_product: "whatsapp",
      status: message[:status],
      message_id: message[:source_id],
      recipient_id: conversation[:group_source_id],
      recipient_type: "group"
    }
  end

  {
    messaging_product: "whatsapp",
    status: message[:status],
    message_id: message[:source_id],
    recipient_id: (message[:sender] || {})[:phone_number],
    recipient_type: "individual"
  }
end
```

## 10. Status inbound de grupo

Payload esperado:

```json
{
  "statuses": [
    {
      "id": "wamid.UNO.abc123",
      "recipient_id": "120363040468224422@g.us",
      "recipient_type": "group",
      "status": "delivered",
      "timestamp": "1710000005"
    }
  ]
}
```

Regra:

- se `recipient_type == "group"`, buscar conversa por
  `inbox_id + group_source_id`;
- buscar mensagem por `source_id`;
- atualizar status;
- nao criar uma atualizacao por participante se o provider mandar status
  agregado.

Pseudo:

```ruby
def process_group_status(status)
  conversation = inbox.conversations.find_by(group: true, group_source_id: status[:recipient_id])
  return if conversation.blank?

  message = conversation.messages.find_by(source_id: status[:id])
  return if message.blank?

  message.update!(status: status[:status])
end
```

## 11. API para frontend

Conversas devem retornar:

```json
{
  "id": 123,
  "group": true,
  "group_title": "Equipe Comercial",
  "group_source_id": "120363040468224422@g.us",
  "group_contacts_count": 42,
  "group_contacts": [
    {
      "id": 1,
      "contact_id": 10,
      "contact": {
        "id": 10,
        "name": "Maria",
        "thumbnail": "https://cdn.exemplo.com/profile/maria.jpg"
      },
      "metadata": {
        "role": "admin",
        "is_admin": true
      }
    }
  ]
}
```

Para lista de conversas:

- retornar `group_contacts_count`;
- retornar no maximo poucos membros de preview;
- nao embutir todos os membros de grupos grandes.

Endpoint paginado:

```http
GET /api/v1/accounts/{account_id}/conversations/{conversation_id}/group_contacts?page=1
```

Resposta:

```json
{
  "meta": {
    "count": 42,
    "current_page": 1
  },
  "payload": [
    {
      "id": 1,
      "contact_id": 10,
      "contact": {
        "id": 10,
        "name": "Maria",
        "thumbnail": "https://cdn.exemplo.com/profile/maria.jpg"
      },
      "metadata": {
        "role": "admin",
        "is_admin": true
      }
    }
  ]
}
```

## 12. UI obrigatoria

Para a nova UI funcionar:

- detectar `conversation.group === true`;
- mostrar `conversation.group_title` no card e cabecalho;
- mostrar icone/avatar de grupo;
- mostrar contador `group_contacts_count`;
- mostrar nome do remetente da mensagem via `message.sender.name`;
- nao depender do texto `*Nome*:` para identificar remetente;
- abrir painel de grupo com membros paginados;
- adicionar traducoes `en` e `pt_BR`.

## 13. UI futura de gerenciamento

Depois do basico:

- atualizar titulo;
- atualizar descricao;
- atualizar foto;
- copiar/resetar link de convite;
- remover participante;
- listar solicitacoes de entrada;
- aprovar/rejeitar solicitacoes;
- sincronizar participantes manualmente.

Essas acoes devem chamar APIs internas do Chatwoot, e o Chatwoot repassa para o
provider quando ele suportar.

## 14. APIs internas futuras de gerenciamento

Exemplos:

```http
GET /api/v1/accounts/{account_id}/conversations/{conversation_id}/group
PATCH /api/v1/accounts/{account_id}/conversations/{conversation_id}/group
GET /api/v1/accounts/{account_id}/conversations/{conversation_id}/group/invite_link
POST /api/v1/accounts/{account_id}/conversations/{conversation_id}/group/invite_link/reset
DELETE /api/v1/accounts/{account_id}/conversations/{conversation_id}/group_contacts
GET /api/v1/accounts/{account_id}/conversations/{conversation_id}/group/join_requests
POST /api/v1/accounts/{account_id}/conversations/{conversation_id}/group/join_requests
DELETE /api/v1/accounts/{account_id}/conversations/{conversation_id}/group/join_requests
POST /api/v1/accounts/{account_id}/conversations/{conversation_id}/group/sync
```

PATCH grupo:

```json
{
  "subject": "Novo nome",
  "description": "Nova descricao",
  "picture": {
    "url": "https://cdn.exemplo.com/nova-foto.jpg"
  }
}
```

DELETE membro:

```json
{
  "participants": [
    "556699999999"
  ]
}
```

## 15. Migracao de historico

Conversas antigas de grupo sao detectadas por:

```ruby
Conversation
  .joins(:contact_inbox)
  .where("contact_inboxes.source_id LIKE ?", "%@g.us")
```

Backfill:

```ruby
conversation.update!(
  group: true,
  group_source_id: conversation.contact_inbox.source_id,
  group_title: conversation.contact.name
)
```

Criar membros historicos:

```ruby
conversation.messages
            .where(sender_type: "Contact")
            .where.not(sender_id: nil)
            .distinct
            .pluck(:sender_id)
            .each do |contact_id|
  next if contact_id == conversation.contact_id

  conversation.group_contacts.find_or_create_by!(contact_id: contact_id) do |member|
    member.account_id = conversation.account_id
  end
end
```

Regras:

- nao reescrever mensagens antigas no primeiro rollout;
- manter contato falso legado como `conversation.contact`;
- opcionalmente enriquecer membros chamando Uno;
- rodar em batches.

## 16. Logs recomendados

Adicionar logs com prefixo claro:

```text
[WHATSAPP][GROUP] structured mode enabled inbox_id=...
[WHATSAPP][GROUP] conversation found group_source_id=...
[WHATSAPP][GROUP] conversation created group_source_id=...
[WHATSAPP][GROUP] sender synced contact_id=...
[WHATSAPP][GROUP] participants sync cache_miss group_source_id=...
[WHATSAPP][GROUP] outbound group message source_id=...
[WHATSAPP][GROUP] status received recipient_id=... status=...
[WHATSAPP][GROUP] legacy fallback reason=...
```

## 17. Testes obrigatorios

Backend:

- inbound grupo legado continua igual quando flag desligada;
- inbound grupo estruturado cria conversa `group: true`;
- inbound grupo estruturado salva `group_source_id` e `group_title`;
- inbound grupo estruturado cria `GroupContact`;
- mensagem nova nao recebe prefixo `*Nome*:`;
- `message.sender` e o participante real;
- outbound grupo envia `recipient_type: "group"` e `to: group_source_id`;
- status grupo atualiza mensagem correta;
- migracao/backfill marca conversas antigas;
- participantes duplicados nao sao criados.

Frontend:

- card usa `group_title`;
- header usa `group_title`;
- bubble mostra nome do remetente via sender;
- painel de grupo lista membros;
- traducoes `pt_BR` nao faltam.

## 18. Ordem de implementacao no Chatwoot

1. Banco e modelos:
   - `group` fields;
   - `group_contacts`;
   - associacoes e validacoes.
2. Flag de rollout:
   - provider_config;
   - UI de config Uno.
3. Normalizador de payload:
   - extrair `group_id`, `group_title`, sender real.
4. Inbound estruturado:
   - criar conversa por `group_source_id`;
   - salvar sender real;
   - criar `GroupContact`;
   - remover prefixo em mensagens novas.
5. API/JSON para UI:
   - `group`, `group_title`, `group_contacts_count`;
   - endpoint paginado de membros.
6. UI:
   - card/header/bubble/painel.
7. Outbound:
   - `recipient_type: "group"`;
   - `to: group_source_id`.
8. Status:
   - `recipient_type: "group"`;
   - busca por `group_source_id`.
9. Hidratacao Uno:
   - job/service de participantes.
10. Migracao historica:
   - backfill de conversas antigas `@g.us`.
11. Gerenciamento futuro:
   - assunto/descricao/foto;
   - convite;
   - remover membros;
   - join requests.

Minimo para ligar a nova UI: itens 1 a 6. Para responder em grupo com o novo
schema, incluir tambem itens 7 e 8.

