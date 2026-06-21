class Channel::Baileys < Channel::Whatsapp
  self.table_name = 'channel_whatsapps'

  validates :phone_number, presence: true, numericality: true

  scope :baileys, -> { where(provider: 'baileys') }
end