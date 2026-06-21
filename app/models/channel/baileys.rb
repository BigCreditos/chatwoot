class Channel::Baileys < Channel::Whatsapp
  self.table_name = 'channel_whatsapp'

  validates :phone_number, presence: true, numericality: true

  scope :baileys, -> { where(provider: 'baileys') }
end