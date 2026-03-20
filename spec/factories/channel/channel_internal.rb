# frozen_string_literal: true

FactoryBot.define do
  factory :channel_internal, class: 'Channel::Internal' do
    account
  end
end
