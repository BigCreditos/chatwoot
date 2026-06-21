module Whatsapp::BaileysHandlers::Concerns::GroupConversationHandler
  extend ActiveSupport::Concern

  private

  def find_or_create_group_conversation(group_contact_inbox)
    group_contact_inbox.contacts.find_by(inbox_id: group_contact_inbox.id, identifier: group_contact_inbox.identifier)
  end

  def conversation_for_reaction
    nil
  end
end